local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local EnemyDamageIndicatorRemote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("EnemyDamageIndicator")
local WindowShatter = require(ReplicatedStorage:WaitForChild("WeaponsSystem"):WaitForChild("WindowShatter"))
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Combat = {}
Combat.__index = Combat

local PLAYER_DEATH_HEALTH = 1
local ARMOUR_DAMAGE_REDUCTION_PER_LEVEL = 0.04 -- Armour 1 = no reduction; Armour 10 ~= 36% reduction

--[[
	Combat

	Server-authoritative combat behaviour. Enemies hold a weapon cloned from
	ReplicatedStorage.Weapons and use the same aim / reload animations as the
	player (from the WeaponsSystem). Firing is done server-side via a raycast
	with spread, so it scales cleanly to many enemies without relying on the
	client-driven weapon pipeline.

	Damage to the player is applied through the project's existing health flow:
	Armour reduces incoming enemy damage, health is clamped to 1, and HealthUI
	uses Health == 1 to trigger the contract-failed/death screen.

	Performance: firing is event/timer driven (ShotCooldown), movement is
	throttled (MOVE_TICK), and raycasts only happen when actually firing.
]]--

-- Combat tuning
local DEFAULT_WEAPON = "MP5"
local MAX_RANGE = 60        -- beyond this, chase the player
local MIN_RANGE = 8         -- closer than this, back away
local STRAFE_INTERVAL = 1.6 -- seconds between strafe direction changes
local MOVE_TICK = 0.28      -- seconds between re-issuing combat movement
local CLOSE_BURST_RANGE = 90
local CLOSE_BURST_SHOTS = 3
local BURST_SHOT_GAP = 0.1
local MAX_DISTANCE = 2000   -- max bullet travel distance
local FULL_DAMAGE_DIST = 1000
local ZERO_DAMAGE_DIST = 10000
local TRACER_MAX_LENGTH = 160
local TRACER_LIFETIME = 0.08
local MUZZLE_FLASH_TIME = 0.06
local TRACER_POOL_SIZE = 80
local CASING_POOL_SIZE = 80
local EffectFolder = nil
local TracerPool = {}
local TracerPoolIndex = 1
local CasingPool = {}
local CasingPoolIndex = 1

local CombatRaycastParams = RaycastParams.new()
CombatRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function flatUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude <= 0.1 then
		return nil
	end
	return flat.Unit
end

local function getEffectFolder()
	if EffectFolder and EffectFolder.Parent then
		return EffectFolder
	end
	EffectFolder = Workspace:FindFirstChild("EnemyCombatEffects")
	if not EffectFolder then
		EffectFolder = Instance.new("Folder")
		EffectFolder.Name = "EnemyCombatEffects"
		EffectFolder.Parent = Workspace
	end
	return EffectFolder
end

local function getPooledTracer()
	local tracer = TracerPool[TracerPoolIndex]
	if not tracer or not tracer.Parent then
		tracer = Instance.new("Part")
		tracer.Name = "EnemyBulletTracer"
		tracer.Anchored = true
		tracer.CanCollide = false
		tracer.CanQuery = false
		tracer.CanTouch = false
		tracer.CastShadow = false
		tracer.Material = Enum.Material.Neon
		tracer.Color = Color3.fromRGB(255, 220, 80)
		tracer.Parent = getEffectFolder()
		TracerPool[TracerPoolIndex] = tracer
	end
	TracerPoolIndex += 1
	if TracerPoolIndex > TRACER_POOL_SIZE then
		TracerPoolIndex = 1
	end
	return tracer
end

local function getPooledCasing()
	local casing = CasingPool[CasingPoolIndex]
	if not casing or not casing.Parent then
		casing = Instance.new("Part")
		casing.Name = "EnemyShellCasing"
		casing.Size = Vector3.new(0.08, 0.08, 0.22)
		casing.Material = Enum.Material.Metal
		casing.Color = Color3.fromRGB(210, 160, 60)
		casing.CanCollide = false
		casing.CanQuery = false
		casing.CanTouch = false
		casing.CastShadow = false
		casing.Parent = getEffectFolder()
		CasingPool[CasingPoolIndex] = casing
	end
	CasingPoolIndex += 1
	if CasingPoolIndex > CASING_POOL_SIZE then
		CasingPoolIndex = 1
	end
	return casing
