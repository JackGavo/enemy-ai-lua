local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Enemy = {}
Enemy.__index = Enemy

local StateController = require(script.Parent.StateController)
local Perception = require(script.Parent.Perception)
local Movement = require(script.Parent.Movement)
local Combat = require(script.Parent.Combat)
local EnemyAnimator = require(script.Parent.EnemyAnimator)
local TargetBehaviour = require(script.Parent.TargetBehaviour)
local EnemyConfig = require(script.Parent.EnemyConfig)
local EnemyAudio = require(script.Parent.EnemyAudio)
local EnemyDebug = require(script.Parent.EnemyDebug)
local AmmoService = require(script.Parent.Parent.Parent:WaitForChild("AmmoService"))
local EnemyService = require(script.Parent.EnemyService)
local EventsService = require(script.Parent.Parent.Parent.Events.EventsService)

local SEARCH_DURATION = 15
local SEARCH_RADIUS = 25
local SEARCH_MAX_POINTS = 4
local SEARCH_POINT_COOLDOWN = 0.75

local INVESTIGATE_DURATION = 10
local INVESTIGATE_RADIUS = 15
local BODY_INVESTIGATE_DURATION = 10
local BODY_INVESTIGATE_REISSUE_INTERVAL = 0.75
local BODY_INVESTIGATE_REACH_DISTANCE = 0.75
local BODY_INVESTIGATE_RETURN_DISTANCE = 0.75

local BodySightRaycastParams = RaycastParams.new()
BodySightRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function flatDistance(a, b)
	if not a or not b then return math.huge end
	local offset = a - b
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

local function getModelPosition(model)
	if not model then return nil end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return model:GetPivot().Position
end

function Enemy.new(Model)
	local self = setmetatable({}, Enemy)

	self.Model = Model

	self.State = nil
	self.Target = nil
	self.LastKnownPosition = nil

	self.SpawnPoint = nil
	self.AssignedPath = nil

	if self.Model and (not self.IsDead) then
		EnemyService.UnregisterDeadBody(self.Model)
	end

	self.Config = nil
	self.Perception = nil
	self.BehaviourTree = nil
	self.Movement = nil
	self.Combat = nil
	self.Audio = nil

	self.IsDead = false
	self.IsTarget = false
	self.TargetBehaviour = nil
	self.TargetFleeTimer = 0
	self.TargetHasEscaped = false
	self.DeathTime = nil
	self.DiscoveredBodies = {}
	self.BodyCheckTimer = 0
	self.Connections = {}
	self.CleanedUpDeath = false

	self.BodyInvestigation = nil
	self.BodyInvestigationCooldown = {}
	self.BodyInvestigationReturnPoint = nil

	self.NextWeaponRecoveryTime = 0

	-- Alert/search timers
	self.SearchTimer = 0
	self.InvestigateTimer = 0
	self.SearchPhase = nil
	self.InvestigatePhase = nil
	self.SearchCenter = nil
	self.SearchPointsVisited = 0
	self.NextSearchPointTime = 0
	self.SearchPauseTimer = 0

	self.AI = StateController.new(self)
	self:SetupStates()

	return self
end

