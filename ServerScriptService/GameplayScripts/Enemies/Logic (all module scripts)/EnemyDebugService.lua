local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local EnemyService = require(script.Parent.EnemyService)
local EventsService = require(script.Parent.Parent.Parent.Events.EventsService)
local Encounter = require(script.Parent.Encounter)

local EnemyDebugService = {}

local Running = false
local UpdateConnection = nil
local Accumulator = 0
local UPDATE_INTERVAL = 0.5 -- 2 Hz; only writes debug attrs when enabled
local ENABLE_ATTRIBUTE_DEBUG = GameConfig.Debug and GameConfig.Debug.EnableEnemyAIDebugAttributes == true
local ENABLE_REMOTE_DEBUG = RunService:IsStudio() or (GameConfig.Debug and GameConfig.Debug.EnableEnemyAIDebug == true)

local remoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions")
if not remoteFunctions then
	remoteFunctions = Instance.new("Folder")
	remoteFunctions.Name = "RemoteFunctions"
	remoteFunctions.Parent = ReplicatedStorage
end

local debugSnapshotFunction = remoteFunctions:FindFirstChild("GetEnemyDebugSnapshot")
if not debugSnapshotFunction then
	debugSnapshotFunction = Instance.new("RemoteFunction")
	debugSnapshotFunction.Name = "GetEnemyDebugSnapshot"
	debugSnapshotFunction.Parent = remoteFunctions
end

local function vectorToTable(value)
	if typeof(value) ~= "Vector3" then return nil end
	return {
		X = math.round(value.X * 100) / 100,
		Y = math.round(value.Y * 100) / 100,
		Z = math.round(value.Z * 100) / 100,
	}
end

local function getModelName(model)
	return model and model.Name or nil
end

local function getModelPath(model)
	if not model then return nil end
	local ok, path = pcall(function()
		return model:GetFullName()
	end)
	if ok then return path end
	return model.Name
end

local function safeCall(object, methodName, fallback)
	if not object or type(object[methodName]) ~= "function" then
		return fallback
	end
	local ok, result = pcall(function()
		return object[methodName](object)
	end)
	if ok then return result end
	return fallback
end

local function getMovementDebug(enemy)
	local movement = enemy.Movement
	if not movement then return {} end
	local currentNode = nil
	if movement.Mode == "Patrol" and movement.Waypoints and movement.WaypointIndex then
		local waypoint = movement.Waypoints[movement.WaypointIndex]
		currentNode = waypoint and waypoint.Name or nil
	elseif movement.Mode == "MoveTo" and movement.PathfindingWaypoints then
		currentNode = "PathWaypoint" .. tostring(movement.PathfindingIndex or 0)
	end
	return {
		Mode = movement.Mode,
		IsMoving = safeCall(movement, "IsMoving", false),
		Destination = vectorToTable(movement.Destination),
		CurrentNode = currentNode,
		PathName = movement.Path and movement.Path.Name or nil,
		WaypointIndex = movement.WaypointIndex,
		StuckTimer = math.round((movement.StuckTimer or 0) * 100) / 100,
	}
end

local function getPerceptionDebug(enemy)
	local perception = enemy.Perception
	if not perception then return {} end
	return {
		VisibleTarget = getModelName(perception.VisibleTarget),
		LastKnownPosition = vectorToTable(perception.LastKnownPosition),
		InvestigationPoint = vectorToTable(perception.InvestigationPoint),
		DetectionRange = perception.VisionRange,
		VisionFOV = perception.FOV,
		HearingRange = perception.HearingRange,
	}
end

local function getCombatDebug(enemy)
	local combat = enemy.Combat
	if not combat then return {} end
	return {
		InCombat = combat.InCombat == true,
		WeaponName = combat.WeaponName,
		Ammo = combat.Ammo,
		AmmoCapacity = combat.AmmoCapacity,
		Reloading = combat.Reloading == true,
		Accuracy = combat.Accuracy,
		ReactionTime = combat.ReactionTime,
		MaxRange = combat.MaxRange,
		MinRange = combat.MinRange,
	}
end

