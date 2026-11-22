local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyAnimator = {}
EnemyAnimator.__index = EnemyAnimator

--[[
	EnemyAnimator

	Small server-side animator for NPC enemies/targets.

	Why not copy the default Animate script or the 2019 Marine Animate script?
	- The default R15 Animate under ReplicatedStorage.R15Rig is a LocalScript, so it
	  does not reliably run for server-owned NPCs.
	- The Marine script is built around a single NPC and has a large amount of
	  legacy character/tool/emote logic that is unnecessary for 50+ enemies.

	This module only handles what enemies need right now: idle, walk/run, jump,
	fall, sit, and a placeholder surrender pose. Weapon aim/reload animations are
	already handled by Combat, so this module does not duplicate them.
]]--

local FADE_TIME = 0.15
local UPDATE_INTERVAL = 0.15 -- throttle speed/pose checks for 50+ NPCs
local WALK_SPEED_REFERENCE = 16
local MOVE_EPSILON = 0.75
local RUN_SPEED_THRESHOLD = WALK_SPEED_REFERENCE + 2 -- 18 studs/sec

local ANIM_PRIORITY = {
	idle = Enum.AnimationPriority.Core,
	search = Enum.AnimationPriority.Action4,
	walk = Enum.AnimationPriority.Core,
	run = Enum.AnimationPriority.Core,
	jump = Enum.AnimationPriority.Core,
	fall = Enum.AnimationPriority.Core,
	sit = Enum.AnimationPriority.Core,
	surrender = Enum.AnimationPriority.Action,
}

local function getFirstAnimation(animateScript, folderName)
	local folder = animateScript and animateScript:FindFirstChild(folderName)
	if not folder then return nil end
	for _, child in folder:GetChildren() do
		if child:IsA("Animation") and child.AnimationId ~= "" then
			return child
		end
	end
	return nil
end

local function cloneAnimationFromTemplate(templateAnimate, folderName, fallbackName)
	local anim = getFirstAnimation(templateAnimate, folderName)
	if anim then
		return anim:Clone()
	end

	local animationsFolder = ReplicatedStorage:FindFirstChild("Animations")
	local fallback = animationsFolder and animationsFolder:FindFirstChild(fallbackName)
	if fallback and fallback:IsA("Animation") and fallback.AnimationId ~= "" then
		return fallback:Clone()
	end

	return nil
end

local function makeAnimation(name, animationId)
	if not animationId or animationId == "" then return nil end
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = animationId
	return animation
end

-- R15-compatible animation IDs (matching the R15Rig default Animate template).
local DEFAULT_ANIMATION_IDS = {
	idle = "rbxassetid://10921261056",
	walk = "rbxassetid://913402848",
	run = "rbxassetid://913376220",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
	sit = "rbxassetid://2506281703",
}

function EnemyAnimator.new(enemy)
	local self = setmetatable({}, EnemyAnimator)

	self.Enemy = enemy
	self.Model = enemy.Model
	self.Humanoid = nil
	self.Animator = nil
	self.Tracks = {}
	self.IdleTracks = {}
	self.Current = nil
	self.CurrentTrack = nil
	self.UpdateAccumulator = 0
	self.IdleSwitchTimer = 0
	self.CurrentIdleIndex = 1
	self.Pose = "Standing"
	self.RunningSpeed = 0
	self.Searching = false
	self.Connections = {}
	self.Destroyed = false

	self:Initialize()

	return self
end