function Enemy:SetupStates()

	self.AI:AddState("TargetFlee", {

		Priority = 95,

		CanRun = function(Enemy)

			return TargetBehaviour.ShouldFlee(Enemy)

		end,

		Enter = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(true)
			end
			if Enemy.Audio then
				Enemy.Audio:PlayBark("Flee", 1)
			end
			TargetBehaviour.BeginFlee(Enemy)

		end,

		Update = function(Enemy, DeltaTime)

			TargetBehaviour.UpdateFlee(Enemy, DeltaTime)

		end,

		Exit = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(false)
			end
			Enemy.TargetFleeTimer = 0

		end,

	})


	self.AI:AddState("TargetSurrender", {

		Priority = 95,

		CanRun = function(Enemy)

			return TargetBehaviour.ShouldSurrender(Enemy)

		end,

		Enter = function(Enemy)

			if Enemy.Audio then
				Enemy.Audio:PlayBark("Surrender", 1)
			end
			TargetBehaviour.BeginSurrender(Enemy)

		end,

		Update = function(Enemy, DeltaTime)

			TargetBehaviour.UpdateSurrender(Enemy, DeltaTime)

		end,

	})


	self.AI:AddState("Combat", {

		Priority = 100,

		CanRun = function(Enemy)

			return Enemy.Combat ~= nil
				and Enemy.Perception ~= nil
				and TargetBehaviour.ShouldUseCombat(Enemy)
				and Enemy.Perception:HasVisibleTarget()

		end,

		Enter = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(true)
			end
			TargetBehaviour.BeginCombat(Enemy)
			if Enemy.Audio then
				Enemy.Audio:PlayBark("Combat", 1)
			end
			if Enemy.Combat then
				Enemy.Combat:BeginCombat()
			end

		end,

		Update = function(Enemy, DeltaTime)

			if Enemy.Combat then
				Enemy.Combat:Update(DeltaTime)
			end

		end,

		Exit = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(false)
			end
			TargetBehaviour.EndCombat(Enemy)
			if Enemy.Combat then
				Enemy.Combat:EndCombat()
			end

		end,

	})


	self.AI:AddState("Pursuing", {

		Priority = 90,

		CanRun = function(Enemy)

			return Enemy.Perception ~= nil
				and Enemy.Perception:HasPursuitTarget()
				and not Enemy.Perception:HasVisibleTarget()

		end,

		Enter = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(true)
			end
			if Enemy.Audio then
				Enemy.Audio:PlayBark("Combat", 1)
			end
			if Enemy.Model then
				Enemy.Model:SetAttribute("EnemyFeedbackState", "Pursuing")
			end
			local target = Enemy.Perception:GetPursuitTarget()
			if target and Enemy.Combat then
				local hrp = target:FindFirstChild("HumanoidRootPart")
				if hrp then
					Enemy.Combat:BeginAlertPosture(hrp.Position)
				end
			end

		end,

		Update = function(Enemy, DeltaTime)

			if not Enemy.Perception then return end
			local target = Enemy.Perception:GetPursuitTarget()
			if not target or not target.Parent then return end

			local hrp = target:FindFirstChild("HumanoidRootPart")
			if not hrp then return end

			local targetPos = hrp.Position

			-- Face the target FIRST (BeginAlertPosture sets hrp.CFrame via FaceTarget),
			-- THEN issue movement. If we move first and override CFrame afterwards, the
			-- humanoid loses its internal movement momentum every tick. This matches
			-- the Combat state's ordering: face target, then move.
			if Enemy.Combat then
				Enemy.Combat:BeginAlertPosture(targetPos)
			end

			if Enemy.Movement then
				Enemy.Movement:SetRunning(true)
				Enemy.Movement:MoveToDirect(targetPos)
			end

		end,

		Exit = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(false)
			end
			if Enemy.Model then
				Enemy.Model:SetAttribute("EnemyFeedbackState", nil)
			end
			if Enemy.Combat then
				Enemy.Combat:EndAlertPosture()
			end

		end,

	})


	self.AI:AddState("BodyInvestigate", {

		Priority = 75,

		CanRun = function(Enemy)

			return Enemy.BodyInvestigation ~= nil
				and Enemy.Perception ~= nil
				and not Enemy.Perception:HasLastKnownPosition()

		end,

		Enter = function(Enemy)

			Enemy:BeginBodyInvestigation()

		end,

		Update = function(Enemy, DeltaTime)

			Enemy:UpdateBodyInvestigation(DeltaTime)

		end,

		Exit = function(Enemy)

			Enemy:ExitBodyInvestigation()

		end,

	})


	self.AI:AddState("Investigate", {

		Priority = 80,

		CanRun = function(Enemy)

			return Enemy.Perception ~= nil and Enemy.Perception:HasInvestigationPoint()

		end,

		Enter = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(true)
			end
			local config = Enemy.Config or {}
			Enemy.InvestigateTimer = config.InvestigateDuration or INVESTIGATE_DURATION
			Enemy.InvestigatePhase = "moving"
			if Enemy.Audio then
				Enemy.Audio:PlayBark("Investigate", 1)
			end
			if Enemy.Model then
				Enemy.Model:SetAttribute("EnemyFeedbackState", "Investigating")
			end
			if Enemy.Combat then
				Enemy.Combat:BeginAlertPosture(Enemy.Perception:GetInvestigationPoint())
			end
			if Enemy.Movement then
				Enemy.Movement:MoveTo(
					Enemy.Perception:GetInvestigationPoint()
				)
			else
				Enemy.Perception.InvestigationPoint = nil
			end

		end,

		Update = function(Enemy, DeltaTime)

			if not Enemy.Perception then return end
			Enemy.InvestigateTimer -= DeltaTime
			if Enemy.InvestigateTimer <= 0 then
				Enemy.Perception.InvestigationPoint = nil
				return
			end

			if not Enemy.Movement or Enemy.Movement:HasFailed() then
				Enemy.Perception.InvestigationPoint = nil
				return
			end

			-- Play the search stance while standing still at the investigation point.
			if Enemy.Animator then
				Enemy.Animator:SetSearching(not Enemy.Movement:IsMoving())
			end

			local investigationPoint = Enemy.Perception:GetInvestigationPoint()
			if Enemy.CameraInvestigationPoint and investigationPoint then
				Enemy.Perception.InvestigationPoint = Enemy.CameraInvestigationPoint
				investigationPoint = Enemy.CameraInvestigationPoint
				if Enemy.Movement and Enemy.Movement:IsMoving() then
					Enemy.Movement:MoveTo(investigationPoint)
				end
			end
			if Enemy.Combat and investigationPoint then
				Enemy.Combat:BeginAlertPosture(investigationPoint)
			end

			-- When we reach the investigation point, search the nearby area
			if not Enemy.Movement:IsMoving() then
				local ip = Enemy.Perception:GetInvestigationPoint()
				if Enemy.CameraInvestigationPoint and ip then
					if flatDistance(Enemy.Movement:GetPosition(), Enemy.CameraInvestigationPoint) > 2 then
						Enemy.Movement:MoveTo(Enemy.CameraInvestigationPoint)
						return
					end
					Enemy.CameraInvestigationPoint = nil
				end
				if ip then
					Enemy:PickSearchPoint(ip, (Enemy.Config and Enemy.Config.InvestigateRadius) or INVESTIGATE_RADIUS)
				end
			end

		end,

		Exit = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(false)
			end
			if Enemy.Animator then
				Enemy.Animator:SetSearching(false)
			end
			if Enemy.Model then
				Enemy.Model:SetAttribute("EnemyFeedbackState", nil)
			end
			if Enemy.Combat then
				Enemy.Combat:EndAlertPosture()
			end
			if Enemy.Movement then
				Enemy.Movement:Stop()
			end
			Enemy.InvestigateTimer = 0
			Enemy.InvestigatePhase = nil
			Enemy.CameraInvestigationPoint = nil

		end,

	})


	self.AI:AddState("Search", {

		Priority = 88,

		CanRun = function(Enemy)

			return Enemy.Perception ~= nil and Enemy.Perception:HasLastKnownPosition()

		end,

		Enter = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(true)
			end
			local config = Enemy.Config or {}
			Enemy.SearchTimer = config.SearchDuration or SEARCH_DURATION
			Enemy.SearchPhase = "movingToLastKnown"
			Enemy.SearchCenter = Enemy.Perception:GetLastKnownPosition()
			Enemy.SearchPointsVisited = 0
			Enemy.NextSearchPointTime = 0
			Enemy.SearchPauseTimer = 0
			if Enemy.Audio then
				Enemy.Audio:PlayBark("Search", 1)
			end
			if Enemy.Model then
				Enemy.Model:SetAttribute("EnemyFeedbackState", "Searching")
			end

			if Enemy.Combat then
				Enemy.Combat:BeginAlertPosture(Enemy.SearchCenter)
			end

			if Enemy.SearchCenter and Enemy.Movement then
				Enemy.Movement:MoveTo(Enemy.SearchCenter)
			else
				Enemy:FinishSearch()
			end

		end,

		Update = function(Enemy, DeltaTime)

			Enemy.SearchTimer -= DeltaTime
			if Enemy.SearchTimer <= 0 then
				Enemy:FinishSearch()
				return
			end

			-- Combat has higher priority and will take over on the next evaluation,
			-- but stop spending search work as soon as the player is visible again.
			if Enemy.Perception:HasVisibleTarget() then
				return
			end

			if not Enemy.SearchCenter then
				Enemy.SearchCenter = Enemy.Perception:GetLastKnownPosition()
				if not Enemy.SearchCenter then
					Enemy:FinishSearch()
					return
				end
			end

			local movement = Enemy.Movement
			if not movement or movement:HasFailed() then
				Enemy:FinishSearch()
				return
			end

			if Enemy.SearchPhase == "movingToLastKnown" then
				if Enemy.Combat and Enemy.SearchCenter then
					Enemy.Combat:BeginAlertPosture(Enemy.SearchCenter)
				end
				if (not movement:IsMoving()) or movement:HasReachedDestination() then
					-- Check if we actually got close to the last known position.
					-- Pathfinding can return NoPath (e.g. elevated target) and the
					-- fallback grounded move may stop short. If we are still far
					-- from the search center, re-issue MoveTo periodically to keep
					-- trying instead of immediately giving up and searching random
					-- points around a location we never reached.
					local currentPos = movement:GetPosition()
					local reachThreshold = movement.MoveToReachThreshold or 4
					if currentPos and Enemy.SearchCenter
						and flatDistance(currentPos, Enemy.SearchCenter) > reachThreshold
						and not movement:HasFailed() then

						local now = os.clock()
						if now >= (Enemy.NextSearchReissueTime or 0) then
							Enemy.NextSearchReissueTime = now + 1.0
							movement:MoveTo(Enemy.SearchCenter)
						end
						return
					end

					-- Reached the last known position (or cannot get closer): pause
					-- and play the search stance before sweeping the surrounding area.
					Enemy.SearchPhase = "pausingAtLastKnown"
					Enemy.SearchPauseTimer = (Enemy.Config and Enemy.Config.SearchPauseDuration) or 2.5
				end
				return
			end

			if Enemy.SearchPhase == "pausingAtLastKnown" then
				if Enemy.Animator then
					Enemy.Animator:SetSearching(true)
				end
				Enemy.SearchPauseTimer -= DeltaTime
				if Enemy.SearchPauseTimer <= 0 then
					Enemy.SearchPhase = "searchingArea"
					Enemy:MoveToNextSearchPoint()
				end
				return
			end

			if Enemy.SearchPhase == "searchingArea" then
				local currentDestination = movement:GetCurrentDestination()
				if Enemy.Combat and currentDestination then
					Enemy.Combat:BeginAlertPosture(currentDestination)
				end
				-- Search stance while standing still between search points.
				if Enemy.Animator then
					Enemy.Animator:SetSearching(not movement:IsMoving())
				end
				local now = os.clock()
				local maxPoints = (Enemy.Config and Enemy.Config.SearchMaxPoints) or SEARCH_MAX_POINTS
				if Enemy.SearchPointsVisited >= maxPoints and not movement:IsMoving() then
					Enemy:FinishSearch()
					return
				end

				if (not movement:IsMoving()) and now >= Enemy.NextSearchPointTime then
					Enemy:MoveToNextSearchPoint()
				end
			end

		end,

		Exit = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(false)
			end
			if Enemy.Animator then
				Enemy.Animator:SetSearching(false)
			end
			if Enemy.Combat then
				Enemy.Combat:EndAlertPosture()
			end
			if Enemy.Movement then
				Enemy.Movement:Stop()
			end
			Enemy.SearchTimer = 0
			Enemy.SearchPhase = nil
			Enemy.SearchCenter = nil
			Enemy.SearchPointsVisited = 0
			Enemy.NextSearchPointTime = 0
			Enemy.SearchPauseTimer = 0
			Enemy.NextSearchReissueTime = 0

		end,

	})


	self.AI:AddState("Patrol", {

		Priority = 10,

		CanRun = function(Enemy)

			return Enemy.Movement ~= nil and Enemy.AssignedPath ~= nil and Enemy.AssignedPath.Parent ~= nil

		end,

		Enter = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(false)
				Enemy.Movement:FollowPath(
					Enemy.AssignedPath
				)
			end

		end,

		Exit = function(Enemy)

			Enemy.Movement:Stop()

		end,

	})


	self.AI:AddState("Idle", {

		Priority = 5,

		CanRun = function(Enemy)

			-- Fallback state: always available when no other state applies
			return true

		end,

		Enter = function(Enemy)

			if Enemy.Movement then
				Enemy.Movement:SetRunning(false)
				Enemy.Movement:Stop()
			end

		end,

	})


	self.AI:AddState("Dead", {

		Priority = 1000,

		CanRun = function(Enemy)

			if not Enemy.Model then return false end
			local humanoid = Enemy.Model:FindFirstChildOfClass("Humanoid")
			if not humanoid then return false end
			return humanoid.Health <= 0

		end,

		Enter = function(Enemy)

			Enemy:HandleDeath()

		end,

	})