end

function Combat.new(Enemy)
	local self = setmetatable({}, Combat)

	self.Enemy = Enemy
	self.InCombat = false

	local config = Enemy.Config or {}
	self.ReactionTime = config.ReactionTime or 0
	self.MaxRange = config.CombatMaxRange or MAX_RANGE
	self.MinRange = config.CombatMinRange or MIN_RANGE
	self.StrafeInterval = config.StrafeInterval or STRAFE_INTERVAL
	self.MoveTick = config.CombatMoveTick or MOVE_TICK
	self.Accuracy = config.Accuracy or 0.7

	-- Weapon state
	self.Weapon = nil
	self.WeaponName = nil
	self.Ammo = 0
	self.AmmoCapacity = 0
	self.UnlimitedMags = config.UnlimitedMags ~= false
	self.Reloading = false
	self.ReloadTimer = 0
	self.ReloadTime = 2
	self.NextFireTime = os.clock() + self.ReactionTime
	self.ShotCooldown = 0.1
	self.HitDamage = 10
	self.BurstShotsRemaining = 0
	self.NextBurstShotTime = 0
	self.LastAllyNotifyTime = 0

	-- Movement state
	self.StrafeTimer = 0
	self.StrafeDirection = 1
	self.MoveTimer = 0
	self.BurstShotsRemaining = 0
	self.NextBurstShotTime = 0

	-- Animation tracks
	self.AimTrack = nil
	self.ReloadTrack = nil

	-- Marine-style combat facing
	self.RootAttachment = nil
	self.OrientationTargetAttachment = nil
	self.AlignOrientation = nil

	return self
end

----------------------------------------------------------------------------
-- Weapon setup
----------------------------------------------------------------------------

-- Equip a weapon from ReplicatedStorage.Weapons onto the enemy character.
function Combat:EquipWeapon()
	local model = self.Enemy and self.Enemy.Model
	if not model then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Resolve weapon name: explicit override, model attribute, or default.
	local weaponName = self.WeaponName
	if not weaponName then
		weaponName = model:GetAttribute("WeaponName") or (self.Enemy.Config and self.Enemy.Config.WeaponName) or DEFAULT_WEAPON
	end

	local template = ReplicatedStorage.Weapons:FindFirstChild(weaponName)
	if not template or not template:IsA("Tool") then
		-- Fall back to the first available weapon.
		for _, w in ipairs(ReplicatedStorage.Weapons:GetChildren()) do
			if w:IsA("Tool") then
				template = w
				break
			end
		end
	end
	if not template then return end

	local weapon = template:Clone()
	-- The clone is used purely for animation/visual purposes on the enemy. Remove
	-- the player-only WeaponsSystem tag so the client-driven weapon system does
	-- not activate for NPC weapons.
	CollectionService:RemoveTag(weapon, "WeaponsSystemWeapon")
	weapon.Parent = model
	humanoid:EquipTool(weapon)
	self.Weapon = weapon
	self.WeaponName = weapon.Name

	self:ReadConfig(weapon)
	self:SetupAnimations()
	if self.Enemy and self.Enemy.Audio then
		self.Enemy.Audio:PlayWeaponSound("Equip")
	end
end

-- Read weapon stats from the weapon's Configuration.
function Combat:ReadConfig(weapon)
	local config = weapon:FindFirstChild("Configuration")
	local function getVal(name, default)
		if not config then return default end
		local v = config:FindFirstChild(name)
		if v and v:IsA("ValueBase") then
			return v.Value
		end
		return default
	end

	self.HitDamage = getVal("HitDamage", 10)
	self.ShotCooldown = getVal("ShotCooldown", 0.1)
	self.AmmoCapacity = getVal("AmmoCapacity", 30)
	self.UnlimitedMags = (self.Enemy and self.Enemy.Config and self.Enemy.Config.UnlimitedMags) ~= false
	-- Weapon configs store spread as degrees. Convert to radians for the simple
	-- vector-cone spread used by NPC combat; treating degrees as raw vector offset
	-- made enemies appear to shoot constantly but almost never hit.
	self.MaxSpread = math.rad(getVal("MaxSpread", 2))
	self.ReloadTime = getVal("ReloadTime", 2)
	self.Ammo = self.AmmoCapacity
