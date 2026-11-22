local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Rig = ReplicatedStorage:WaitForChild("R15Rig")
local EnemyOutfits = require(ServerScriptService.GameplayScripts.Enemies.Databases.Appearance.EnemyOutfits)
local EnemyConfig = require(ServerScriptService.GameplayScripts.Enemies.Logic.EnemyConfig)

local EnemyGeneration = {}

-- Create a single enemy rig with the given appearance type (e.g. "Street", "Military").
-- Optionally parent the rig to a specific folder (defaults to workspace).
-- appearance: optional table { SkinColor, HairId } from EnemyOutfits.GenerateAppearance.
-- If nil, a random appearance is generated per-enemy (non-deterministic).
function EnemyGeneration.CreateEnemy(Type, Parent, appearance)
	local Enemy = Rig:Clone()
	Enemy.Name = "Enemy"
	Enemy.Parent = Parent or workspace

	EnemyOutfits.ApplyAppearance(Enemy, Type, appearance)
	if Type then
		Enemy:SetAttribute("EnemyArchetype", Type)
	end
	local config = EnemyConfig.Resolve(Enemy)
	EnemyConfig.ApplyAttributes(Enemy, config)

	return Enemy
end

-- Place enemies across the map's spawn points.
-- Each enemy is positioned at a spawn point and assigned a patrol path.
--
-- If EnemySpawns (a plan from ContractSeedSystem) is provided, enemies are placed
-- deterministically at the planned spawn points with their planned patrol paths.
-- Each spawn data entry may include an "Archetype" field to override the Type parameter.
-- If no plan is provided, falls back to placing an enemy at every non-VIP spawn point
-- with random path assignment (legacy behaviour).
--
-- rng: optional Random for deterministic appearance generation.
-- The RNG is used ONCE to generate a single shared appearance (skin color + hair)
-- that all guards in this contract will use.
function EnemyGeneration.PlaceEnemies(Type, Map, EnemySpawns, rng: Random?)
	if not Map then
		warn("[EnemyGeneration] PlaceEnemies called with no map.")
		return 0
	end

	local Enemies = Map:FindFirstChild("Enemies")
	if not Enemies then
		warn("[EnemyGeneration] Map '" .. Map.Name .. "' has no Enemies folder.")
		return 0
	end
	
	local enemiesFolder = Map:FindFirstChild("Enemies")
	
	-- If a deterministic plan is provided, use it directly.
	if EnemySpawns then
		-- Generate one shared appearance for all guards in this contract.
		local sharedAppearance = EnemyOutfits.GenerateAppearance(rng)

		local placed = 0
		for _, spawnData in ipairs(EnemySpawns) do
			local spawnPoint = spawnData.SpawnPoint
			local assignedPath = spawnData.Path
			local enemyType = spawnData.Archetype or Type

			local enemy = EnemyGeneration.CreateEnemy(enemyType, enemiesFolder or Map, sharedAppearance)

			local hrp = enemy:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = spawnPoint.CFrame
				hrp.Anchored = false
			end

			if assignedPath then
				local pathValue = Instance.new("ObjectValue")
				pathValue.Name = "AssignedPath"
				pathValue.Value = assignedPath
				pathValue.Parent = enemy
			end

			placed += 1
		end
		return placed
	end

	-- Legacy fallback: collect all non-VIP spawn points and place an enemy at each.
	local spawnPoints = enemiesFolder:FindFirstChild("SpawnPoints")
	local paths = enemiesFolder:FindFirstChild("Paths")

	if not spawnPoints then
		warn("[EnemyGeneration] Map '" .. Map.Name .. "' has no SpawnPoints folder.")
		return 0
	end

	local spawnList = {}
	for _, spawn in spawnPoints:GetChildren() do
		if spawn:IsA("BasePart") then
			local vipVal = spawn:FindFirstChild("VIP")
			local isVIP = vipVal ~= nil and vipVal:IsA("BoolValue") and vipVal.Value == true
			if not isVIP then
				table.insert(spawnList, spawn)
			end
		end
	end

	local pathList = {}
	if paths then
		for _, path in paths:GetChildren() do
			if path:IsA("Folder") then
				table.insert(pathList, path)
			end
		end
	end

	local placed = 0
	for _, spawnPoint in ipairs(spawnList) do
		local enemy = EnemyGeneration.CreateEnemy(Type, enemiesFolder or Map)

		local hrp = enemy:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = spawnPoint.CFrame
			hrp.Anchored = false
		end

		local assignedPath = nil
		local pathName = spawnPoint:GetAttribute("Path")
		if pathName and paths then
			assignedPath = paths:FindFirstChild(pathName)
		end
		if not assignedPath and #pathList > 0 then
			assignedPath = pathList[math.random(1, #pathList)]
		end

		if assignedPath then
			local pathValue = Instance.new("ObjectValue")
			pathValue.Name = "AssignedPath"
			pathValue.Value = assignedPath
			pathValue.Parent = enemy
		end

		placed += 1
	end

	return placed
end

return EnemyGeneration