end

function Enemy:Initialize()
	-- Resolve per-enemy configuration once at initialization. Modules read from
	-- this table instead of repeatedly walking attributes/folders every AI tick.
	self.Config = EnemyConfig.Resolve(self.Model)
	EnemyConfig.ApplyAttributes(self.Model, self.Config)

	-- Create subsystem instances
	self.IsTarget = TargetBehaviour.IsTargetModel(self.Model)
	self.TargetBehaviour = TargetBehaviour.GetBehaviour(self)

	-- Match the useful part of the Marine reference AI: keep NPC movement owned by
	-- the server. This avoids client network ownership jitter where enemies tilt or
	-- animate inconsistently while the server is driving Humanoid movement/combat.
	local root = self.Model and self.Model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end

	self.Perception = Perception.new(self)
	self.Movement = Movement.new(self)
	self.Combat = Combat.new(self)
	self.Animator = EnemyAnimator.new(self)
	self.Audio = EnemyAudio.new(self)

	-- Equip a weapon when this NPC can fight. Fleeing/surrendering targets stay lightweight.
	if TargetBehaviour.ShouldEquipWeapon(self) then
		self.Combat:EquipWeapon()
	end

	-- Read AssignedPath from model (set by EnemyGeneration)
	local pathValue = self.Model:FindFirstChild("AssignedPath")
	if pathValue and pathValue:IsA("ObjectValue") then
		self.AssignedPath = pathValue.Value
	end

	-- One Humanoid.Died connection per enemy catches deaths immediately instead of waiting
	-- for the next service tick. It is disconnected in HandleDeath/Destroy.
	local humanoid = self.Model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(self.Connections, humanoid.Died:Connect(function()
			self:HandleDeath()
		end))
	end

	-- Evaluate initial state (will pick Patrol if AssignedPath exists)
	self.AI:Evaluate()