end

-- Load the aim and reload animations from the WeaponsSystem onto the enemy.
function Combat:SetupAnimations()
	local model = self.Enemy.Model
	if not model then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Do not assume ServerScriptService.WeaponsSystem is present at runtime. Some
	-- places/bootstrap states only expose ReplicatedStorage.WeaponsSystem, and a
	-- direct dotted lookup here can crash every enemy registration.
	local weaponsSystem = ServerScriptService:FindFirstChild("WeaponsSystem") or ReplicatedStorage:FindFirstChild("WeaponsSystem")
	local assetsFolder = weaponsSystem and weaponsSystem:FindFirstChild("Assets")
	local animFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
	if not animFolder then
		return
	end

	-- Match the Marine AI weapon posture instead of the player RifleAim animation.
	-- RifleAim was pitching NPC arms/weapon upward; use the project's R15
	-- AimingAnimation for a stable, straight weapon-ready pose on the R15 rig.
	local aimAnim = Instance.new("Animation")
	aimAnim.Name = "MarineAim"
	aimAnim.AnimationId = "rbxassetid://113822138136396"
	local reloadAnim = animFolder:FindFirstChild("RifleReload")

	self.AimTrack = animator:LoadAnimation(aimAnim)
	self.AimTrack.Priority = Enum.AnimationPriority.Idle
	self.AimTrack.Looped = true
	aimAnim:Destroy()
	if reloadAnim and reloadAnim:IsA("Animation") then
		self.ReloadTrack = animator:LoadAnimation(reloadAnim)
		self.ReloadTrack.Priority = Enum.AnimationPriority.Action
	end
end

function Combat:SetupCombatFacing()
	local model = self.Enemy and self.Enemy.Model
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end

	local rootAttachment = root:FindFirstChild("EnemyCombatFacingAttachment")
	if not rootAttachment then
		rootAttachment = Instance.new("Attachment")
		rootAttachment.Name = "EnemyCombatFacingAttachment"
		rootAttachment.Parent = root
	end

	local targetAttachment = self.OrientationTargetAttachment
	if not targetAttachment or not targetAttachment.Parent then
		targetAttachment = Instance.new("Attachment")
		targetAttachment.Name = "EnemyCombatFacingTarget"
		targetAttachment.Parent = Workspace.Terrain
		self.OrientationTargetAttachment = targetAttachment
	end

	local align = self.AlignOrientation
	if not align or not align.Parent then
		align = Instance.new("AlignOrientation")
		align.Name = "EnemyCombatAlignOrientation"
		align.Mode = Enum.OrientationAlignmentMode.TwoAttachment
		align.RigidityEnabled = false
		align.Responsiveness = 35
		align.MaxAngularVelocity = 12
		align.MaxTorque = 100000
		align.Parent = root
		self.AlignOrientation = align
	end

	align.Attachment0 = rootAttachment
	align.Attachment1 = targetAttachment
	align.Enabled = true
	self.RootAttachment = rootAttachment
end

function Combat:DisableCombatFacing()
	if self.AlignOrientation then
		self.AlignOrientation.Enabled = false
	end
end

function Combat:CleanupCombatFacing()
	if self.AlignOrientation then
		self.AlignOrientation.Parent = nil
		self.AlignOrientation = nil
	end
	if self.OrientationTargetAttachment then
		self.OrientationTargetAttachment.Parent = nil
		self.OrientationTargetAttachment = nil
	end
	self.RootAttachment = nil
end

function Combat:HoldAimPose()
	local track = self.AimTrack
	if not track then return end

	if not track.IsPlaying then
		track:Play(0.1, 1, 1)
	else
		track:AdjustWeight(1, 0.05)
		track:AdjustSpeed(1)
	end
	track.Looped = true
end

function Combat:BeginCombat()
	if self.InCombat then return end
	self.InCombat = true
	self.NextFireTime = os.clock() + self.ReactionTime
	self.Reloading = false
	self.ReloadTimer = 0
	self.StrafeTimer = 0
	self.MoveTimer = 0

	local model = self.Enemy and self.Enemy.Model
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
	end
	self:DisableCombatFacing()
	self:HoldAimPose()