function EnemyAnimator:Initialize()
	local model = self.Model
	if not model then return end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	self.Humanoid = humanoid

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	self.Animator = animator

	-- Disable the cloned LocalScript Animate for NPCs so it doesn't conflict in contexts where it might run.
	local localAnimate = model:FindFirstChild("Animate")
	if localAnimate and localAnimate:IsA("LocalScript") then
		localAnimate.Disabled = true
	end

	local templateRig = ReplicatedStorage:FindFirstChild("R15Rig")
	local templateAnimate = templateRig and templateRig:FindFirstChild("Animate")

	-- These are copied from the temporary Workspace.Marine development rig so the
	-- production enemy NPCs do not depend on that rig remaining in the place.
	local animationSources = {
		-- Regular idle comes from ReplicatedStorage.Animations.IdleAnimation.
		idle = cloneAnimationFromTemplate(nil, nil, "IdleAnimation") or makeAnimation("marine_idle", DEFAULT_ANIMATION_IDS.idle) or cloneAnimationFromTemplate(templateAnimate, "idle", "IdleAnimation") or makeAnimation("idle", "rbxassetid://10848551631"),
		-- Dedicated searching animation.
		search = makeAnimation("enemy_searching", "rbxassetid://507766666") or cloneAnimationFromTemplate(nil, nil, "IdleAnimation") or makeAnimation("search", "rbxassetid://10848551631"),
		walk = makeAnimation("marine_walk", DEFAULT_ANIMATION_IDS.walk) or cloneAnimationFromTemplate(templateAnimate, "walk", "RunAnimation"),
		run = makeAnimation("marine_run", DEFAULT_ANIMATION_IDS.run) or cloneAnimationFromTemplate(templateAnimate, "run", "RunAnimation") or cloneAnimationFromTemplate(nil, nil, "RunAnimation"),
		jump = makeAnimation("marine_jump", DEFAULT_ANIMATION_IDS.jump) or cloneAnimationFromTemplate(templateAnimate, "jump", "RunAnimation") or makeAnimation("jump", "rbxassetid://507765000"),
		fall = makeAnimation("marine_fall", DEFAULT_ANIMATION_IDS.fall) or cloneAnimationFromTemplate(templateAnimate, "fall", "RunAnimation") or makeAnimation("fall", "rbxassetid://507767968"),
		sit = makeAnimation("marine_sit", DEFAULT_ANIMATION_IDS.sit) or cloneAnimationFromTemplate(templateAnimate, "sit", "IdleAnimation") or makeAnimation("sit", "rbxassetid://2506281703"),
		surrender = cloneAnimationFromTemplate(nil, nil, "SurrenderAnimation")
			or cloneAnimationFromTemplate(templateAnimate, "mood", "SurrenderAnimation")
			or makeAnimation("surrender", "rbxassetid://10848551631"),
	}

	for name, animation in animationSources do
		if animation then
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = ANIM_PRIORITY[name] or Enum.AnimationPriority.Core
				track.Looped = (name == "idle" or name == "search" or name == "walk" or name == "run" or name == "fall" or name == "sit" or name == "surrender")
				self.Tracks[name] = track
			end
			animation:Destroy()
		end
	end

	-- Use the requested single enemy idle so guards share the intended Marine-style stance.
	if self.Tracks.idle then
		table.insert(self.IdleTracks, self.Tracks.idle)
	end

	table.insert(self.Connections, humanoid.Running:Connect(function(speed)
		if self.Destroyed then return end
		self.RunningSpeed = speed or 0
		if self.RunningSpeed > 0.01 then
			self.Pose = "Running"
			local isRunning = self.RunningSpeed > RUN_SPEED_THRESHOLD
			self:SetLocomotionState(isRunning and "Running" or "Walking")
			if isRunning and self.Tracks.run then
				self:Play("run", self.RunningSpeed / 18)
			else
				self:Play("walk", self.RunningSpeed / 12)
			end
		else
			self.Pose = "Standing"
			self:SetLocomotionState("Idle")
			if self.Searching then
				self:Play("search")
			else
				self:Play("idle")
			end
		end
	end))

	table.insert(self.Connections, humanoid.StateChanged:Connect(function(_, newState)
		if self.Destroyed then return end
		if newState == Enum.HumanoidStateType.Jumping then
			self.Pose = "Jumping"
			self:SetLocomotionState("Jumping")
			self:Play("jump")
		elseif newState == Enum.HumanoidStateType.Freefall then
			self.Pose = "FreeFall"
			self:SetLocomotionState("FreeFall")
			self:Play("fall")
		elseif newState == Enum.HumanoidStateType.Seated then
			self.Pose = "Seated"
			self:SetLocomotionState("Seated")
			self:Play("sit")
		elseif newState == Enum.HumanoidStateType.GettingUp then
			self.Pose = "GettingUp"
			self:SetLocomotionState("GettingUp")
		elseif newState == Enum.HumanoidStateType.FallingDown then
			self.Pose = "FallingDown"
			self:SetLocomotionState("FallingDown")
		end
	end))

	table.insert(self.Connections, humanoid.Died:Connect(function()
		self.Pose = "Dead"
		self:SetLocomotionState("Dead")
		self:StopAll()
	end))

	self:Play("idle")
