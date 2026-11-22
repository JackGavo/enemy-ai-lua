local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyService = {}

local Enemies = {}
local EnemyByModel = {}
local DeadBodies = {}
local DeadBodySnapshot = {}
local DeadBodySnapshotDirty = true
local LastDeadBodyCleanupTime = 0
local DEAD_BODY_CLEANUP_INTERVAL = 10
local OnEnemyRemovedCallbacks = {}
local PlayerHealthConnections = {}

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local DEFAULT_SHOT_AUDIBLE_DISTANCE = 42
local MAX_SHOT_AUDIBLE_DISTANCE = 150
local MAX_SHOT_VERTICAL_DIFFERENCE = 12
local SHOT_ALERT_COOLDOWN = 0.35
local IMPACT_PROXIMITY_RANGE = 35
local LastShotAlertByPlayer = {}
local LastWitnessAlert = {}
local WITNESS_ALERT_COOLDOWN = 0.75
local ALLY_REINFORCEMENT_RANGE = 80
local ALLY_REINFORCEMENT_COOLDOWN = 3
local LastAllyReinforcementAlert = {}

local Running = false
local ContractActive = false
local UpdateConnection = nil
local Accumulator = 0
local UpdateInterval = 0.05 -- scheduler pulse, not every-enemy update rate
local DEAD_BODY_CLEANUP_DELAY = 30  -- seconds before a body stops being considered investigatable by AI

-- Server-side AI scheduler
-- Each enemy gets an accumulated delta and a next-update deadline. Important enemies
-- update more often, quiet patrol/idle enemies sleep longer. This keeps 50+ enemies
-- from all doing perception/state/movement work on the same 20 Hz pulse.
local DEFAULT_MAX_UPDATES_PER_PULSE = 20
local COMBAT_INTERVAL = 0.06
local ACTIVE_INTERVAL = 0.08
local PATROL_INTERVAL = 0.15
local IDLE_INTERVAL = 0.25
local FAR_IDLE_INTERVAL = 0.45
local FAR_PLAYER_DISTANCE = 180

local SchedulerIndex = 1
local EnemySchedule = {}
local CachedPlayerCharacters = {}
local PlayerCharacterCacheTime = 0
local PLAYER_CACHE_INTERVAL = 0.25
local OPTICAL_CAMOUFLAGE_ATTRIBUTE = "OpticalCamouflageActive"

local function isCharacterCamouflaged(character)
	return character ~= nil and character:GetAttribute(OPTICAL_CAMOUFLAGE_ATTRIBUTE) == true
end

local function disconnectPlayerHealthConnections(player)
	local connections = PlayerHealthConnections[player]
	if not connections then return end
	for i = 1, #connections do
		connections[i]:Disconnect()
	end
	PlayerHealthConnections[player] = nil
end

local function clearEnemyTargetsForCharacter(character)
	if not character then return end
	for i = 1, #Enemies do
		local enemy = Enemies[i]
		if enemy and not enemy.IsDead then
			if enemy.Perception then
				if enemy.Perception.VisibleTarget == character then
					enemy.Perception.VisibleTarget = nil
				end
				if enemy.Perception.PursuitTarget == character then
					enemy.Perception.PursuitTarget = nil
				end
				enemy.Perception.WasVisible = false
				enemy.Perception.LastKnownPosition = nil
				enemy.Perception.InvestigationPoint = nil
			end
			if enemy.Target == character then
				enemy.Target = nil
			end
			enemy.LastKnownPosition = nil
			if enemy.Combat then
				enemy.Combat:EndCombat()
			end
			if enemy.Movement then
				enemy.Movement:Stop()
			end
			if enemy.AI then
				enemy.AI:SetState("Idle")
			end
		end
	end
end