end

function Combat:EndCombat()
	self.InCombat = false

	local model = self.Enemy and self.Enemy.Model
	if model then
		model:SetAttribute("EnemyFeedbackState", nil)
	end
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.AutoRotate = true
	end
	self:DisableCombatFacing()

	if self.AimTrack then
		self.AimTrack:Stop()
	end
	if self.ReloadTrack then
		self.ReloadTrack:Stop()
	end

	self.Reloading = false
	self.ReloadTimer = 0
	self.BurstShotsRemaining = 0
	self.NextBurstShotTime = 0
end

function Combat:BeginAlertPosture(lookPosition)
	local model = self.Enemy and self.Enemy.Model
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not model or not humanoid or humanoid.Health <= 0 then return end

	if not self.Weapon then
		if self.Enemy and self.Enemy.IsTarget and self.Enemy.TargetBehaviour == "Surrender" then
			return
		end
		self:EquipWeapon()
	end

	humanoid.AutoRotate = false
	self:DisableCombatFacing()
	self:HoldAimPose()
	if lookPosition then
		self:FaceTarget(lookPosition)
	end
end

function Combat:EndAlertPosture()
	if self.InCombat then return end
	local model = self.Enemy and self.Enemy.Model
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.AutoRotate = true
	end
	self:DisableCombatFacing()
	if self.AimTrack then
		self.AimTrack:Stop(0.15)
	end
end

----------------------------------------------------------------------------
-- Main update (called each AI tick while in Combat state)
----------------------------------------------------------------------------

function Combat:Update(DeltaTime)
	if not self.InCombat then return end
	if self.Weapon and not self.Weapon.Parent then
		self.Weapon = nil
		self.WeaponName = nil
		self:EquipWeapon()
	end

	local target = self:GetTarget()
	if not target then
		self:EndCombat()
		return
	end

	-- While reloading, keep moving/facing so enemies do not freeze in bad spots
	-- or stand still outside range with an empty weapon.
	if self.Reloading then
		local model = self.Enemy and self.Enemy.Model
		if model then
			model:SetAttribute("EnemyFeedbackState", "Reloading")
		end
		self:UpdateMovement(DeltaTime)
		local targetHrp = target:FindFirstChild("HumanoidRootPart")
		if targetHrp then
			self:FaceTarget(targetHrp.Position)
		end
		self.ReloadTimer -= DeltaTime
		if self.ReloadTimer <= 0 then
			self.Reloading = false
			self.Ammo = self.AmmoCapacity
			if model then
				model:SetAttribute("EnemyFeedbackState", nil)
			end
			if self.ReloadTrack then
				self.ReloadTrack:Stop()
			end
		end
		return
	end

	self:UpdateMovement(DeltaTime)
	self:TryFire()
end

function Combat:GetTarget()
	local perception = self.Enemy and self.Enemy.Perception
	if not perception then return nil end
	local target = perception.VisibleTarget
	if not target or not target.Parent then return nil end
	if not self:IsPlayerCharacterAlive(target) then
		if self.Enemy and self.Enemy.Perception then
			self.Enemy.Perception.VisibleTarget = nil
			self.Enemy.Perception.WasVisible = false
		end
		self:EndCombat()
		return nil
	end
	return target
end

----------------------------------------------------------------------------
-- Movement
----------------------------------------------------------------------------

function Combat:IsGroundedMoveClear(origin, destination, targetModel)
	local enemyModel = self.Enemy and self.Enemy.Model
	CombatRaycastParams.FilterDescendantsInstances = { enemyModel, targetModel }

	local offset = destination - origin
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	if flatOffset.Magnitude <= 0.25 then return true end

	local wallResult = Workspace:Raycast(origin + Vector3.new(0, 2.5, 0), flatOffset, CombatRaycastParams)
	if wallResult and wallResult.Instance and wallResult.Instance.CanCollide then
		return false
	end

	local groundResult = Workspace:Raycast(destination + Vector3.new(0, 4, 0), Vector3.new(0, -9, 0), CombatRaycastParams)
	return groundResult ~= nil
end