end

function EnemyAnimator:SetLocomotionState(state)
	if self.Model and self.Model.Parent and self.Model:GetAttribute("LocomotionState") ~= state then
		self.Model:SetAttribute("LocomotionState", state)
	end
end

function EnemyAnimator:Play(name, speed)
	local track = self.Tracks[name]
	if name == "idle" and #self.IdleTracks > 0 then
		track = self.IdleTracks[self.CurrentIdleIndex] or self.IdleTracks[1]
	end
	if not track then return end

	if self.Current == name and self.CurrentTrack == track then
		if speed then
			track:AdjustSpeed(speed)
		end
		return
	end

	local oldTrack = self.CurrentTrack
	if oldTrack and oldTrack ~= track then
		oldTrack:Stop(FADE_TIME)
	end

	self.Current = name
	self.CurrentTrack = track
	track:Play(FADE_TIME)
	if name == "search" then
		local enemyName = (self.Model and self.Model.Name) or "UnknownEnemy"
		--print("[EnemyAnimator] Searching animation playing for " .. enemyName .. " | AnimationId: rbxassetid://507766666")
	end
	track:AdjustSpeed(speed or 1)
end

function EnemyAnimator:StopAll()
	for _, track in self.Tracks do
		track:Stop(FADE_TIME)
	end
	for i = 1, #self.IdleTracks do
		self.IdleTracks[i]:Stop(FADE_TIME)
	end
	self.Current = nil
	self.CurrentTrack = nil
end

function EnemyAnimator:Update(deltaTime)
	if self.Destroyed then return end
	self.UpdateAccumulator += deltaTime
	if self.UpdateAccumulator < UPDATE_INTERVAL then return end
	self.UpdateAccumulator = 0

	local humanoid = self.Humanoid
	if not humanoid or humanoid.Health <= 0 then
		self.Pose = "Dead"
		self:SetLocomotionState("Dead")
		self:StopAll()
		return
	end

	local enemy = self.Enemy
	if enemy and enemy.IsTarget and enemy.TargetBehaviour == "Surrender" then
		local model = enemy.Model
		if model and model:GetAttribute("TargetSurrendered") then
			self:SetLocomotionState("Surrender")
			self:Play("surrender")
			return
		end
	end

	-- Marine-style animation source of truth: Humanoid.Running/state events set
	-- the pose. This update only keeps the current loop alive and repairs missed
	-- server Running events for NPC MoveTo edge cases.
	local speed = self.RunningSpeed or 0
	local root = self.Model and self.Model:FindFirstChild("HumanoidRootPart")
	if root then
		local velocity = root.AssemblyLinearVelocity
		speed = math.max(speed, Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
	end

	if self.Pose == "Running" or speed > MOVE_EPSILON then
		local isRunning = speed > RUN_SPEED_THRESHOLD
		self:SetLocomotionState(isRunning and "Running" or "Walking")
		if isRunning and self.Tracks.run then
			self:Play("run", math.max(speed, 1) / 18)
		else
			self:Play("walk", math.max(speed, 1) / 12)
		end
	elseif self.Pose == "FreeFall" then
		self:SetLocomotionState("FreeFall")
		self:Play("fall")
	elseif self.Pose == "Seated" then
		self:SetLocomotionState("Seated")
		self:Play("sit")
	else
		self.Pose = "Standing"
		self:SetLocomotionState("Idle")
		if self.Searching then
			self:Play("search")
		else
			self:Play("idle")
		end
	end
end

-- Toggle the search/investigate stance. When active and the enemy is standing
-- still, the dedicated search animation plays instead of the default idle.
function EnemyAnimator:SetSearching(active)
	self.Searching = active == true
	if self.Searching then
		self:Play("search")
	end
end

function EnemyAnimator:Destroy()
	self.Destroyed = true
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}
	self:StopAll()
	self.Tracks = {}
	self.IdleTracks = {}
	self.CurrentTrack = nil
	self.Enemy = nil
	self.Model = nil
	self.Humanoid = nil
	self.Animator = nil
end

return EnemyAnimator