end

function Enemy:Update(DeltaTime)
	-- Dead or unexpectedly removed enemies don't update
	if self.IsDead then return end
	if not self.Model or not self.Model.Parent then
		self.IsDead = true
		return
	end

	self:ValidateRuntimeState()

	if self.Model then
		local humanoid = self.Model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= 0 then
			self:HandleDeath()
			return
		end
	end

	-- Update perception first so state evaluation has fresh data
	if self.Perception then
		self.Perception:Update(DeltaTime)
	end
	self.AI:Update(DeltaTime)
	-- Update movement after AI so any new state Enter calls take effect first
	if self.Movement then
		self.Movement:Update(DeltaTime)
	end
	if self.Animator then
		self.Animator:Update(DeltaTime)
	end

	if self.Audio then
		self.Audio:Update(DeltaTime)
	end

	-- Visual debug overlay (only renders when GameConfig.Debug.EnableEnemyAIDebug is true)
	EnemyDebug:Update(self)

	-- Body discovery check (timer-based for performance, every 1 second)
	-- Only for living, non-combat enemies. If this enemy already has the player's
	-- last known location, do not let body discovery interrupt that urgent search.
	-- Dedicated BodyInvestigate witnesses are handled immediately on death and should not
	-- be interrupted by rediscovering the same body every polling tick.
	local hasLastKnownPosition = self.Perception ~= nil and self.Perception:HasLastKnownPosition()
	if not self.IsDead and self.AI and not hasLastKnownPosition and self.AI:GetState() ~= "Combat" and self.AI:GetState() ~= "BodyInvestigate" and self.AI:GetState() ~= "Pursuing" and self.AI:GetState() ~= "Search" then
		self.BodyCheckTimer += DeltaTime
		if self.BodyCheckTimer >= 1.0 then
			self.BodyCheckTimer = 0
			self:CheckForBodies()
		end
	end
end

function Enemy:ValidateRuntimeState()
	-- Target/character disappeared, left the map, or became downed: clear active targeting.
	local target = self.Target
	if target and (not target.Parent) then
		self.Target = nil
		self.LastKnownPosition = nil
	end

	if self.Perception then
		local visible = self.Perception.VisibleTarget
		if visible and (not visible.Parent) then
			self.Perception.VisibleTarget = nil
			self.Perception.WasVisible = false
		end
		local humanoid = visible and visible:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= 1 then
			self.Perception.VisibleTarget = nil
			self.Perception.WasVisible = false
		end

		local pursuit = self.Perception.PursuitTarget
		if pursuit and (not pursuit.Parent) then
			self.Perception.PursuitTarget = nil
		end
		local pursuitHumanoid = pursuit and pursuit:FindFirstChildOfClass("Humanoid")
		if pursuitHumanoid and pursuitHumanoid.Health <= 1 then
			self.Perception.PursuitTarget = nil
		end
	end

	-- Assigned path was removed by map unload / bad map setup.
	if self.AssignedPath and not self.AssignedPath.Parent then
		self.AssignedPath = nil
		if self.Movement then
			self.Movement:Stop()
		end
	end

	-- Movement failed repeatedly. For active combat/pursuit, do not immediately
	-- abandon a valid target; clear the failure and let the current state re-issue
	-- a fresh direct/pathfinding chase on the next update. For investigation/search
	-- targets, fail gracefully so NPCs do not path forever to unreachable points.
	if self.Movement and self.Movement:HasFailed() then
		local state = self:GetState()
		local canStillEngage = false
		if self.Perception then
			canStillEngage = self.Perception:HasVisibleTarget() or self.Perception:HasPursuitTarget()
		end
		if (state == "Combat" or state == "Pursuing") and canStillEngage then
			self.Movement:ClearFailure()
			if self.Movement then
				self.Movement:SetRunning(true)
			end
			return
		end
		if state == "BodyInvestigate" or self.BodyInvestigation then
			if self.Audio then
				self.Audio:PlayBark("ReturnToPost", 0.35)
			end
			self.BodyInvestigation = nil
			self.BodyInvestigationReturnPoint = nil
			if self.Model then
				self.Model:SetAttribute("EnemyFeedbackState", nil)
			end
		end
		if self.Perception then
			self.Perception.InvestigationPoint = nil
			if self:GetState() == "Search" then
				self.Perception.LastKnownPosition = nil
			end
		end
		self.LastKnownPosition = nil
		self.Target = nil
		self.Movement:Stop()
		self.Movement:ClearFailure()
	end

	-- Weapon disappeared while a fighter is alive: try to re-equip through Combat,
	-- but throttle attempts so a missing/bad weapon config does not create 20Hz work.
	if self.Combat and (not self.Combat.Weapon or not self.Combat.Weapon.Parent) and TargetBehaviour.ShouldEquipWeapon(self) then
		local now = os.clock()
		if now >= (self.NextWeaponRecoveryTime or 0) then
			self.NextWeaponRecoveryTime = now + 2
			self.Combat:EquipWeapon()
		end
	end
