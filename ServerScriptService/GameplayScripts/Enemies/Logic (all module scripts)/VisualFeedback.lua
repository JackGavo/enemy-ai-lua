local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local EnemyService = require(script.Parent.EnemyService)
local EventsService = require(script.Parent.Parent.Parent.Events.EventsService)

--[[
	VisualFeedback

	Server-authoritative awareness state for in-world visual feedback.
	Derives each enemy's awareness from its AI state + perception and
	fires it to clients via RemoteEvents. The client renders the actual
	BillboardGui indicators and holographic afterimage.

	Awareness levels:
		"none"       - no indicator (idle / patrol)
		"suspicious" - investigating a sound/event ( ? )
		"alert"      - player just confirmed ( ! ) - brief flash
		"searching"  - lost sight of player, searching (searching icon)
		"combat"     - actively fighting (indicator reduced/removed)
		"closing"    - moving into shooting range
		"reloading"  - temporarily reloading during combat
		"body"       - investigating a dead body
		"flee"       - target is fleeing
		"surrender"  - target has surrendered

	Performance: staggered low-frequency polling (4 Hz) + event-driven
	flash. Only fires to clients when an enemy's awareness actually changes,
	so it scales to many enemies.
]]--

local VisualFeedback = {}

local AwarenessRemote = ReplicatedStorage.RemoteEvents:FindFirstChild("EnemyAwarenessChanged")
local LastKnownRemote = ReplicatedStorage.RemoteEvents:FindFirstChild("EnemyLastKnownPosition")

local Running = false
local UpdateConnection = nil
local Accumulator = 0
local UpdateInterval = 0.25 -- 4 Hz staggered polling

local ALERT_FLASH_TIME = 1.0 -- seconds the "!" shows after spotting
local RADIO_TOWER_ALERT_RADIUS = 120
local FEEDBACK_STATE_AWARENESS = {
	BodyInvestigating = "body",
	BodySearching = "body",
	Returning = "searching",
	Investigating = "suspicious",
	Searching = "searching",
	Pursuing = "pursuing",
	CombatClosing = "closing",
	Reloading = "reloading",
}

-- enemy -> last awareness sent to clients
local LastAwareness = {}
-- enemy -> remaining alert flash time
local AlertFlash = {}
-- enemy -> whether the player was visible last poll (for lost-sight detection)
local WasVisible = {}

local function GetAwareness(enemy)
	if enemy.IsDead then return "none" end

	local model = enemy.Model
	if model then
		if model:GetAttribute("TargetSurrendered") == true then
			return "surrender"
		end
		if model:GetAttribute("TargetFleeing") == true then
			return "flee"
		end
		local feedbackState = model:GetAttribute("EnemyFeedbackState")
		if feedbackState and FEEDBACK_STATE_AWARENESS[feedbackState] then
			return FEEDBACK_STATE_AWARENESS[feedbackState]
		end
	end

	local state = enemy:GetState()

	if state == "Combat" then
		-- Actively fighting: reduce/remove the indicator.
		-- If the player is no longer visible, the enemy is searching.
		if enemy.Perception and enemy.Perception:HasVisibleTarget() then
			return "combat"
		else
			return "searching"
		end
	elseif state == "Investigate" then
		return "suspicious"
	elseif state == "BodyInvestigate" then
		return "body"
	elseif state == "TargetFlee" then
		return "flee"
	elseif state == "TargetSurrender" then
		return "surrender"
	elseif state == "Search" then
		return "searching"
	elseif state == "Pursuing" then
		return "pursuing"
	end

	return "none"
end

local function GetEnemyPosition(enemy)
	local model = enemy and enemy.Model
	if not model or not model.Parent then return nil end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root.Position end
	return model:GetPivot().Position
end

