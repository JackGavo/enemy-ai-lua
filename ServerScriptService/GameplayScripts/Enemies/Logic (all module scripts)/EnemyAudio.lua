local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyAudio = {}
EnemyAudio.__index = EnemyAudio

local DEFAULT_FOOTSTEP_SOUND_ID = "rbxasset://sounds/action_footsteps_plastic.mp3"
local FOOTSTEP_INTERVAL_WALK = 0.42
local FOOTSTEP_INTERVAL_RUN = 0.28
local BARK_COOLDOWN = 2.5

local BARK_NAMES = {
	"Alert",
	"Investigate",
	"Search",
	"BodyFound",
	"BodyInvestigate",
	"ReturnToPost",
	"Combat",
	"Reloading",
	"Hurt",
	"Death",
	"Flee",
	"Surrender",
	"GuardReached",
	"Footstep",
}

local SOUND_DEFAULTS = {
	Footstep = {
		SoundId = DEFAULT_FOOTSTEP_SOUND_ID,
		Volume = 0.35,
		PlaybackSpeed = 1.0,
	},
}

local TEMPLATE_FALLBACKS = {
	Search = "Investigate",
	BodyFound = "Alert",
	BodyInvestigate = "Investigate",
	ReturnToPost = "Investigate",
	Flee = "Alert",
	Surrender = "Investigate",
	GuardReached = "Investigate",
}

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function ensureBarkTemplates()
	local soundEffects = getOrCreateFolder(SoundService, "SoundEffects")
	local barks = getOrCreateFolder(soundEffects, "Barks")
	local enemyFolder = getOrCreateFolder(barks, "Enemy")

	for i = 1, #BARK_NAMES do
		local name = BARK_NAMES[i]
		local sound = enemyFolder:FindFirstChild(name)
		if not sound then
			sound = Instance.new("Sound")
			sound.Name = name
			sound.Volume = 1
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMaxDistance = 85
			sound.Parent = enemyFolder
		end
		local defaults = SOUND_DEFAULTS[name]
		if defaults then
			for property, value in defaults do
				sound[property] = value
			end
		end
	end

	return enemyFolder
end

local function clonePlayableSound(template, parent)
	if not template or not template:IsA("Sound") or not parent then return nil end
	local sound = template:Clone()
	sound.Parent = parent
	return sound
end

local function getSoundParent(model)
	if not model then return nil end
	return model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
end

local FEEDBACK_COLORS = {
	Alert = Color3.fromRGB(255, 80, 80),
	Combat = Color3.fromRGB(255, 50, 50),
	Hurt = Color3.fromRGB(255, 60, 60),
	Death = Color3.fromRGB(120, 120, 120),
	Investigate = Color3.fromRGB(255, 220, 90),
	Search = Color3.fromRGB(120, 200, 255),
	BodyFound = Color3.fromRGB(120, 220, 255),
	BodyInvestigate = Color3.fromRGB(120, 220, 255),
	Flee = Color3.fromRGB(255, 185, 80),
	Surrender = Color3.fromRGB(120, 200, 255),
	GuardReached = Color3.fromRGB(120, 200, 255),
}

local function pulseModelHighlight(model, barkName)
	if not model or not model.Parent then return end
	if barkName == "Footstep" or barkName == "Reloading" or barkName == "ReturnToPost" then return end

	local color = FEEDBACK_COLORS[barkName]
	if not color then return end

	local highlight = Instance.new("Highlight")
	highlight.Name = "EnemyFeedbackPulse"
	highlight.Adornee = model
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.75
	highlight.OutlineTransparency = 0.25
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	task.delay(0.22, function()
		if highlight and highlight.Parent then
			highlight.Parent = nil
		end
	end)
end

function EnemyAudio.EnsureTemplates()
	return ensureBarkTemplates()
end

function EnemyAudio.new(enemy)
	local self = setmetatable({}, EnemyAudio)
	self.Enemy = enemy
	self.Model = enemy and enemy.Model or nil
	self.Templates = ensureBarkTemplates()
	self.LastBarkTime = {}
	self.FootstepTimer = 0
	self.LastHealth = nil
	self.Connections = {}
	self.Destroyed = false

	self:Initialize()
	return self