end

-- Check for visible dead bodies and fire BodyDiscovered events for new ones
function Enemy:CheckForBodies()
	if not self.Perception then return end

	local visibleBodies = self.Perception:GetVisibleBodies()
	for _, bodyModel in ipairs(visibleBodies) do
		if not self.DiscoveredBodies[bodyModel] then
			self.DiscoveredBodies[bodyModel] = true

			local hrp = bodyModel:FindFirstChild("HumanoidRootPart")
			local position = hrp and hrp.Position or bodyModel:GetPivot().Position

			EventsService:FireEvent("BodyDiscovered", {
				Position = position,
				Body = bodyModel,
				Discoverer = self.Model,
			})
			if self.Audio then
				self.Audio:PlayBark("BodyFound", 1)
			end

			if self:GetState() ~= "Combat" and self:GetState() ~= "BodyInvestigate" and not (self.Perception and self.Perception:HasLastKnownPosition()) then
				self:RequestBodyInvestigation(bodyModel, position, "BodyDiscovered")
			end
		end
	end
end

local function applyPendingExplosionDeathImpulse(model)
	if not model or not model.Parent or model:GetAttribute("PendingExplosionDeathImpulse") ~= true then return end

	local origin = model:GetAttribute("ExplosionDeathOrigin")
	if typeof(origin) ~= "Vector3" then return end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end

	local strength = math.clamp(tonumber(model:GetAttribute("ExplosionDeathStrength")) or 0.5, 0.15, 1)
	local offset = root.Position - origin
	local flatDirection = Vector3.new(offset.X, 0, offset.Z)
	if flatDirection.Magnitude < 0.05 then
		flatDirection = root.CFrame.LookVector
	end
	flatDirection = flatDirection.Unit

	-- Enable physics-style states for the corpse only. Movement disables these while
	-- enemies are alive to prevent accidental launches, but explosion deaths should get
	-- a controlled cinematic blast kick after AI cleanup begins.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, true) end)
		pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true) end)
		pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true) end)
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
		pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Physics) end)
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
		end
	end

	local horizontalSpeed = 28 + (24 * strength)
	local upwardSpeed = 16 + (14 * strength)
	local impulseVelocity = (flatDirection * horizontalSpeed) + Vector3.new(0, upwardSpeed, 0)

	root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + impulseVelocity
	root.AssemblyAngularVelocity = root.AssemblyAngularVelocity + Vector3.new(
		math.random(-4, 4),
		math.random(-6, 6),
		math.random(-4, 4)
	)
	root:ApplyImpulse(impulseVelocity * root.AssemblyMass)

	model:SetAttribute("PendingExplosionDeathImpulse", false)
end

function Enemy:CanSeeBodyAtDeath(bodyModel, bodyPosition)
	if self.IsDead then return false end
	if not self.Model or not self.Model.Parent or not bodyModel or bodyModel == self.Model then return false end

	local humanoid = self.Model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	local perception = self.Perception
	if perception and typeof(perception.CanSeeBody) == "function" and bodyModel.Parent then
		if perception:CanSeeBody(bodyModel) then
			return true
		end
	end

	local originPart = perception and perception:GetOriginPart()
	originPart = originPart or self.Model:FindFirstChild("HumanoidRootPart")
	if not originPart or not originPart:IsA("BasePart") then return false end

	local targetPosition = bodyPosition or getModelPosition(bodyModel)
	if not targetPosition then return false end

	-- Close-range bypass: if the body is within 15 studs (flat), the enemy can
	-- sense it regardless of facing direction — peripheral vision, the sound of
	-- a body falling, etc. Only line-of-sight matters at this distance.
	local flatOffset = Vector3.new(targetPosition.X - originPart.Position.X, 0, targetPosition.Z - originPart.Position.Z)
	if flatOffset.Magnitude <= 15 then
		BodySightRaycastParams.FilterDescendantsInstances = { self.Model, bodyModel }
		local result = Workspace:Raycast(originPart.Position, targetPosition - originPart.Position, BodySightRaycastParams)
		return result == nil
	end

	if perception and typeof(perception.IsTargetWithinVisionCone) == "function" then
		if not perception:IsTargetWithinVisionCone(originPart, targetPosition) then
			return false
		end
	else
		local offset = targetPosition - originPart.Position
		if offset.Magnitude > 80 then return false end
	end

	BodySightRaycastParams.FilterDescendantsInstances = { self.Model, bodyModel }
	local result = Workspace:Raycast(originPart.Position, targetPosition - originPart.Position, BodySightRaycastParams)
	return result == nil
