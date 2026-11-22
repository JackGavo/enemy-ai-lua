local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

--[[
	EnemyAwarenessFeedback (Client)

	Renders in-world visual feedback for enemy awareness:
		- BillboardGui above each enemy's head ( ? / ! / searching )
		- Holographic player afterimage at the last known position

	The server is authoritative for awareness state; this script only
	represents it visually. All feedback is in-world (BillboardGui), not 2D HUD.
]]--

local AwarenessRemote = ReplicatedStorage.RemoteEvents:FindFirstChild("EnemyAwarenessChanged")
local LastKnownRemote = ReplicatedStorage.RemoteEvents:FindFirstChild("EnemyLastKnownPosition")

-- model -> BillboardGui
local Indicators = {}
-- model -> latest awareness string from the server. The client applies it only
-- when the enemy is near enough to matter visually.
local PendingAwareness = {}

local MAX_INDICATOR_DISTANCE = 120
local VISUAL_UPDATE_INTERVAL = 0.25
local CLEANUP_INTERVAL = 2.0
local MAX_AFTERIMAGES = 2
local MIN_AFTERIMAGE_INTERVAL = 1.25

local VisualAccumulator = 0
local CleanupAccumulator = 0
local ActiveAfterimages = {}
local LastAfterimageTime = 0

local function GetLocalRoot()
	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function GetModelPosition(model)
	if not model or not model.Parent then return nil end
	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
	if root then return root.Position end
	return model:GetPivot().Position
end

local function ShouldRenderModel(model)
	local localRoot = GetLocalRoot()
	local modelPosition = GetModelPosition(model)
	if not localRoot or not modelPosition then return false end
	return (localRoot.Position - modelPosition).Magnitude <= MAX_INDICATOR_DISTANCE
end

local function RemoveIndicator(model)
	local billboard = Indicators[model]
	if billboard then
		billboard.Parent = nil
		Indicators[model] = nil
	end
	PendingAwareness[model] = nil
end

local function IsDeadEnemy(model)
	return model ~= nil and model:GetAttribute("EnemyDead") == true
end

local function DisableIndicator(model)
	local billboard = Indicators[model]
	if billboard and billboard.Parent then
		billboard.Enabled = false
		local label = billboard:FindFirstChild("Icon")
		if label then
			label.Text = ""
		end
	end
end


local function GetHead(model)
	return model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
end