local function restorePlayerHealth(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = humanoid.MaxHealth
	end
end

local function watchPlayerCharacter(player, character)
	disconnectPlayerHealthConnections(player)
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	PlayerHealthConnections[player] = {
		humanoid.HealthChanged:Connect(function(health)
			if health <= 1 then
				clearEnemyTargetsForCharacter(character)
				EnemyService.OnPlayerDown(player, character)
			end
		end),
	}
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		watchPlayerCharacter(player, character)
	end)
	if player.Character then
		watchPlayerCharacter(player, player.Character)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	disconnectPlayerHealthConnections(player)
	LastShotAlertByPlayer[player] = nil
end)

for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(character)
		watchPlayerCharacter(player, character)
	end)
	if player.Character then
		watchPlayerCharacter(player, player.Character)
	end
end

local ShotOcclusionRaycastParams = RaycastParams.new()
ShotOcclusionRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshPlayerCharacterCache()
	local now = os.clock()
	if now - PlayerCharacterCacheTime < PLAYER_CACHE_INTERVAL then
		return CachedPlayerCharacters
	end
	PlayerCharacterCacheTime = now
	CachedPlayerCharacters = {}

	local players = Players:GetPlayers()
	for i = 1, #players do
		local character = players[i].Character
		if character and character.Parent then
			local root = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 1 and not isCharacterCamouflaged(character) then
				table.insert(CachedPlayerCharacters, {
					Character = character,
					Position = root.Position,
				})
			end
		end
	end

	return CachedPlayerCharacters
end

local function getEnemyPosition(enemy)
	local model = enemy and enemy.Model
	if not model then return nil end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then return root.Position end
	return model:GetPivot().Position
end

