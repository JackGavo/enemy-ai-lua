local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyService = require(ServerScriptService.GameplayScripts.Enemies.Logic.EnemyService)
local Enemy = require(ServerScriptService.GameplayScripts.Enemies.Logic.Enemy)
local VisualFeedback = require(ServerScriptService.GameplayScripts.Enemies.Logic.VisualFeedback)
local Encounter = require(ServerScriptService.GameplayScripts.Enemies.Logic.Encounter)
local TargetBehaviour = require(ServerScriptService.GameplayScripts.Enemies.Logic.TargetBehaviour)
local EnemyDebugService = require(ServerScriptService.GameplayScripts.Enemies.Logic.EnemyDebugService)

local BindableEvents = ReplicatedStorage:WaitForChild("BindableEvents")
local MapLoadedBindable = BindableEvents:FindFirstChild("MapLoaded")
if not MapLoadedBindable then
	MapLoadedBindable = Instance.new("BindableEvent")
	MapLoadedBindable.Name = "MapLoaded"
	MapLoadedBindable.Parent = BindableEvents
end

local MapUnloadedBindable = BindableEvents:FindFirstChild("MapUnloaded")
if not MapUnloadedBindable then
	MapUnloadedBindable = Instance.new("BindableEvent")
	MapUnloadedBindable.Name = "MapUnloaded"
	MapUnloadedBindable.Parent = BindableEvents
end

local function isEnemyModel(model)
	return model:IsA("Model")
		and model.Name == "Enemy"
		and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function isTargetModel(model)
	return model:IsA("Model")
		and model:FindFirstChildOfClass("Humanoid") ~= nil
		and TargetBehaviour.IsTargetModel(model)
end

-- Create an Enemy object from a model and register it with EnemyService
local function registerEnemyModel(model)
	if EnemyService.GetEnemy(model) then return end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local enemyObj = Enemy.new(model)
	enemyObj:Initialize()
	EnemyService.RegisterEnemy(enemyObj)
	Encounter.RegisterEnemy(enemyObj)
end

local function registerEnemiesIn(container)
	if not container then return 0 end
	local registered = 0
	for _, descendant in container:GetDescendants() do
		if isEnemyModel(descendant) or isTargetModel(descendant) then
			local before = EnemyService.GetEnemy(descendant)
			registerEnemyModel(descendant)
			if not before and EnemyService.GetEnemy(descendant) then
				registered += 1
			end
		end
	end
	return registered
end

-- Start the enemy service
EnemyService.Start()

-- Start visual feedback (awareness indicators / afterimage)
VisualFeedback:Start()

-- Start opt-in AI debugging tools (snapshot RemoteFunction + disabled-by-default attributes)
EnemyDebugService.Start()

-- Start the encounter system (groups enemies by area; alerts nearby enemies
-- when one confirms the player)
Encounter:Start()

-- Watch for enemy and target models being added under active gameplay containers.
-- This catches deterministic contract NPCs and also supports Safehouse NPCs without
-- accidentally registering the sample Workspace.Marine reference model.
Workspace.DescendantAdded:Connect(function(descendant)
	local world = Workspace:FindFirstChild("World")
	local safehouse = Workspace:FindFirstChild("Safehouse")
	local inGameplayContainer = (world and descendant:IsDescendantOf(world)) or (safehouse and descendant:IsDescendantOf(safehouse))
	if not inGameplayContainer then
		return
	end

	if isEnemyModel(descendant) or isTargetModel(descendant) then
		task.defer(function()
			if descendant.Parent then
				local currentWorld = Workspace:FindFirstChild("World")
				local currentSafehouse = Workspace:FindFirstChild("Safehouse")
				local stillInGameplayContainer = (currentWorld and descendant:IsDescendantOf(currentWorld)) or (currentSafehouse and descendant:IsDescendantOf(currentSafehouse))
				if stillInGameplayContainer then
					registerEnemyModel(descendant)
				end
			end
		end)
	end
end)

if MapLoadedBindable then
	MapLoadedBindable.Event:Connect(function(_mapName, worldFolder)
		registerEnemiesIn(worldFolder or Workspace:FindFirstChild("World"))
	end)
end

if MapUnloadedBindable then
	MapUnloadedBindable.Event:Connect(function(_mapName)
		EnemyService.DestroyAllEnemies()
	end)
end

-- Initial scan for any enemies/targets already present in the active World map only.
registerEnemiesIn(Workspace:FindFirstChild("World"))
