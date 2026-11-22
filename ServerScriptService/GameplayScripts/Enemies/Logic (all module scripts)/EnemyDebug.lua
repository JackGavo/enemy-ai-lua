--==================================================
-- EnemyDebug
--
-- Visual debug system for enemy AI, modeled after the Marine AI's
-- Troubleshoot module. Provides real-time visual feedback for:
--   - Current AI state and target distance (billboard text)
--   - LOS rays to targets (green=normal combat, orange=pursuit)
--   - Vision cone wireframe (optional)
--
-- All visuals are toggled via GameConfig.Debug flags and only
-- render when EnableEnemyAIDebug is true.
--==================================================

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local EnemyDebug = {}

-- Cache of debug visual objects per enemy model
local debugObjects = {}

local function getDebugFolder()
	local folder = Workspace:FindFirstChild("EnemyDebugVisuals")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "EnemyDebugVisuals"
		folder.Parent = Workspace
	end
	return folder
end

local function createRayPart(name, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(0.15, 0.15, 1)
	part.Transparency = 1
	return part
end

-- Create or get debug objects for an enemy model
local function getOrCreateDebugObjects(model)
	if not debugObjects[model] then
		local folder = getDebugFolder()
		local modelFolder = Instance.new("Folder")
		modelFolder.Name = model.Name .. "_Debug"
		modelFolder.Parent = folder

		-- State text billboard
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "StateText"
		billboard.Size = UDim2.fromOffset(220, 50)
		billboard.StudsOffset = Vector3.new(0, 4, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 250
		billboard.Enabled = false

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.Code
		label.Text = ""
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0
		label.TextScaled = true
		label.Parent = billboard

		-- LOS ray (green for normal combat)
		local losRay = createRayPart("LOSRay", Color3.fromRGB(0, 255, 80))

		-- Pursuit ray (orange for pursuit phase)
		local pursuitRay = createRayPart("PursuitRay", Color3.fromRGB(255, 165, 0))

		-- Last known position marker (red sphere)
		local lkpMarker = Instance.new("Part")
		lkpMarker.Name = "LastKnownPos"
		lkpMarker.Shape = Enum.PartType.Ball
		lkpMarker.Anchored = true
		lkpMarker.CanCollide = false
		lkpMarker.CanQuery = false
		lkpMarker.CanTouch = false
		lkpMarker.CastShadow = false
		lkpMarker.Material = Enum.Material.Neon
		lkpMarker.Color = Color3.fromRGB(255, 50, 50)
		lkpMarker.Size = Vector3.new(2, 2, 2)
		lkpMarker.Transparency = 1

		billboard.Parent = modelFolder
		losRay.Parent = modelFolder
		pursuitRay.Parent = modelFolder
		lkpMarker.Parent = modelFolder

		debugObjects[model] = {
			Folder = modelFolder,
			Billboard = billboard,
			Label = label,
			LOSRay = losRay,
			PursuitRay = pursuitRay,
			LKPMarker = lkpMarker,
		}
	end
	return debugObjects[model]
end

local function updateRay(rayPart, origin, dest)
	local offset = dest - origin
	local length = offset.Magnitude
	if length < 0.5 then
		rayPart.Transparency = 1
		return
	end
	local midPoint = origin + offset * 0.5
	rayPart.Size = Vector3.new(0.15, 0.15, length)
	rayPart.CFrame = CFrame.lookAt(midPoint, dest)
	rayPart.Transparency = 0.3
end

function EnemyDebug:Update(enemy)
	local debugConfig = GameConfig.Debug
	if not debugConfig or not debugConfig.EnableEnemyAIDebug then
		self:Clear(enemy)
		return
	end

	local model = enemy.Model
	if not model then return end

	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local objs = getOrCreateDebugObjects(model)
	local perception = enemy.Perception

	-- Update state text
	if debugConfig.ShowAIStateText then
		objs.Billboard.Adornee = hrp
		objs.Billboard.Enabled = true
		local state = enemy:GetState() or "Unknown"
		local pursuing = perception and perception:IsPursuing()
		local target = perception and perception.VisibleTarget
		local distStr = ""
		if target and target:FindFirstChild("HumanoidRootPart") then
			local dist = (target.HumanoidRootPart.Position - hrp.Position).Magnitude
			distStr = string.format(" [%.0f studs]", dist)
		end
		local pursuitStr = pursuing and " (PURSUIT)" or ""
		objs.Label.Text = string.format("%s%s%s", state, pursuitStr, distStr)
		objs.Label.TextColor3 = pursuing and Color3.fromRGB(255, 165, 0) or Color3.fromRGB(0, 255, 100)
	else
		objs.Billboard.Enabled = false
	end

	-- Update LOS/pursuit rays
	if perception and debugConfig.ShowPursuitRays then
		local target = perception.VisibleTarget
		if target and target:FindFirstChild("HumanoidRootPart") then
			local targetHrp = target.HumanoidRootPart
			local origin = hrp.Position
			local dest = targetHrp.Position

			if perception:IsPursuing() then
				-- Pursuit: orange ray
				updateRay(objs.PursuitRay, origin, dest)
				objs.LOSRay.Transparency = 1
			else
				-- Normal combat: green ray
				updateRay(objs.LOSRay, origin, dest)
				objs.PursuitRay.Transparency = 1
			end
		else
			objs.LOSRay.Transparency = 1
			objs.PursuitRay.Transparency = 1
		end

		-- Show last known position marker
		if perception:HasLastKnownPosition() and not perception:HasVisibleTarget() then
			local lkp = perception:GetLastKnownPosition()
			if lkp then
				objs.LKPMarker.Position = lkp
				objs.LKPMarker.Transparency = 0.5
			else
				objs.LKPMarker.Transparency = 1
			end
		else
			objs.LKPMarker.Transparency = 1
		end
	else
		objs.LOSRay.Transparency = 1
		objs.PursuitRay.Transparency = 1
		objs.LKPMarker.Transparency = 1
	end
end

function EnemyDebug:Clear(enemy)
	local model = enemy.Model
	if not model then return end
	local objs = debugObjects[model]
	if objs then
		objs.Billboard.Enabled = false
		objs.LOSRay.Transparency = 1
		objs.PursuitRay.Transparency = 1
		objs.LKPMarker.Transparency = 1
	end
end

function EnemyDebug:Destroy(enemy)
	local model = enemy.Model
	if not model then return end
	local objs = debugObjects[model]
	if objs then
		if objs.Folder then
			objs.Folder:Destroy()
		end
		debugObjects[model] = nil
	end
end

return EnemyDebug