function VisualFeedback:Start()
	if Running then return end
	Running = true
	Accumulator = 0

	-- When an enemy first confirms the player, trigger the "!" flash.
	EventsService:Subscribe("PlayerSpotted", function(event)
		local data = event.Data or {}
		local spotter = data.Spotter
		if not spotter then return end

		local enemy = EnemyService.GetEnemy(spotter)
		-- Only flash if the enemy is not already in combat (avoids re-flash
		-- every time the player re-enters view during an active fight).
		if enemy and enemy:GetState() ~= "Combat" then
			AlertFlash[enemy] = ALERT_FLASH_TIME
		end
	end)

	EventsService:Subscribe("RadioTowerDestroyed", function(event)
		local data = event.Data or {}
		local position = data.Position
		if not position then return end
		local radius = data.Radius or RADIO_TOWER_ALERT_RADIUS
		local duration = data.Duration or ALERT_FLASH_TIME
		for _, enemy in ipairs(EnemyService.GetEnemies()) do
			if enemy and not enemy.IsDead and enemy.Model and enemy.Model.Parent then
				local enemyPosition = GetEnemyPosition(enemy)
				if enemyPosition and (enemyPosition - position).Magnitude <= radius then
					-- Visual-only alert. Do not modify perception, target, movement, or AI state.
					AlertFlash[enemy] = math.max(AlertFlash[enemy] or 0, duration)
					if enemy.Audio then
						enemy.Audio:PlayBark("Alert", 0.45)
					end
				end
			end
		end
	end)

	-- Send current awareness to players who join mid-game so indicators
	-- are correct immediately.
	local function sendCurrentToPlayer(player)
		if not AwarenessRemote then return end
		for _, enemy in ipairs(EnemyService.GetEnemies()) do
			if enemy.Model and enemy.Model.Parent then
				AwarenessRemote:FireClient(player, enemy.Model, LastAwareness[enemy] or "none")
			end
		end
	end

	Players.PlayerAdded:Connect(sendCurrentToPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		sendCurrentToPlayer(player)
	end

	UpdateConnection = RunService.Heartbeat:Connect(function(DeltaTime)
		Accumulator += DeltaTime
		if Accumulator >= UpdateInterval then
			VisualFeedback:Update(Accumulator)
			Accumulator = 0
		end
	end)
end

function VisualFeedback:Stop()
	Running = false

	if UpdateConnection then
		UpdateConnection:Disconnect()
		UpdateConnection = nil
	end

	LastAwareness = {}
	AlertFlash = {}
	WasVisible = {}
end

function VisualFeedback:Update(DeltaTime)
	-- Tick down alert-flash timers
	for enemy, t in pairs(AlertFlash) do
		local remaining = t - DeltaTime
		if remaining <= 0 then
			AlertFlash[enemy] = nil
		else
			AlertFlash[enemy] = remaining
		end
	end

	for _, enemy in ipairs(EnemyService.GetEnemies()) do
		if not enemy.Model or not enemy.Model.Parent then
			LastAwareness[enemy] = nil
			WasVisible[enemy] = nil
			continue
		end

		-- Detect lost-sight transitions to fire the afterimage event
		local visible = enemy.Perception and enemy.Perception:HasVisibleTarget() or false
		local prevVisible = WasVisible[enemy] or false
		if prevVisible and not visible then
			local lkp = enemy.Perception and enemy.Perception:GetLastKnownPosition()
			if lkp and LastKnownRemote then
				LastKnownRemote:FireAllClients(enemy.Model, lkp)
			end
		end
		WasVisible[enemy] = visible

		-- Determine awareness and apply alert flash
		local awareness = GetAwareness(enemy)
		if AlertFlash[enemy] then
			awareness = "alert"
		end

		-- Fire only on change
		if LastAwareness[enemy] ~= awareness then
			LastAwareness[enemy] = awareness
			if AwarenessRemote then
				AwarenessRemote:FireAllClients(enemy.Model, awareness)
			end
		end
	end
end

function VisualFeedback:Destroy()
	self:Stop()
end

return VisualFeedback