local function isCharacterDowned(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid == nil or humanoid.Health <= 1
end

local function getCharacterRootPosition(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function getShotAudibleDistance(weaponInstance)
	local defaultDistance = DEFAULT_SHOT_AUDIBLE_DISTANCE
	if not weaponInstance then
		return defaultDistance
	end

	local config = weaponInstance:FindFirstChild("Configuration") or weaponInstance:FindFirstChild("Config")
	if config then
		local value = config:FindFirstChild("ShotAudibleDistance")
		if value and value:IsA("NumberValue") and value.Value > 0 then
			return math.min(value.Value, MAX_SHOT_AUDIBLE_DISTANCE)
		end
	end

	local attrValue = weaponInstance:GetAttribute("ShotAudibleDistance")
	if typeof(attrValue) == "number" and attrValue > 0 then
		return math.min(attrValue, MAX_SHOT_AUDIBLE_DISTANCE)
	end

	return math.min(defaultDistance, MAX_SHOT_AUDIBLE_DISTANCE)
end

local function canHearShotFrom(enemyPosition, shotOrigin, audibleDistance, shooterCharacter, enemyModel)
	if not enemyPosition or not shotOrigin then return false end
	if math.abs(enemyPosition.Y - shotOrigin.Y) > MAX_SHOT_VERTICAL_DIFFERENCE then
		return false
	end

	local flatEnemy = Vector3.new(enemyPosition.X, 0, enemyPosition.Z)
	local flatShot = Vector3.new(shotOrigin.X, 0, shotOrigin.Z)
	if (flatEnemy - flatShot).Magnitude > audibleDistance then
		return false
	end

	-- Floor/wall occlusion: if there is solid geometry between the shot and the NPC,
	-- heavily restrict the audible radius. This prevents enemies on other floors/rooms
	-- reacting to every shot like they have perfect map-wide hearing.
	ShotOcclusionRaycastParams.FilterDescendantsInstances = { shooterCharacter, enemyModel }
	local result = workspace:Raycast(shotOrigin, enemyPosition - shotOrigin, ShotOcclusionRaycastParams)
	if result and result.Instance and result.Instance.CanCollide then
		return (flatEnemy - flatShot).Magnitude <= math.min(audibleDistance * 0.35, 12)
	end

	return true
end

local function shouldThrottleShotAlert(player)
	local now = os.clock()
	local last = LastShotAlertByPlayer[player]
	if last and now - last < SHOT_ALERT_COOLDOWN then
		return true
	end
	LastShotAlertByPlayer[player] = now
	return false
end

local function shouldThrottleWitnessAlert(enemy)
	local now = os.clock()
	local last = LastWitnessAlert[enemy]
	if last and now - last < WITNESS_ALERT_COOLDOWN then
		return true
	end
	LastWitnessAlert[enemy] = now
	return false
end

local function getDeathWitnessPosition(deadEnemy, fallbackPosition)
	local model = deadEnemy and deadEnemy.Model
	if not model then return fallbackPosition end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return fallbackPosition or model:GetPivot().Position
end

local function forceEnemyEngagePlayer(enemy, character)
	if not enemy or enemy.IsDead or not enemy.Perception or not character then return end
	if isCharacterDowned(character) then return end
	local rootPosition = getCharacterRootPosition(character)
	if not rootPosition then return end

	enemy.Target = character
	enemy.LastKnownPosition = rootPosition
	enemy.Perception.VisibleTarget = character
	enemy.Perception.LastKnownPosition = rootPosition
	enemy.Perception.InvestigationPoint = nil
	enemy.Perception.WasVisible = true

	if enemy.Combat then
		enemy.Combat:BeginAlertPosture(rootPosition)
	end
	if enemy.AI then
		enemy.AI:Evaluate()
	end
end

local function notifyWitnessesOfEnemyHit(victimEnemy, shooterCharacter, eventPosition, wasKilled)
	if not victimEnemy or not victimEnemy.Model or not shooterCharacter then return end
	if isCharacterDowned(shooterCharacter) then return end

	local victimModel = victimEnemy.Model
	local victimPosition = eventPosition or getEnemyPosition(victimEnemy)
	local shooterPosition = getCharacterRootPosition(shooterCharacter)
	if not victimPosition or not shooterPosition then return end

	for i = 1, #Enemies do
		local witness = Enemies[i]
		if witness and witness ~= victimEnemy and not witness.IsDead and witness.Perception and witness.Model and witness.Model.Parent then
			local witnessPosition = getEnemyPosition(witness)
			if witnessPosition
				and math.abs(witnessPosition.Y - victimPosition.Y) <= MAX_SHOT_VERTICAL_DIFFERENCE
				and math.abs(witnessPosition.Y - shooterPosition.Y) <= MAX_SHOT_VERTICAL_DIFFERENCE
			then
				local seesVictim = witness.Perception:CanSeeBody(victimModel)
				local seesShooter = witness.Perception:CanSeeTarget(shooterCharacter)
				if seesVictim and seesShooter and not shouldThrottleWitnessAlert(witness) then
					forceEnemyEngagePlayer(witness, shooterCharacter)
				elseif wasKilled and seesVictim and not shouldThrottleWitnessAlert(witness) then
					-- The witness saw the victim die but did not see the shooter.
					-- If they are not already fighting, investigate where the shot came from.
					if witness:GetState() ~= "Combat" then
						witness.Perception.InvestigationPoint = shooterPosition
						witness.Perception.LastKnownPosition = nil
						if witness.AI then
							witness.AI:Evaluate()
						end
					end
				end
			end
		end
	end
end


local function getNearestPlayerDistance(enemy)
	local enemyPosition = getEnemyPosition(enemy)
	if not enemyPosition then return math.huge end

	local players = refreshPlayerCharacterCache()
	local nearest = math.huge
	for i = 1, #players do
		local distance = (players[i].Position - enemyPosition).Magnitude
		if distance < nearest then
			nearest = distance
		end
	end
	return nearest
end

local function getEnemyState(enemy)
	if enemy and enemy.AI then
		return enemy:GetState()
	end
	return "Idle"
end

local function getUpdateIntervalForEnemy(enemy)
	if not enemy or enemy.IsDead then
		return FAR_IDLE_INTERVAL
	end

	local state = getEnemyState(enemy)
	if state == "Combat" or state == "TargetFlee" then
		return COMBAT_INTERVAL
	end
	if state == "Search" or state == "Investigate" or state == "Pursuing" or enemy.Target or (enemy.Perception and (enemy.Perception:HasVisibleTarget() or enemy.Perception:HasPursuitTarget())) then
		return ACTIVE_INTERVAL
	end
	if state == "Patrol" then
		return PATROL_INTERVAL
	end

	if getNearestPlayerDistance(enemy) > FAR_PLAYER_DISTANCE then
		return FAR_IDLE_INTERVAL
	end
	return IDLE_INTERVAL
end

local function resetSchedule(enemy, initialDelay)
	if not enemy then return end
	EnemySchedule[enemy] = {
		Elapsed = 0,
		NextUpdate = initialDelay or 0,
		Interval = IDLE_INTERVAL,
	}
end

local function removeSchedule(enemy)
	EnemySchedule[enemy] = nil
end

function EnemyService.Start()
	if Running then return end
	Running = true
	Accumulator = 0

	UpdateConnection = RunService.Heartbeat:Connect(function(DeltaTime)
		if not ContractActive then
			Accumulator = 0
			return
		end

		Accumulator += DeltaTime
		if Accumulator >= UpdateInterval then
			EnemyService.Update(Accumulator)
			Accumulator = 0
		end
	end)
end

function EnemyService.Stop()
	Running = false

	if UpdateConnection then
		UpdateConnection:Disconnect()
		UpdateConnection = nil
	end

	-- Ensure no AI work continues after the service is stopped.
	EnemyService.SetContractActive(false)

	-- Destroy all active enemies
	for _, enemy in ipairs(Enemies) do
		enemy:Destroy()
	end

	Enemies = {}
	EnemyByModel = {}
	DeadBodies = {}
	DeadBodySnapshot = {}
	DeadBodySnapshotDirty = true
	LastDeadBodyCleanupTime = 0
	EnemySchedule = {}
	SchedulerIndex = 1
	CachedPlayerCharacters = {}
	PlayerCharacterCacheTime = 0
	PlayerHealthConnections = {}
	LastAllyReinforcementAlert = {}
end

function EnemyService.SetContractActive(IsActive)
	ContractActive = IsActive == true
	Accumulator = 0

	if ContractActive then
		for i = 1, #Enemies do
			local enemy = Enemies[i]
			if enemy and not enemy.IsDead then
				if enemy.Model then
					enemy.Model:SetAttribute("AIDisabled", false)
				end
				if enemy.AI then
					enemy.AI:Evaluate()
				end
			end
		end
	else
		EnemyService.ResetActiveEnemyState()
	end
end

function EnemyService.IsContractActive()
	return ContractActive
end

function EnemyService.ResetActiveEnemyState()
	for i = 1, #Enemies do
		local enemy = Enemies[i]
		if enemy and not enemy.IsDead then
			if enemy.Model then
				enemy.Model:SetAttribute("AIDisabled", true)
			end
			if enemy.Perception then
				enemy.Perception.VisibleTarget = nil
				enemy.Perception.PursuitTarget = nil
				enemy.Perception.LastKnownPosition = nil
				enemy.Perception.InvestigationPoint = nil
				enemy.Perception.WasVisible = false
			end
			enemy.Target = nil
			enemy.LastKnownPosition = nil
			enemy.SearchTimer = 0
			enemy.InvestigateTimer = 0
			enemy.SearchPhase = nil
			enemy.InvestigatePhase = nil
			enemy.SearchCenter = nil
			enemy.SearchPointsVisited = 0
			enemy.NextSearchPointTime = 0
			enemy.SearchPauseTimer = 0
			enemy.DiscoveredBodies = {}
			enemy.BodyCheckTimer = 0
			if enemy.Animator then
				enemy.Animator:SetSearching(false)
			end
			if enemy.Combat then
				enemy.Combat:EndCombat()
			end
			if enemy.Movement then
				enemy.Movement:Stop()
			end
			if enemy.AI then
				enemy.AI:SetState("Idle")
			end
		end
	end
end

function EnemyService.DestroyAllEnemies()
	EnemyService.SetContractActive(false)

	for i = #Enemies, 1, -1 do
		local enemy = Enemies[i]
		if enemy then
			EnemyService.UnregisterEnemy(enemy)
			enemy:Destroy()
		end
	end

	Enemies = {}
	EnemyByModel = {}
	DeadBodies = {}
	DeadBodySnapshot = {}
	DeadBodySnapshotDirty = true
	LastDeadBodyCleanupTime = 0
	EnemySchedule = {}
	SchedulerIndex = 1
	LastAllyReinforcementAlert = {}
end

function EnemyService.RegisterEnemy(Enemy)
	table.insert(Enemies, Enemy)
	-- Stagger initial updates so newly spawned groups do not all run perception on
	-- the same scheduler pulse.
	local initialDelay = (#Enemies % DEFAULT_MAX_UPDATES_PER_PULSE) * (UpdateInterval / DEFAULT_MAX_UPDATES_PER_PULSE)
	resetSchedule(Enemy, initialDelay)
	if Enemy.Model then
		EnemyByModel[Enemy.Model] = Enemy
		Enemy.Model:SetAttribute("AIDisabled", not ContractActive)
	end
	if ContractActive and Enemy.AI and not Enemy.IsDead then
		Enemy.AI:Evaluate()
	elseif not ContractActive then
		if Enemy.AI then
			Enemy.AI:SetState("Idle")
		elseif Enemy.Movement then
			Enemy.Movement:Stop()
		end
	end
end

function EnemyService.UnregisterEnemy(Enemy)
	removeSchedule(Enemy)
	for i = #Enemies, 1, -1 do
		local e = Enemies[i]
		if e == Enemy then
			table.remove(Enemies, i)
			break
		end
	end
	if Enemy.Model then
		EnemyByModel[Enemy.Model] = nil
	end
	LastWitnessAlert[Enemy] = nil
	LastAllyReinforcementAlert[Enemy] = nil

	-- Notify subscribers (e.g. Encounter) so they can clean up per-enemy state.
	for i = 1, #OnEnemyRemovedCallbacks do
		OnEnemyRemovedCallbacks[i](Enemy)
	end
end

function EnemyService.RegisterDeadBody(Model)
	if not Model then return end
	DeadBodies[Model] = os.clock()
	DeadBodySnapshotDirty = true
end

function EnemyService.UnregisterDeadBody(Model)
	if not Model then return end
	DeadBodies[Model] = nil
	DeadBodySnapshotDirty = true
end

function EnemyService.GetDeadBodies()
	local now = os.clock()
	if DeadBodySnapshotDirty or now - LastDeadBodyCleanupTime >= DEAD_BODY_CLEANUP_INTERVAL then
		DeadBodySnapshotDirty = false
		LastDeadBodyCleanupTime = now
		DeadBodySnapshot = {}

		for model, deathTime in DeadBodies do
			if not model or not model.Parent then
				DeadBodies[model] = nil
			elseif now - deathTime <= DEAD_BODY_CLEANUP_DELAY then
				table.insert(DeadBodySnapshot, model)
			else
				DeadBodies[model] = nil
			end
		end
	end

	return DeadBodySnapshot
end

function EnemyService.RestorePlayerHealth(Player)
	restorePlayerHealth(Player)
end

-- Register a callback invoked whenever an enemy is removed from the system.
function EnemyService.OnEnemyRemoved(Callback)
	table.insert(OnEnemyRemovedCallbacks, Callback)
end

function EnemyService.ClearEnemyTarget(Enemy)
	if not Enemy or Enemy.IsDead then return end

	if Enemy.Perception then
		Enemy.Perception.VisibleTarget = nil
		Enemy.Perception.PursuitTarget = nil
		Enemy.Perception.WasVisible = false
		Enemy.Perception.LastKnownPosition = nil
		Enemy.Perception.InvestigationPoint = nil
	end

	Enemy.Target = nil
	Enemy.LastKnownPosition = nil

	if Enemy.Combat then
		Enemy.Combat:EndCombat()
		Enemy.Combat:EndAlertPosture()
	end

	if Enemy.Movement then
		Enemy.Movement:Stop()
	end

	if Enemy.AI then
		Enemy.AI:SetState("Idle")
	end
end

function EnemyService.GetEnemy(Model)
	return EnemyByModel[Model]
end

function EnemyService.NotifyEnemyDeath(deadEnemy, deathPosition)
	if not deadEnemy or not deadEnemy.Model then
		return 0
	end

	local witnessCount = 0
	local bodyPosition = getDeathWitnessPosition(deadEnemy, deathPosition)
	for i = 1, #Enemies do
		local witness = Enemies[i]
		if witness
			and witness ~= deadEnemy
			and not witness.IsDead
			and witness.Model
			and witness.Model.Parent
			and witness.Perception
		then
			local witnessPosition = getEnemyPosition(witness)
			if witnessPosition and bodyPosition then
				local handled = false
				-- Vision-based detection: enemies on the same vertical level that can see the body
				if math.abs(witnessPosition.Y - bodyPosition.Y) <= MAX_SHOT_VERTICAL_DIFFERENCE then
					if typeof(witness.NotifyWitnessedDeath) == "function" then
						handled = witness:NotifyWitnessedDeath(deadEnemy, bodyPosition)
					elseif witness.Perception:CanSeeBody(deadEnemy.Model) and witness:GetState() ~= "Combat" then
						witness.Perception.InvestigationPoint = bodyPosition
						witness.Perception.LastKnownPosition = nil
						if witness.AI then
							witness.AI:Evaluate()
						end
						handled = true
					end
				end
				-- Hearing-based detection: if the witness didn't see the body but is
				-- within hearing range, turn toward the body and investigate if visible.
				if not handled and typeof(witness.HearGuardDeath) == "function" then
					local hearingRange = (witness.Perception and witness.Perception.HearingRange) or 30
					local flatDist = (Vector3.new(witnessPosition.X, 0, witnessPosition.Z) - Vector3.new(bodyPosition.X, 0, bodyPosition.Z)).Magnitude
					if flatDist <= hearingRange then
						handled = witness:HearGuardDeath(deadEnemy, bodyPosition)
					end
				end
				if handled then
					witnessCount += 1
				end
			end
		end
	end

	return witnessCount
end

function EnemyService.ClearEnemyTargetsForCharacter(character)
	clearEnemyTargetsForCharacter(character)
end

function EnemyService.GetPlayerCharacters()
	return refreshPlayerCharacterCache()
end

function EnemyService.HandlePlayerShot(player, weaponInstance, fireInfo, hitInfo)
	if not ContractActive then
		return
	end
	if not player then
		return
	end
	local isHitAlert = hitInfo ~= nil
	if (not isHitAlert) and shouldThrottleShotAlert(player) then
		return
	end

	local character = player.Character
	if not character or isCharacterDowned(character) or isCharacterCamouflaged(character) then
		return
	end

	local shotOrigin = nil
	if typeof(fireInfo) == "table" then
		if typeof(fireInfo.origin) == "Vector3" then
			shotOrigin = fireInfo.origin
		elseif typeof(fireInfo.o) == "Vector3" then
			shotOrigin = fireInfo.o
		end
	end
	shotOrigin = shotOrigin or getCharacterRootPosition(character)
	if not shotOrigin then
		return
	end

	local hitPart = hitInfo and hitInfo.part
	local hitPoint = hitInfo and hitInfo.p
	local audibleDistance = getShotAudibleDistance(weaponInstance)

	for i = 1, #Enemies do
		local enemy = Enemies[i]
		if enemy and not enemy.IsDead and enemy.Perception then
			local enemyPosition = getEnemyPosition(enemy)
			local isDirectHit = hitPart ~= nil and enemy.Model ~= nil and hitPart:IsDescendantOf(enemy.Model)
			if isDirectHit then
				notifyWitnessesOfEnemyHit(enemy, character, enemyPosition or hitPoint, false)
				task.delay(0.15, function()
					local humanoid = enemy.Model and enemy.Model:FindFirstChildOfClass("Humanoid")
					if enemy.IsDead or (humanoid and humanoid.Health <= 0) then
						notifyWitnessesOfEnemyHit(enemy, character, getEnemyPosition(enemy) or hitPoint, true)
					end
				end)
			end
			-- Gunshot hearing only applies to enemies within the weapon's audible range
			-- that are not already in combat. Enemies already engaging the player don't
			-- need to react to gunshots — they already know where the shooter is.
			if enemy:GetState() ~= "Combat" then
				local heardShot = enemyPosition and (isDirectHit or canHearShotFrom(enemyPosition, shotOrigin, audibleDistance, character, enemy.Model))
				if heardShot then
					if isDirectHit then
						enemy:ReactToShot(shotOrigin, character, true, hitPoint)
					else
						enemy:ReactToShot(shotOrigin, character, false, hitPoint)
					end
				elseif hitPoint and enemyPosition and not isDirectHit then
					-- Proximity impact reaction: if the bullet landed close to this enemy
					-- (within IMPACT_PROXIMITY_RANGE), the enemy turns toward the shooter,
					-- raycasts with generous range (no FOV cone), and either engages or
					-- investigates the impact point. This works regardless of facing direction.
					local flatEnemy = Vector3.new(enemyPosition.X, 0, enemyPosition.Z)
					local flatImpact = Vector3.new(hitPoint.X, 0, hitPoint.Z)
					local impactDistance = (flatImpact - flatEnemy).Magnitude
					if impactDistance <= IMPACT_PROXIMITY_RANGE then
						enemy:ReactToNearbyImpact(shotOrigin, character, hitPoint)
					elseif enemy.Perception:CanSeePoint(hitPoint) then
						-- Visual impact investigation: if the enemy can see where the shot
						-- landed (the impact point), they should investigate where it came from.
						-- This covers cases where the enemy is too far to hear the gunshot but
						-- witnesses the bullet impact on a nearby wall or object.
						enemy:ReactToShot(shotOrigin, character, false, hitPoint)
					end
				end
			end
		end
	end
end

-- Notify nearby allies when an enemy fires at the player, so they can move
-- to reinforce. Event-driven (only called when an enemy actually fires) and
-- throttled per-ally to avoid performance issues with many enemies.
function EnemyService.NotifyAllyReinforcement(firingEnemy, targetCharacter)
	if not ContractActive then return end
	if not firingEnemy or not targetCharacter then return end

	local targetHrp = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetHrp then return end
	local playerPosition = targetHrp.Position

	local firingPosition = getEnemyPosition(firingEnemy)
	if not firingPosition then return end

	for i = 1, #Enemies do
		local ally = Enemies[i]
		if ally
			and ally ~= firingEnemy
			and not ally.IsDead
			and ally.Model
			and ally.Model.Parent
			and ally.Perception
		then
			-- Skip allies already in combat or with a visible target
			if ally:GetState() == "Combat" then
				-- already engaged
			elseif ally.Perception:HasVisibleTarget() then
				-- already sees the player
			else
				local allyPosition = getEnemyPosition(ally)
				if allyPosition then
					-- Only reinforce allies within range of the firing enemy
					local flatDist = (Vector3.new(allyPosition.X, 0, allyPosition.Z)
						- Vector3.new(firingPosition.X, 0, firingPosition.Z)).Magnitude
					if flatDist <= ALLY_REINFORCEMENT_RANGE
						and math.abs(allyPosition.Y - firingPosition.Y) <= MAX_SHOT_VERTICAL_DIFFERENCE
					then
						-- Throttle per-ally
						local now = os.clock()
						local last = LastAllyReinforcementAlert[ally]
						if not last or now - last >= ALLY_REINFORCEMENT_COOLDOWN then
							LastAllyReinforcementAlert[ally] = now
							if typeof(ally.RespondToAllyCombat) == "function" then
								ally:RespondToAllyCombat(playerPosition, targetCharacter)
							end
						end
					end
				end
			end
		end
	end
end

function EnemyService.GetEnemies()
	return Enemies
end

function EnemyService.OnPlayerDown(_player, character)
	clearEnemyTargetsForCharacter(character)

	-- Stop active AI reactions when the player's existing Health == 1 death flow starts.
	-- This does not destroy enemies or bodies; it only clears combat/search state so
	-- 50+ enemies do not keep shooting/pathing during the death UI/retry flow.
	EnemyService.SetContractActive(false)

	for i = 1, #Enemies do
		local enemy = Enemies[i]
		if enemy and not enemy.IsDead then
			if enemy.Perception then
				if character and enemy.Perception.VisibleTarget == character then
					enemy.Perception.VisibleTarget = nil
				end
				if character and enemy.Perception.PursuitTarget == character then
					enemy.Perception.PursuitTarget = nil
				end
				enemy.Perception.LastKnownPosition = nil
				enemy.Perception.InvestigationPoint = nil
				enemy.Perception.WasVisible = false
			end
			enemy.Target = nil
			enemy.LastKnownPosition = nil
			if enemy.Combat then
				enemy.Combat:EndCombat()
			end
			if enemy.Movement then
				enemy.Movement:Stop()
			end
			if enemy.AI then
				enemy.AI:SetState("Idle")
			end
		end
	end
end

function EnemyService.Update(DeltaTime)
	if not ContractActive then
		return
	end

	local enemyCount = #Enemies
	if enemyCount == 0 then
		return
	end

	-- Accumulate elapsed time for every living enemy, then spend a small update
	-- budget in round-robin order. This prevents 50 enemies from all running full
	-- perception/state/movement work on the same frame while keeping combat actors
	-- responsive through shorter intervals.
	for i = 1, enemyCount do
		local enemy = Enemies[i]
		local schedule = EnemySchedule[enemy]
		if not schedule then
			resetSchedule(enemy, 0)
			schedule = EnemySchedule[enemy]
		end
		if schedule then
			schedule.Elapsed += DeltaTime
			schedule.NextUpdate -= DeltaTime
		end
	end

	local toRemove = {}
	local updatesThisPulse = 0
	local maxUpdates = math.max(DEFAULT_MAX_UPDATES_PER_PULSE, math.ceil(enemyCount * 0.25))
	local checked = 0

	while checked < enemyCount and updatesThisPulse < maxUpdates do
		if SchedulerIndex > #Enemies then
			SchedulerIndex = 1
		end

		local enemy = Enemies[SchedulerIndex]
		SchedulerIndex += 1
		checked += 1

		if not enemy or not enemy.Model or not enemy.Model.Parent then
			if enemy then
				table.insert(toRemove, enemy)
			end
		elseif enemy.IsDead then
			table.insert(toRemove, enemy)
		else
			local schedule = EnemySchedule[enemy]
			if schedule and schedule.NextUpdate <= 0 then
				local elapsed = schedule.Elapsed
				schedule.Elapsed = 0
				schedule.Interval = getUpdateIntervalForEnemy(enemy)
				schedule.NextUpdate = schedule.Interval

				enemy:Update(elapsed)
				updatesThisPulse += 1

				if enemy.IsDead then
					table.insert(toRemove, enemy)
				end
			end
		end
	end

	-- Remove destroyed/dead enemies from the active AI service.
	for i = 1, #toRemove do
		local enemy = toRemove[i]
		EnemyService.UnregisterEnemy(enemy)
		enemy:Destroy()
	end
end

local Perception = require(script.Parent.Perception)
if Perception and typeof(Perception.SetEnemyService) == "function" then
	Perception.SetEnemyService(EnemyService)
end

return EnemyService