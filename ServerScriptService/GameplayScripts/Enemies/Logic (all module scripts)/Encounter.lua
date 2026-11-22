local ServerScriptService = game:GetService("ServerScriptService")

local EnemyService = require(script.Parent.EnemyService)
local EventsService = require(script.Parent.Parent.Parent.Events.EventsService)

--[[
	Encounter

	Groups enemies into logical encounters (nearby enemies occupying the same
	area). When one enemy confirms the player (PlayerSpotted), the encounter
	alerts the other enemies in the group by giving them the player's last known
	position, so they move toward it and transition into combat.

	This keeps the AI manageable: a single spot does NOT alert the entire map,
	only the enemies in the same area. Grouping is done once per enemy spawn
	(cheap), and alerting is event-driven (only on PlayerSpotted), so it scales
	cleanly to many enemies.
]]--

local Encounter = {}

local GROUP_RADIUS = 40 -- studs: fallback grouping radius if enemies have no configured AlertRadius
local ALERT_PROPAGATION_COOLDOWN = 0.5 -- seconds; avoids duplicate propagation spam from repeated sight events

local Encounters = {}        -- array of { Enemies = {}, Centroid = Vector3 }
local EnemyToEncounter = {}  -- enemy -> encounter

local function GetPosition(enemy)
	if enemy.Model then
		local hrp = enemy.Model:FindFirstChild("HumanoidRootPart")
		if hrp then return hrp.Position end
		return enemy.Model:GetPivot().Position
	end
	return nil
end

local function RecalculateCentroid(enc)
	local sum = Vector3.new()
	local count = 0
	for _, e in ipairs(enc.Enemies) do
		local pos = GetPosition(e)
		if pos then
			sum += pos
			count += 1
		end
	end
	enc.Centroid = count > 0 and sum / count or nil
end

local function GetAlertRadius(enemy)
	local config = enemy and enemy.Config
	local radius = config and config.AlertRadius or nil
	if typeof(radius) == "number" and radius > 0 then
		return radius
	end
	return GROUP_RADIUS
end

-- Register an enemy, grouping it with nearby enemies into an encounter.
function Encounter.RegisterEnemy(enemy)
	if EnemyToEncounter[enemy] then return end

	local pos = GetPosition(enemy)

	-- Find the nearest existing encounter within GROUP_RADIUS.
	local bestEnc = nil
	local bestDist = math.huge
	for _, enc in ipairs(Encounters) do
		if enc.Centroid then
			local dist = pos and (pos - enc.Centroid).Magnitude or math.huge
			if dist < bestDist then
				bestDist = dist
				bestEnc = enc
			end
		end
	end

	local groupRadius = GetAlertRadius(enemy)
	if bestEnc and bestDist <= groupRadius then
		table.insert(bestEnc.Enemies, enemy)
		EnemyToEncounter[enemy] = bestEnc
		RecalculateCentroid(bestEnc)
	else
		local enc = {
			Enemies = { enemy },
			Centroid = pos,
			Alerted = false,
			LastKnownPosition = nil,
			LastAlertTime = 0,
		}
		table.insert(Encounters, enc)
		EnemyToEncounter[enemy] = enc
	end
end

-- Remove an enemy from its encounter, cleaning up empty groups.
function Encounter.UnregisterEnemy(enemy)
	local enc = EnemyToEncounter[enemy]
	if not enc then return end

	for i, e in ipairs(enc.Enemies) do
		if e == enemy then
			table.remove(enc.Enemies, i)
			break
		end
	end
	EnemyToEncounter[enemy] = nil

	RecalculateCentroid(enc)

	if #enc.Enemies == 0 then
		for i, e in ipairs(Encounters) do
			if e == enc then
				table.remove(Encounters, i)
				break
			end
		end
	end
end

-- Alert living enemies in the spotter's encounter.
-- This is the main PlayerSpotted propagation path: it intentionally alerts only
-- the spotter's grouped encounter, not every enemy in a large radius/map.
function Encounter.AlertEncounter(spotter, playerPosition, target)
	local enc = EnemyToEncounter[spotter]
	if not enc or not playerPosition then return 0 end

	local now = os.clock()
	if enc.Alerted and (now - (enc.LastAlertTime or 0)) < ALERT_PROPAGATION_COOLDOWN then
		enc.LastKnownPosition = playerPosition
		return 0
	end

	enc.Alerted = true
	enc.LastKnownPosition = playerPosition
	enc.LastAlertTime = now

	local alertedCount = 0
	for i = 1, #enc.Enemies do
		local enemy = enc.Enemies[i]
		if enemy and not enemy.IsDead then
			enemy:Alert(playerPosition, target)
			alertedCount += 1
		end
	end

	return alertedCount
end

function Encounter.Start()
	-- When an enemy confirms the player, alert the rest of its encounter.
	EventsService:Subscribe("PlayerSpotted", function(event)
		local data = event.Data or {}
		local spotter = data.Spotter
		local position = data.Position
		if not spotter or not position then return end

		local enemy = EnemyService.GetEnemy(spotter)
		if enemy and not enemy.IsDead then
			Encounter.AlertEncounter(enemy, position, data.Target)
		end
	end)

	-- Clean up groups when enemies are removed from the system.
	EnemyService.OnEnemyRemoved(Encounter.UnregisterEnemy)
end

function Encounter.GetDebugInfo(enemy)
	local enc = EnemyToEncounter[enemy]
	if not enc then return nil end
	local index = nil
	for i = 1, #Encounters do
		if Encounters[i] == enc then
			index = i
			break
		end
	end
	return {
		Index = index,
		EnemyCount = #enc.Enemies,
		Alerted = enc.Alerted == true,
		Centroid = enc.Centroid,
		LastKnownPosition = enc.LastKnownPosition,
		LastAlertTime = enc.LastAlertTime,
	}
end

function Encounter.GetAllDebugInfo()
	local result = {}
	for i = 1, #Encounters do
		local enc = Encounters[i]
		result[i] = {
			Index = i,
			EnemyCount = #enc.Enemies,
			Alerted = enc.Alerted == true,
			Centroid = enc.Centroid,
			LastKnownPosition = enc.LastKnownPosition,
			LastAlertTime = enc.LastAlertTime,
		}
	end
	return result
end

return Encounter