-- Create (or reuse) the BillboardGui indicator for an enemy model
local function GetOrCreateIndicator(model)
	local existing = Indicators[model]
	if existing and existing.Parent then return existing end

	local head = GetHead(model)
	if not head then return nil end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AwarenessIndicator"
	billboard.Size = UDim2.new(0, 150, 0, 44)
	billboard.StudsOffset = Vector3.new(0, 3.35, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Enabled = false
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Name = "Icon"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.Jura
	label.TextStrokeTransparency = 0.25
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Text = ""
	label.Parent = billboard

	Indicators[model] = billboard
	return billboard
end

local function SetAwareness(model, awareness)
	if not model or not model.Parent then return end
	if IsDeadEnemy(model) then
		RemoveIndicator(model)
		return
	end
	awareness = awareness or "none"
	PendingAwareness[model] = awareness

	if awareness == "none" or awareness == "combat" then
		DisableIndicator(model)
		return
	end

	if not ShouldRenderModel(model) then
		DisableIndicator(model)
		return
	end

	local billboard = GetOrCreateIndicator(model)
	if not billboard then return end

	local label = billboard:FindFirstChild("Icon")
	if not label then return end

	if awareness == "suspicious" then
		label.Text = "INVESTIGATING"
		label.TextColor3 = Color3.fromRGB(255, 214, 64)
		billboard.Enabled = true
	elseif awareness == "alert" then
		label.Text = "!"
		label.TextColor3 = Color3.fromRGB(255, 64, 64)
		billboard.Enabled = true
	elseif awareness == "searching" then
		label.Text = "SEARCHING"
		label.TextColor3 = Color3.fromRGB(120, 200, 255)
		billboard.Enabled = true
	elseif awareness == "body" then
		label.Text = "BODY FOUND"
		label.TextColor3 = Color3.fromRGB(120, 220, 255)
		billboard.Enabled = true
	elseif awareness == "flee" then
		label.Text = "FLEEING"
		label.TextColor3 = Color3.fromRGB(255, 185, 80)
		billboard.Enabled = true
	elseif awareness == "surrender" then
		label.Text = "SURRENDERED"
		label.TextColor3 = Color3.fromRGB(120, 200, 255)
		billboard.Enabled = true
	elseif awareness == "pursuing" then
		label.Text = "PURSUING"
		label.TextColor3 = Color3.fromRGB(255, 120, 60)
		billboard.Enabled = true
	elseif awareness == "closing" then
		label.Text = "CLOSING IN"
		label.TextColor3 = Color3.fromRGB(255, 150, 70)
		billboard.Enabled = true
	elseif awareness == "reloading" then
		label.Text = "RELOADING"
		label.TextColor3 = Color3.fromRGB(255, 230, 120)
		billboard.Enabled = true
	end
end

-- Holographic player afterimage at the last known position
local function CreateAfterimage(position)
	if not position then return end

	local now = os.clock()
	if now - LastAfterimageTime < MIN_AFTERIMAGE_INTERVAL then
		return
	end
	LastAfterimageTime = now

	while #ActiveAfterimages >= MAX_AFTERIMAGES do
		local oldest = table.remove(ActiveAfterimages, 1)
		if oldest and oldest.Parent then
			oldest.Parent = nil
		end
	end

	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	if not character then return end

	local oldArchivable = character.Archivable
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = oldArchivable
	if not clone then return end

	clone.Name = "PlayerAfterimage"
	clone.Parent = Workspace
	table.insert(ActiveAfterimages, clone)

	-- Remove non-visual runtime objects so the hologram doesn't simulate or run scripts.
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("Humanoid") or descendant:IsA("BaseScript") or descendant:IsA("Tool") then
			descendant.Parent = nil
		end
	end

	-- Make every part a white, semi-transparent forcefield hologram
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Material = Enum.Material.ForceField
			part.Color = Color3.new(1, 1, 1)
			part.CanCollide = false
			part.Anchored = true
			part.Transparency = 0.25
		end
	end

	-- Position the hologram at the last known position
	local hrp = clone:FindFirstChild("HumanoidRootPart")
	if hrp then
		clone:PivotTo(CFrame.new(position))
	end

	-- Fade out and clean up
	task.delay(3, function()
		if not clone.Parent then return end
		for _, part in clone:GetDescendants() do
			if part:IsA("BasePart") then
				TweenService:Create(part, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
		end
		task.delay(0.6, function()
			for i = #ActiveAfterimages, 1, -1 do
				if ActiveAfterimages[i] == clone then
					table.remove(ActiveAfterimages, i)
					break
				end
			end
			if clone.Parent then clone.Parent = nil end
		end)
	end)
end

if AwarenessRemote then
	AwarenessRemote.OnClientEvent:Connect(SetAwareness)
end

if LastKnownRemote then
	LastKnownRemote.OnClientEvent:Connect(function(_, position)
		CreateAfterimage(position)
	end)
end

RunService.RenderStepped:Connect(function(deltaTime)
	VisualAccumulator += deltaTime
	CleanupAccumulator += deltaTime

	if VisualAccumulator >= VISUAL_UPDATE_INTERVAL then
		VisualAccumulator = 0
		for model, awareness in PendingAwareness do
			if model and model.Parent then
				if IsDeadEnemy(model) then
					RemoveIndicator(model)
				elseif ShouldRenderModel(model) then
					SetAwareness(model, awareness)
				else
					DisableIndicator(model)
				end
			else
				PendingAwareness[model] = nil
			end
		end
	end

	if CleanupAccumulator >= CLEANUP_INTERVAL then
		CleanupAccumulator = 0
		for model, billboard in Indicators do
			if (not model) or (not model.Parent) or IsDeadEnemy(model) or (not billboard) or (not billboard.Parent) then
				RemoveIndicator(model)
			end
		end
		for i = #ActiveAfterimages, 1, -1 do
			local afterimage = ActiveAfterimages[i]
			if not afterimage or not afterimage.Parent then
				table.remove(ActiveAfterimages, i)
			end
		end
	end
end)