end

function EnemyAudio:Initialize()
	local model = self.Model
	if not model then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self.LastHealth = humanoid.Health
		table.insert(self.Connections, humanoid.HealthChanged:Connect(function(health)
			if self.Destroyed then return end
			if self.LastHealth and health < self.LastHealth and health > 0 then
				self:PlayBark("Hurt", 0.35)
			end
			self.LastHealth = health
		end))
		table.insert(self.Connections, humanoid.Died:Connect(function()
			if self.Destroyed then return end
			self:PlayBark("Death", 0)
		end))
	end
end

function EnemyAudio:GetTemplate(name)
	local template = self.Templates and self.Templates:FindFirstChild(name) or nil
	if template and template:IsA("Sound") and template.SoundId ~= "" then
		return template
	end
	local fallbackName = TEMPLATE_FALLBACKS[name]
	local fallback = fallbackName and self.Templates and self.Templates:FindFirstChild(fallbackName) or nil
	if fallback and fallback:IsA("Sound") and fallback.SoundId ~= "" then
		return fallback
	end
	return template or fallback
end

function EnemyAudio:PlayBark(name, chance)
	if self.Destroyed then return end
	if chance and chance > 0 and math.random() > chance then return end

	local now = os.clock()
	local last = self.LastBarkTime[name]
	if last and now - last < BARK_COOLDOWN then
		return
	end
	self.LastBarkTime[name] = now

	local parent = getSoundParent(self.Model)
	pulseModelHighlight(self.Model, name)
	local template = self:GetTemplate(name)
	if not template or template.SoundId == "" then return end
	local sound = clonePlayableSound(template, parent)
	if not sound then return end

	sound.PlaybackSpeed *= (0.92 + math.random() * 0.16)
	sound:Play()
	task.delay(math.max(sound.TimeLength, 0.35) + 0.15, function()
		if sound and sound.Parent then
			sound.Parent = nil
		end
	end)
end

function EnemyAudio:PlayWeaponSound(soundName)
	if self.Destroyed then return end
	local combat = self.Enemy and self.Enemy.Combat
	local weapon = combat and combat.Weapon
	if not weapon then return end

	local sound = weapon:FindFirstChild(soundName, true)
	if not sound or not sound:IsA("Sound") then return end
	local clone = sound:Clone()
	clone.Parent = sound.Parent
	clone:Play()
	task.delay(math.max(clone.TimeLength, 0.35) + 0.15, function()
		if clone and clone.Parent then
			clone.Parent = nil
		end
	end)
end

function EnemyAudio:Update(deltaTime)
	if self.Destroyed then return end
	local model = self.Model
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if horizontalSpeed < 2 or humanoid.FloorMaterial == Enum.Material.Air then
		self.FootstepTimer = 0
		return
	end

	local interval = horizontalSpeed > 15 and FOOTSTEP_INTERVAL_RUN or FOOTSTEP_INTERVAL_WALK
	self.FootstepTimer += deltaTime
	if self.FootstepTimer >= interval then
		self.FootstepTimer = 0
		local template = self:GetTemplate("Footstep")
		local parent = getSoundParent(model)
		local sound = clonePlayableSound(template, parent)
		if sound then
			sound.PlaybackSpeed *= math.clamp(horizontalSpeed / 12, 0.85, 1.35)
			sound:Play()
			task.delay(math.max(sound.TimeLength, 0.2) + 0.1, function()
				if sound and sound.Parent then
					sound.Parent = nil
				end
			end)
		end
	end
end

function EnemyAudio:Destroy()
	self.Destroyed = true
	for i = 1, #self.Connections do
		self.Connections[i]:Disconnect()
	end
	self.Connections = {}
	self.Enemy = nil
	self.Model = nil
	self.Templates = nil
	self.LastBarkTime = {}
end

ensureBarkTemplates()

return EnemyAudio