function Combat:PickSmoothCombatMove(myPos, targetHrp, dist)
	local targetPos = targetHrp.Position
	if dist > self.MaxRange then
		local direction = flatUnit(targetPos - myPos)
		if direction then
			local desired = myPos + direction * math.min(dist - self.MaxRange + 6, 18)
			if self:IsGroundedMoveClear(myPos, desired, targetHrp.Parent) then
				return desired
			end
		end
		return myPos
	end

	if dist < self.MinRange then
		local away = flatUnit(myPos - targetPos)
		if away then
			local desired = myPos + away * 10
			if self:IsGroundedMoveClear(myPos, desired, targetHrp.Parent) then
				return desired
			end
		end
	end

	local side = flatUnit(targetHrp.CFrame.RightVector * self.StrafeDirection)
	if side then
		local desired = myPos + side * 8
		if self:IsGroundedMoveClear(myPos, desired, targetHrp.Parent) then
			return desired
		end
		local opposite = myPos - side * 8
		if self:IsGroundedMoveClear(myPos, opposite, targetHrp.Parent) then
			self.StrafeDirection = -self.StrafeDirection
			return opposite
		end
	end

	return myPos
end

function Combat:UpdateMovement(DeltaTime)
	local target = self:GetTarget()
	if not target then return end
	local targetHrp = target:FindFirstChild("HumanoidRootPart")
	if not targetHrp then return end

	local movement = self.Enemy and self.Enemy.Movement
	if not movement then return end
	local myPos = movement:GetPosition()
	if not myPos then return end

	local dist = (targetHrp.Position - myPos).Magnitude
	local model = self.Enemy and self.Enemy.Model
	if model then
		if dist > self.MaxRange then
			model:SetAttribute("EnemyFeedbackState", "CombatClosing")
		elseif not self.Reloading then
			model:SetAttribute("EnemyFeedbackState", nil)
		end
	end

	-- Always face the target so shots line up.
	self:FaceTarget(targetHrp.Position)

	-- Strafe direction changes periodically.
	self.StrafeTimer += DeltaTime
	if self.StrafeTimer >= self.StrafeInterval then
		self.StrafeTimer = 0
		self.StrafeDirection = -self.StrafeDirection
	end

	-- If the target is visible but outside shooting range, chase continuously
	-- without the movement throttle. This prevents enemies from briefly stopping
	-- between move commands when they reach the player's old position while the
	-- player is still moving. MoveToDirect has its own internal pathfinding
	-- cooldown (PATH_RECOMPUTE_COOLDOWN) so this will not flood PathfindingService.
	if dist > self.MaxRange then
		movement:MoveToDirect(targetHrp.Position)
		return
	end

	-- Throttle re-issuing movement to avoid excessive pathfinding.
	self.MoveTimer += DeltaTime
	if self.MoveTimer < self.MoveTick then return end
	self.MoveTimer = 0

	local desired = self:PickSmoothCombatMove(myPos, targetHrp, dist)
	local currentDestination = movement:GetCurrentDestination()
	if desired and (not currentDestination or (currentDestination - desired).Magnitude > 3) then
		movement:MoveDirect(desired)
	end
end

function Combat:FaceTarget(targetPos)
	local model = self.Enemy and self.Enemy.Model
	if not model then return end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local myPos = hrp.Position
	local flatTarget = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
	local look = flatTarget - myPos
	if look.Magnitude < 0.1 then return end

	-- Yaw-only root rotation. Do not pitch up/down toward elevated targets and do
	-- not use constraints here; this preserves the current grounded position while
	-- still allowing shots to be aimed using the real muzzle/target ray below.
	local velocity = hrp.AssemblyLinearVelocity
	local angularVelocity = hrp.AssemblyAngularVelocity
	hrp.CFrame = CFrame.lookAt(myPos, myPos + look.Unit, Vector3.yAxis)
	hrp.AssemblyLinearVelocity = Vector3.new(velocity.X, math.min(velocity.Y, 0), velocity.Z)
	hrp.AssemblyAngularVelocity = angularVelocity
end

----------------------------------------------------------------------------
-- Firing
----------------------------------------------------------------------------