end

function Enemy:RequestBodyInvestigation(bodyModel, bodyPosition, reason)
	if self.IsDead then return false end
	if not self.Model or not self.Model.Parent then return false end
	if not bodyModel or bodyModel == self.Model then return false end
	if self:GetState() == "Combat" then return false end
	if self.Perception and (self.Perception:HasVisibleTarget() or self.Perception:HasLastKnownPosition()) then return false end

	local point = bodyPosition or getModelPosition(bodyModel)
	if not point then return false end

	local now = os.clock()
	local lastTime = self.BodyInvestigationCooldown[bodyModel]
	if lastTime and now - lastTime < 2 then
		return false
	end
	self.BodyInvestigationCooldown[bodyModel] = now

	local returnPoint = nil
	if self.Movement then
		returnPoint = self.Movement:GetPosition()
	end
	returnPoint = returnPoint or getModelPosition(self.Model)

	self.BodyInvestigation = {
		Body = bodyModel,
		Point = point,
		ReturnPoint = returnPoint,
		Reason = reason or "EnemyDeath",
		Phase = "movingToBody",
		WaitTimer = BODY_INVESTIGATE_DURATION,
		MoveReissueTimer = 0,
		StartedAt = now,
	}
	self.BodyInvestigationReturnPoint = returnPoint

	if self.Perception then
		self.Perception.InvestigationPoint = nil
	end
	self.Target = nil

	if self.AI then
		self.AI:Evaluate()
		-- Evaluate() can trigger the Dead state's Enter -> HandleDeath ->
		-- NotifyEnemyDeath cascade, which may destroy this enemy (setting
		-- self.AI to nil). Re-check self.AI before accessing it.
		if self.AI and self.AI:GetState() == "BodyInvestigate" then
			self.AI:SetState("BodyInvestigate")
		end
	end

	return true
end

function Enemy:BeginBodyInvestigation()
	local info = self.BodyInvestigation
	if not info then return end

	if self.Movement then
		self.Movement.MoveToReachThreshold = BODY_INVESTIGATE_REACH_DISTANCE
		self.Movement:SetRunning(true)
		self.Movement:MoveTo(info.Point)
	end
	if self.Model then
		self.Model:SetAttribute("EnemyFeedbackState", "BodyInvestigating")
	end
	if self.Animator then
		self.Animator:SetSearching(false)
	end
	if self.Audio then
		self.Audio:PlayBark("BodyInvestigate", 1)
	end
	if self.Combat then
		self.Combat:BeginAlertPosture(info.Point)
	end
	info.Phase = info.Phase or "movingToBody"
	info.MoveReissueTimer = 0
end

function Enemy:UpdateBodyInvestigation(deltaTime)
	local info = self.BodyInvestigation
	if not info then return end

	-- Combat/Search can take over naturally via higher-priority perception states. If
	-- the player becomes visible during the body check, abandon body investigation.
	if self.Perception and self.Perception:HasVisibleTarget() then
		self.BodyInvestigation = nil
		return
	end

	local movement = self.Movement
	if not movement or movement:HasFailed() then
		self.BodyInvestigation = nil
		if movement then
			movement:ClearFailure()
		end
		return
	end

	if info.Body and not info.Body.Parent then
		info.Body = nil
	end

	if info.Phase == "movingToBody" then
		if self.Combat then
			self.Combat:BeginAlertPosture(info.Point)
		end
		info.MoveReissueTimer = (info.MoveReissueTimer or 0) - deltaTime
		if info.MoveReissueTimer <= 0 then
			info.MoveReissueTimer = BODY_INVESTIGATE_REISSUE_INTERVAL
			local bodyPoint = (info.Body and getModelPosition(info.Body)) or info.Point
			if bodyPoint then
				if flatDistance(bodyPoint, info.Point) > 0.5 then
					info.Point = bodyPoint
				end
				movement:MoveTo(info.Point)
			end
		end
		if self.Model then
			self.Model:SetAttribute("EnemyFeedbackState", "BodySearching")
		end
		local currentPosition = movement:GetPosition()
		if currentPosition and flatDistance(currentPosition, info.Point) <= BODY_INVESTIGATE_REACH_DISTANCE then
			info.Phase = "waitingAtBody"
			info.WaitTimer = BODY_INVESTIGATE_DURATION
			movement:Stop()
			movement:SetRunning(false)
			if self.Audio then
				self.Audio:PlayBark("BodyFound", 0.6)
			end
			if self.Animator then
				self.Animator:SetSearching(true)
			end
		end
		return
	end

	if info.Phase == "waitingAtBody" then
		if self.Animator then
			self.Animator:SetSearching(true)
		end
		if self.Combat then
			self.Combat:BeginAlertPosture(info.Point)
		end
		info.WaitTimer -= deltaTime
		if info.WaitTimer <= 0 then
			if info.ReturnPoint then
				info.Phase = "returning"
				movement.MoveToReachThreshold = nil
				movement:SetRunning(false)
				movement:MoveTo(info.ReturnPoint)
				if self.Model then
					self.Model:SetAttribute("EnemyFeedbackState", "Returning")
				end
				if self.Audio then
					self.Audio:PlayBark("ReturnToPost", 0.7)
				end
				if self.Animator then
					self.Animator:SetSearching(false)
				end
			else
				self.BodyInvestigation = nil
			end
		end
		return
	end

	if info.Phase == "returning" then
		if (not movement:IsMoving()) or movement:HasReachedDestination() or flatDistance(movement:GetPosition(), info.ReturnPoint) <= BODY_INVESTIGATE_RETURN_DISTANCE then
			self.BodyInvestigation = nil
			if self.AI then
				self.AI:Evaluate()
			end
		end
		return
	end