local function getRecentEvents(limit)
	local events = EventsService:GetEvents()
	local result = {}
	local startIndex = math.max(1, #events - (limit or 10) + 1)
	for i = startIndex, #events do
		local event = events[i]
		local data = event.Data or {}
		result[#result + 1] = {
			Type = event.Type,
			Age = math.round((os.clock() - (event.Timestamp or os.clock())) * 100) / 100,
			Position = vectorToTable(event.Position or data.Position),
			Spotter = getModelName(data.Spotter),
			Target = getModelName(data.Target),
		}
	end
	return result
end

local function getEnemyState(enemy)
	if enemy and type(enemy.GetState) == "function" then
		local ok, state = pcall(function()
			return enemy:GetState()
		end)
		if ok then return state end
	end
	return enemy and enemy.State or nil
end

local function getEnemySnapshot(enemy)
	local model = enemy.Model
	local encounterDebug = Encounter.GetDebugInfo(enemy)
	return {
		Model = model,
		Name = getModelName(model),
		Path = getModelPath(model),
		State = getEnemyState(enemy),
		IsDead = enemy.IsDead == true,
		AIDisabled = model and model:GetAttribute("AIDisabled") == true or false,
		Target = getModelName(enemy.Target),
		LastKnownPosition = vectorToTable(enemy.LastKnownPosition),
		Config = enemy.Config,
		Perception = getPerceptionDebug(enemy),
		Movement = getMovementDebug(enemy),
		Combat = getCombatDebug(enemy),
		Encounter = encounterDebug,
	}
end

local function writeDebugAttributes(enemy)
	local model = enemy.Model
	if not model or not model.Parent then return end
	local perception = enemy.Perception
	local movement = enemy.Movement
	local encounterDebug = Encounter.GetDebugInfo(enemy)
	model:SetAttribute("DebugAIState", getEnemyState(enemy) or "None")
	model:SetAttribute("DebugTarget", getModelName(enemy.Target or (perception and perception.VisibleTarget)) or "")
	model:SetAttribute("DebugHasLastKnownPosition", perception and perception.LastKnownPosition ~= nil or false)
	model:SetAttribute("DebugMovementMode", movement and movement.Mode or "None")
	model:SetAttribute("DebugCurrentPath", movement and movement.Path and movement.Path.Name or "")
	model:SetAttribute("DebugCurrentNode", getMovementDebug(enemy).CurrentNode or "")
	model:SetAttribute("DebugDetectionRange", perception and perception.VisionRange or 0)
	model:SetAttribute("DebugEncounterIndex", encounterDebug and encounterDebug.Index or 0)
	model:SetAttribute("DebugEncounterSize", encounterDebug and encounterDebug.EnemyCount or 0)
	model:SetAttribute("DebugEncounterAlerted", encounterDebug and encounterDebug.Alerted or false)
end

function EnemyDebugService.SetAttributeDebugEnabled(enabled)
	ENABLE_ATTRIBUTE_DEBUG = enabled == true
	if not ENABLE_ATTRIBUTE_DEBUG then
		for _, enemy in ipairs(EnemyService.GetEnemies()) do
			local model = enemy.Model
			if model then
				model:SetAttribute("DebugAIState", nil)
				model:SetAttribute("DebugTarget", nil)
				model:SetAttribute("DebugHasLastKnownPosition", nil)
				model:SetAttribute("DebugMovementMode", nil)
				model:SetAttribute("DebugCurrentPath", nil)
				model:SetAttribute("DebugCurrentNode", nil)
				model:SetAttribute("DebugDetectionRange", nil)
				model:SetAttribute("DebugEncounterIndex", nil)
				model:SetAttribute("DebugEncounterSize", nil)
				model:SetAttribute("DebugEncounterAlerted", nil)
			end
		end
	end
end

function EnemyDebugService.GetSnapshot()
	local enemies = EnemyService.GetEnemies()
	local enemySnapshots = {}
	for i = 1, #enemies do
		enemySnapshots[i] = getEnemySnapshot(enemies[i])
	end
	return {
		EnemyCount = #enemies,
		AttributeDebugEnabled = ENABLE_ATTRIBUTE_DEBUG,
		Enemies = enemySnapshots,
		RecentEvents = getRecentEvents(10),
		Encounters = Encounter.GetAllDebugInfo(),
	}
end

function EnemyDebugService.Start()
	if Running then return end
	Running = true
	Accumulator = 0

	debugSnapshotFunction.OnServerInvoke = function(_player)
		if not ENABLE_REMOTE_DEBUG then
			return {
				EnemyCount = 0,
				AttributeDebugEnabled = ENABLE_ATTRIBUTE_DEBUG,
				DebugDisabled = true,
				Enemies = {},
				RecentEvents = {},
				Encounters = {},
			}
		end
		return EnemyDebugService.GetSnapshot()
	end

	UpdateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not ENABLE_ATTRIBUTE_DEBUG then return end
		Accumulator += deltaTime
		if Accumulator < UPDATE_INTERVAL then return end
		Accumulator = 0
		local enemies = EnemyService.GetEnemies()
		for i = 1, #enemies do
			writeDebugAttributes(enemies[i])
		end
	end)
end

function EnemyDebugService.Stop()
	Running = false
	if UpdateConnection then
		UpdateConnection:Disconnect()
		UpdateConnection = nil
	end
	EnemyDebugService.SetAttributeDebugEnabled(false)
end

return EnemyDebugService