function Combat:TryFire()
	local now = os.clock()
	if self.BurstShotsRemaining > 0 and now >= self.NextBurstShotTime then
		self.BurstShotsRemaining -= 1
		self.NextFireTime = now
		self.NextBurstShotTime = now + BURST_SHOT_GAP
	end
	if now < self.NextFireTime then return end
	if self.Reloading then return end

	local target = self:GetTarget()
	if not target then return end
	local targetHrp = target:FindFirstChild("HumanoidRootPart")
	if not targetHrp then return end

	-- Empty magazine -> reload. Enemy NPCs have unlimited reserve magazines by
	-- default, so this refills the current magazine forever instead of consuming
	-- shared/player ammo. Set Config/attribute UnlimitedMags=false to disable.
	if self.Ammo <= 0 then
		if self.UnlimitedMags then
			self:StartReload()
		end
		return
	end

	local muzzle = self:GetMuzzlePosition()
	if not muzzle then return end

	-- Range check: don't waste ammo firing at targets beyond effective range.
	-- During pursuit the enemy chases via pathfinding but holds fire until in range.
	local distToTarget = (targetHrp.Position - muzzle).Magnitude
	if distToTarget > self.MaxRange then return end

	self.Ammo -= 1
	self.NextFireTime = now + self.ShotCooldown

	local targetVelocity = targetHrp.AssemblyLinearVelocity
	local leadTime = math.clamp(distToTarget / 350, 0, 0.35)
	local aimPosition = targetHrp.Position + targetVelocity * leadTime

	-- Aim at the target with a small random spread.
	local toTarget = (aimPosition - muzzle).Unit
	local dir = self:ApplySpread(toTarget)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { self.Enemy and self.Enemy.Model }

	local result = Workspace:Raycast(muzzle, dir * MAX_DISTANCE, rayParams)
	self:PlayFireEffects(muzzle, dir, result)
	if result then
		local hitPart = result.Instance
		-- If the bullet hit a shatterable window, break it (same as player shots)
		if hitPart and WindowShatter.isShatterableWindow(hitPart) then
			WindowShatter.shatter(hitPart, { p = result.Position })
		end
		local character = self:FindCharacter(hitPart)
		if character and character == target and self:IsPlayerCharacterAlive(character) then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local damage = self:CalculateDamage(result.Distance)
				self:ApplyDamageToPlayer(humanoid, damage, muzzle)
			end
		end
	end

	-- Notify nearby allies to reinforce (throttled per-enemy to avoid spam).
	local allyNow = os.clock()
	if allyNow - self.LastAllyNotifyTime >= 2.0 then
		self.LastAllyNotifyTime = allyNow
		local EnemyService = require(script.Parent.EnemyService)
		EnemyService.NotifyAllyReinforcement(self.Enemy, target)
	end

	-- Auto reload when the magazine is empty. NPC reserve magazines are unlimited,
	-- so they can reload indefinitely without touching player ammo reserves.
	if self.Ammo <= 0 then
		if self.UnlimitedMags then
			self:StartReload()
		end
	elseif distToTarget <= CLOSE_BURST_RANGE and self.BurstShotsRemaining <= 0 then
		self.BurstShotsRemaining = CLOSE_BURST_SHOTS - 1
		self.NextBurstShotTime = os.clock() + BURST_SHOT_GAP
	end
end

function Combat:PlayFireEffects(muzzlePosition, direction, raycastResult)
	local weapon = self.Weapon
	if not weapon then return end

	local sound = weapon:FindFirstChild("Fired", true)
	if sound and sound:IsA("Sound") then
		-- Clone briefly so rapid-fire weapons can overlap shots naturally instead of
		-- cutting off the previous sound every cooldown.
		local shot = sound:Clone()
		shot.Parent = sound.Parent
		shot:Play()
		task.delay(math.max(shot.TimeLength, 0.25) + 0.1, function()
			if shot.Parent then
				shot.Parent = nil
			end
		end)
	end

	local muzzleAttachment = weapon:FindFirstChild("TipAttachment", true)
	if muzzleAttachment and muzzleAttachment:IsA("Attachment") then
		local flash = muzzleAttachment:FindFirstChildWhichIsA("ParticleEmitter")
		if flash then
			flash:Emit(1)
		end

		local light = muzzleAttachment:FindFirstChildWhichIsA("PointLight")
		if not light then
			light = Instance.new("PointLight")
			light.Name = "EnemyMuzzleFlashLight"
			light.Brightness = 2
			light.Range = 8
			light.Enabled = false
			light.Parent = muzzleAttachment
		end
		light.Enabled = true
		task.delay(MUZZLE_FLASH_TIME, function()
			if light.Parent then
				light.Enabled = false
			end
		end)
	end

	self:CreateTracer(muzzlePosition, direction, raycastResult)
	self:EjectCasing()