end

function Enemy:ExitBodyInvestigation()
	if self.Movement then
		self.Movement.MoveToReachThreshold = nil
		self.Movement:SetRunning(false)
	end
	if self.Model then
		self.Model:SetAttribute("EnemyFeedbackState", nil)
	end
	if self.Animator then
		self.Animator:SetSearching(false)
	end
	if self.Combat then
		self.Combat:EndAlertPosture()
	end
	if self.Perception then
		self.Perception.InvestigationPoint = nil
	end
end

function Enemy:NotifyWitnessedDeath(deadEnemy, deathPosition)
	if not deadEnemy or deadEnemy == self then return false end
	local bodyModel = deadEnemy.Model
	if not bodyModel then return false end
	if not self:CanSeeBodyAtDeath(bodyModel, deathPosition) then return false end
	return self:RequestBodyInvestigation(bodyModel, deathPosition, "WitnessedDeath")
end

function Enemy:HandleDeath()
	if self.CleanedUpDeath then return end
	self.CleanedUpDeath = true
	self.IsDead = true
	self.DeathTime = self.DeathTime or os.clock()

	local model = self.Model
	local deathPosition = getModelPosition(model)
	if model and model:GetAttribute("AmmoDropSpawned") ~= true then
		model:SetAttribute("AmmoDropSpawned", true)
		local dropAmount = 30
		if self.Combat and tonumber(self.Combat.AmmoCapacity) then
			dropAmount = self.Combat.AmmoCapacity
		end
		AmmoService.SpawnAmmoDrop(model, dropAmount)
	end
	EnemyService.NotifyEnemyDeath(self, deathPosition)
	if self.Audio then
		self.Audio:PlayBark("Death", 0)
		self.Audio:Destroy()
		self.Audio = nil
	end

	if model then
		self.BodyInvestigation = nil
		self.BodyInvestigationReturnPoint = nil
		model:SetAttribute("EnemyDead", true)
		model:SetAttribute("AIDisabled", true)
		model:SetAttribute("DeathTime", self.DeathTime)


		-- Remove any server-created/world-parented visual state immediately. Client
		-- awareness billboards are handled separately by EnemyAwarenessFeedback.
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BillboardGui") and (descendant.Name == "AwarenessIndicator" or descendant.Name == "SurrenderPlaceholder" or descendant.Name == "TargetFleePlaceholder") then
				descendant.Parent = nil
			end
		end

		EnemyService.RegisterDeadBody(model)
	end

	for i = 1, #self.Connections do
		self.Connections[i]:Disconnect()
	end
	self.Connections = {}

	if self.Perception then
		self.Perception.VisibleTarget = nil
		self.Perception.LastKnownPosition = nil
		self.Perception.InvestigationPoint = nil
	end
	self.Target = nil
	self.LastKnownPosition = nil

	if self.Movement then
		self.Movement:Stop()
	end
	if self.Combat then
		self.Combat:DropWeapon()
		self.Combat:Destroy()
		self.Combat = nil
	end
	if self.Animator then
		self.Animator:Destroy()
		self.Animator = nil
	end

	EnemyDebug:Clear(self)

	if model then
		applyPendingExplosionDeathImpulse(model)

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
			humanoid.AutoRotate = false
		end
	end
end

function Enemy:Destroy()
	for i = 1, #self.Connections do
		self.Connections[i]:Disconnect()
	end
	self.Connections = {}

	if self.AI then
		self.AI:Destroy()
	end
	if self.Movement then
		self.Movement:Destroy()
	end
	if self.Combat then
		self.Combat:Destroy()
	end
	if self.Audio then
		self.Audio:Destroy()
		self.Audio = nil
	end

	EnemyDebug:Destroy(self)

	self.Perception = nil
	self.Movement = nil
	self.Combat = nil
	self.Animator = nil
	self.AI = nil
	self.Model = nil
	self.BodyInvestigation = nil
	self.BodyInvestigationReturnPoint = nil
	self.BodyInvestigationCooldown = {}
	self.DiscoveredBodies = {}
end

function Enemy:SetState(State)
	if self.IsDead then return end
	if not self.AI then return end
	self.AI:SetState(State)
end

function Enemy:GetState()
	if not self.AI then return nil end
	return self.AI:GetState()
end

function Enemy:SetTarget(Target)
	if self.IsDead then return end
	self.Target = Target
end

function Enemy:ReactToShot(shotOrigin, suspectedTarget, wasHit, hitPoint)
	if self.IsDead then return end
	if not self.Perception then return end

	if self.Audio then
		self.Audio:PlayBark(wasHit and "Combat" or "Investigate", 1)
	end

	self.Perception:ReactToShot(shotOrigin, suspectedTarget, wasHit, hitPoint)

	if self.AI then
		self.AI:Evaluate()
		local currentState = self.AI:GetState()
		if currentState == "Investigate" and self.Perception:HasInvestigationPoint() then
			self.AI:SetState("Investigate")
		elseif currentState == "Search" and self.Perception:HasVisibleTarget() then
			self.AI:Evaluate()
		end
	end
end

-- React to gunfire heard from anywhere on the map (no distance limit).
-- The enemy turns toward the shot origin, raycasts to check if the shooter is
-- visible, and engages if so. Otherwise investigates the origin point.
function Enemy:ReactToDistantShot(shotOrigin, suspectedTarget)
	if self.IsDead then return end
	if not self.Perception then return end

	if self.Audio then
		self.Audio:PlayBark("Investigate", 1)
	end

	self.Perception:ReactToDistantShot(shotOrigin, suspectedTarget)

	if self.AI then
		self.AI:Evaluate()
		local currentState = self.AI:GetState()
		if currentState == "Investigate" and self.Perception:HasInvestigationPoint() then
			self.AI:SetState("Investigate")
		elseif currentState == "Combat" and self.Perception:HasVisibleTarget() then
			-- Already engaging
		end
	end