end

function Combat:CreateTracer(origin, direction, raycastResult)
	if not origin or not direction then return end
	local endPosition = raycastResult and raycastResult.Position or (origin + direction.Unit * TRACER_MAX_LENGTH)
	local offset = endPosition - origin
	local length = math.min(offset.Magnitude, TRACER_MAX_LENGTH)
	if length <= 0.5 then return end

	local tracer = getPooledTracer()
	local token = (tracer:GetAttribute("UseToken") or 0) + 1
	tracer:SetAttribute("UseToken", token)
	tracer.Transparency = 0.15
	tracer.Size = Vector3.new(0.035, 0.035, length)
	tracer.CFrame = CFrame.lookAt(origin + direction.Unit * (length * 0.5), origin + direction.Unit * length)

	local tween = TweenService:Create(tracer, TweenInfo.new(TRACER_LIFETIME, Enum.EasingStyle.Linear), {
		Transparency = 1,
		Size = Vector3.new(0.01, 0.01, length),
	})
	tween:Play()
	task.delay(TRACER_LIFETIME + 0.05, function()
		if tracer.Parent and tracer:GetAttribute("UseToken") == token then
			tracer.Transparency = 1
		end
	end)
end

function Combat:EjectCasing()
	local weapon = self.Weapon
	if not weapon then return end
	local handle = weapon:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return end

	-- Cheap optional shell casing, pooled so large fights do not allocate hundreds of parts per second.
	local casing = getPooledCasing()
	local token = (casing:GetAttribute("UseToken") or 0) + 1
	casing:SetAttribute("UseToken", token)
	casing.Transparency = 0
	casing.CFrame = handle.CFrame * CFrame.new(0.25, 0.05, 0)
	casing.AssemblyLinearVelocity = handle.CFrame.RightVector * 8 + Vector3.new(0, 5, 0)
	casing.AssemblyAngularVelocity = Vector3.new(math.random(), math.random(), math.random()) * 20
	task.delay(1.5, function()
		if casing.Parent and casing:GetAttribute("UseToken") == token then
			casing.Transparency = 1
			casing.AssemblyLinearVelocity = Vector3.zero
			casing.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

function Combat:GetMuzzlePosition()
	local weapon = self.Weapon
	if weapon then
		local tip = weapon:FindFirstChild("TipAttachment", true)
		if tip and tip:IsA("Attachment") then
			return tip.WorldPosition
		end
		local handle = weapon:FindFirstChild("Handle")
		if handle then
			return handle.Position
		end
	end

	local model = self.Enemy and self.Enemy.Model
	if model then
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hrp then return hrp.Position end
	end
	return nil
end

-- Apply a random cone of spread around the aim direction.
function Combat:ApplySpread(direction)
	local accuracy = math.clamp(self.Accuracy or 0.7, 0, 1)
	local spread = self.MaxSpread * (1.25 - accuracy)
	if spread <= 0 then return direction end

	local angle = math.random() * math.pi * 2
	local radius = math.random() * spread

	local axis = direction:Cross(Vector3.new(0, 1, 0))
	if axis.Magnitude < 0.01 then
		axis = Vector3.new(1, 0, 0)
	end
	axis = axis.Unit
	local up = direction:Cross(axis).Unit

	local offset = axis * math.cos(angle) * radius + up * math.sin(angle) * radius
	return (direction + offset).Unit
end

-- Walk up the parent chain to find the character model containing a Humanoid.
function Combat:FindCharacter(part)
	local current = part
	while current do
		if current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Simple distance-based damage falloff, scaled by the global enemy damage multiplier.
function Combat:CalculateDamage(distance)
	local falloff = math.clamp(
		1 - (math.max(0, distance - FULL_DAMAGE_DIST) / (ZERO_DAMAGE_DIST - FULL_DAMAGE_DIST)),
		0, 1
	)
	local multiplier = GameConfig.Combat.EnemyDamageMultiplier or 1
	return self.HitDamage * falloff * multiplier
end

function Combat:GetPlayerFromHumanoid(humanoid)
	if not humanoid or not humanoid.Parent then return nil end
	return Players:GetPlayerFromCharacter(humanoid.Parent)
end

function Combat:GetPlayerStat(player, statName, defaultValue)
	local plrInfo = player and player:FindFirstChild("PlrInfo")
	local stats = plrInfo and plrInfo:FindFirstChild("Stats")
	local valueObject = stats and stats:FindFirstChild(statName)
	if valueObject and valueObject:IsA("ValueBase") and typeof(valueObject.Value) == "number" then
		return valueObject.Value
	end
	return defaultValue
end

function Combat:ApplyArmourReduction(player, damage)
	local armourLevel = self:GetPlayerStat(player, "Armour", 1)
	local reduction = math.clamp((armourLevel - 1) * ARMOUR_DAMAGE_REDUCTION_PER_LEVEL, 0, 0.75)
	return damage * (1 - reduction)
end

function Combat:IsPlayerCharacterAlive(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > PLAYER_DEATH_HEALTH
end

-- Apply damage to the player through the existing Health == 1 death flow.
function Combat:ApplyDamageToPlayer(humanoid, damage, damageOrigin)
	if not humanoid or humanoid.Health <= PLAYER_DEATH_HEALTH then return end
	if typeof(damage) ~= "number" or damage <= 0 then return end

	local player = self:GetPlayerFromHumanoid(humanoid)
	local finalDamage = self:ApplyArmourReduction(player, damage)
	if finalDamage <= 0 then return end

	-- The project disables real Humanoid death and uses Health == 1 to show the
	-- contract-failed/death UI. Clamp here so enemy fire participates in that path.
	humanoid.Health = math.max(PLAYER_DEATH_HEALTH, humanoid.Health - finalDamage)

	-- Show the existing directional damage indicator on the damaged player's client.
	-- Prefer the muzzle / shot origin, falling back to the enemy root if needed.
	if player and EnemyDamageIndicatorRemote then
		local originPosition = damageOrigin
		if typeof(originPosition) ~= "Vector3" then
			local enemyModel = self.Enemy and self.Enemy.Model
			local enemyRoot = enemyModel and enemyModel:FindFirstChild("HumanoidRootPart")
			originPosition = enemyRoot and enemyRoot.Position or nil
		end
		if typeof(originPosition) == "Vector3" then
			EnemyDamageIndicatorRemote:FireClient(player, CFrame.new(originPosition))
		end
	end

	if humanoid.Health <= PLAYER_DEATH_HEALTH then
		humanoid.Health = PLAYER_DEATH_HEALTH
		local EnemyService = require(script.Parent.EnemyService)
		EnemyService.OnPlayerDown(player, humanoid.Parent)
	end
end

function Combat:StartReload()
	if self.Reloading then return end
	self.Reloading = true
	local model = self.Enemy and self.Enemy.Model
	if model then
		model:SetAttribute("EnemyFeedbackState", "Reloading")
	end
	self.ReloadTimer = self.ReloadTime
	if self.ReloadTrack then
		self.ReloadTrack:Play()
		self.ReloadTrack:AdjustSpeed(math.clamp(2 / math.max(self.ReloadTime, 0.1), 0.8, 3))
	end
	if self.Enemy and self.Enemy.Audio then
		self.Enemy.Audio:PlayWeaponSound("Reload")
		self.Enemy.Audio:PlayBark("Reloading", 1)
	end
end

----------------------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------------------

function Combat:DropWeapon()
	self:EndCombat()

	if self.Weapon then
		-- Remove the NPC weapon from the body. Parent=nil follows the project convention
		-- for removing instances and avoids leaving active tools on dead enemies.
		self.Weapon.Parent = nil
		self.Weapon = nil
	end
end

function Combat:Destroy()
	self:DropWeapon()

	self.AimTrack = nil
	self.ReloadTrack = nil
	self:CleanupCombatFacing()
	self.Enemy = nil
end

return Combat