end

-- React to a bullet impact that landed nearby. The enemy turns toward the
-- shooter, raycasts with generous range (no FOV cone), and either engages or
-- investigates the impact point.
function Enemy:ReactToNearbyImpact(shotOrigin, suspectedTarget, impactPoint)
	if self.IsDead then return end
	if not self.Perception then return end

	if self.Audio then
		self.Audio:PlayBark("Investigate", 1)
	end

	self.Perception:ReactToNearbyImpact(shotOrigin, suspectedTarget, impactPoint)

	if self.AI then
		self.AI:Evaluate()
		local currentState = self.AI:GetState()
		if currentState == "Investigate" and self.Perception:HasInvestigationPoint() then
			self.AI:SetState("Investigate")
		end
	end
end

-- Called when this enemy hears a guard die nearby (within hearing range).
-- The enemy turns toward the dead guard, raycasts to see the body, and if
-- visible, goes to investigate the body.
function Enemy:HearGuardDeath(deadEnemy, deathPosition)
	if self.IsDead then return false end
	if not deadEnemy or deadEnemy == self then return false end
	if not self.Perception then return false end
	if not self.Model or not self.Model.Parent then return false end

	local bodyModel = deadEnemy.Model
	if not bodyModel then return false end

	-- Already in combat: don't interrupt to investigate a body
	if self:GetState() == "Combat" then return false end

	-- Already investigating this body: don't re-trigger
	if self.BodyInvestigation and self.BodyInvestigation.Body == bodyModel then
		return false
	end

	-- Turn toward the dead guard's position
	self.Perception:FacePosition(deathPosition)

	-- After turning, raycast to see if the dead body is visible
	if self:CanSeeBodyAtDeath(bodyModel, deathPosition) then
		if self.Audio then
			self.Audio:PlayBark("BodyFound", 1)
		end
		return self:RequestBodyInvestigation(bodyModel, deathPosition, "HeardDeath")
	end

	-- Heard the death but cannot see the body: investigate the death position
	self.Perception.InvestigationPoint = deathPosition
	self.Perception.LastKnownPosition = nil
	if self.AI then
		self.AI:Evaluate()
	end
	return true
end

-- Alert this enemy to the player's last known position (used by the Encounter
-- system when a nearby enemy confirms the player). Sets the last known position
-- so the AI transitions toward it (Search -> Combat if the player is seen).
function Enemy:Alert(position, target)
	if self.IsDead then return end
	if not position then return end
	if self.Perception then
		self.Perception.LastKnownPosition = position
		self.Perception.InvestigationPoint = nil
	end
	self.LastKnownPosition = position
	if target then
		self.Target = target
	end
end

-- Called when a nearby ally fires at the player. Sets the player's last known
-- position so the Search state moves this enemy toward the combat area.
-- Overridable by direct combat (Combat priority 100 > Search priority 60).
function Enemy:RespondToAllyCombat(playerPosition, targetCharacter)
	if self.IsDead then return end
	if not self.Model or not self.Model.Parent then return end
	if self:GetState() == "Combat" then return end
	if self.Perception and self.Perception:HasVisibleTarget() then return end
	if not playerPosition then return end

	-- Set last known position to the player's position to trigger Search state
	if self.Perception then
		self.Perception.LastKnownPosition = playerPosition
		self.Perception.InvestigationPoint = nil
	end
	self.LastKnownPosition = playerPosition

	if targetCharacter then
		self.Target = targetCharacter
	end

	if self.Audio then
		self.Audio:PlayBark("Investigate", 0.5)
	end

	if self.AI then
		self.AI:Evaluate()
	end
end

function Enemy:GetTarget()
	return self.Target
end

function Enemy:FinishSearch()
	if self.Perception then
		self.Perception.LastKnownPosition = nil
	end
	self.Target = nil
	self.LastKnownPosition = nil
	self.SearchTimer = 0
	self.SearchPhase = nil
	self.SearchCenter = nil
	self.SearchPointsVisited = 0
	self.NextSearchPointTime = 0
	self.SearchPauseTimer = 0
	self.NextSearchReissueTime = 0
	if self.Animator then
		self.Animator:SetSearching(false)
	end
	if self.Movement then
		self.Movement:Stop()
	end
end

function Enemy:MoveToNextSearchPoint()
	if self.IsDead then return end
	if not self.SearchCenter then
		self:FinishSearch()
		return
	end
	local maxPoints = (self.Config and self.Config.SearchMaxPoints) or SEARCH_MAX_POINTS
	if self.SearchPointsVisited >= maxPoints then
		self:FinishSearch()
		return
	end

	self.SearchPointsVisited += 1
	local cooldown = (self.Config and self.Config.SearchPointCooldown) or SEARCH_POINT_COOLDOWN
	self.NextSearchPointTime = os.clock() + cooldown
	self:PickSearchPoint(self.SearchCenter, (self.Config and self.Config.SearchRadius) or SEARCH_RADIUS)
end

-- Pick a random point near centerPos within radius for search behaviour
function Enemy:PickSearchPoint(centerPos, radius)
	if self.IsDead then return end
	if not centerPos then return end
	if not self.Movement then return end
	local angle = math.random() * math.pi * 2
	local distance = radius * (0.4 + math.random() * 0.6)
	local offset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	self.Movement:MoveTo(centerPos + offset)
end

return Enemy