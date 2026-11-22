local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TargetBehaviour = {}

local VALID_BEHAVIOURS = {
	Fighter = true,
	Flee = true,
	Surrender = true,
}

local DEFAULT_BEHAVIOUR = "Surrender"
local FLEE_REISSUE_INTERVAL = 1.0
local FLEE_COMPLETE_DISTANCE = 6
local FLEE_GUARD_REACHED_DISTANCE = 10
local FLEE_GUARD_SEARCH_RADIUS = 250
local FALLBACK_FLEE_DISTANCE = 90

local function getConfiguration(model)
	if not model then return nil end
	local config = model:FindFirstChild("Configuration")
	if config and config:IsA("Configuration") then
		return config
	end
	return nil
end

local function getRoot(model)
	if not model then return nil end
	return model:FindFirstChild("HumanoidRootPart")
end

local function isAliveModel(model)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = getRoot(model)
	return model ~= nil and model.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0 and root ~= nil
end

local function getEnemyService()
	local ok, service = pcall(function()
		return require(script.Parent.EnemyService)
	end)
	if ok then
		return service
	end
	return nil
end

local function forceFleeTargetSurrender(enemy, reason)
	if not enemy or not enemy.IsTarget then return end
	local model = enemy.Model
	if model then
		model:SetAttribute("TargetFleeing", false)
		model:SetAttribute("TargetAlertState", "Surrendered")
		model:SetAttribute("TargetFleeSurrenderReason", reason or "NoAliveGuard")
	end
	if enemy.Audio then
		enemy.Audio:PlayBark("Surrender", 1)
	end
	if enemy.Movement then
		enemy.Movement:Stop()
	end
	enemy.TargetHasEscaped = false
	enemy.FleeGuard = nil
	enemy.FleeGuardModel = nil
	enemy.FleeGuardSelected = false
	enemy.FleeGuardMissing = true
	-- Convert this target instance to the surrender branch. This is intentionally
	-- per-instance only; it does not rewrite the NPC template/configuration.
	enemy.TargetBehaviour = "Surrender"
	if enemy.Perception then
		enemy.Perception.InvestigationPoint = nil
		enemy.Perception.LastKnownPosition = nil
	end
	TargetBehaviour.BeginSurrender(enemy)
	if enemy.AI then
		enemy.AI:Evaluate()
	end
end

local function findNearestAliveGuard(enemy)
	local model = enemy and enemy.Model
	local root = getRoot(model)
	if not root then return nil, nil end

	local service = getEnemyService()
	local enemies = service and typeof(service.GetEnemies) == "function" and service.GetEnemies() or {}
	local bestEnemy = nil
	local bestModel = nil
	local bestDistance = math.huge

	for i = 1, #enemies do
		local guard = enemies[i]
		local guardModel = guard and guard.Model
		if guard
			and guard ~= enemy
			and guard.IsTarget ~= true
			and guard.IsDead ~= true
			and isAliveModel(guardModel)
		then
			local guardRoot = getRoot(guardModel)
			local distance = (guardRoot.Position - root.Position).Magnitude
			if distance < bestDistance and distance <= FLEE_GUARD_SEARCH_RADIUS then
				bestDistance = distance
				bestEnemy = guard
				bestModel = guardModel
			end
		end
	end

	return bestEnemy, bestModel
end

local function findFirstBasePart(container)
	if not container then return nil end
	if container:IsA("BasePart") then return container end
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function findMapRoot(model)
	local current = model
	while current and current ~= workspace do
		if current.Name == "World" then
			return current
		end
		current = current.Parent
	end
	return workspace:FindFirstChild("World")
end

local function getConfiguredBehaviour(model)
	local attributeBehaviour = model and model:GetAttribute("TargetBehaviour")
	if typeof(attributeBehaviour) == "string" and VALID_BEHAVIOURS[attributeBehaviour] then
		return attributeBehaviour
	end

	local config = getConfiguration(model)
	local behaviourValue = config and config:FindFirstChild("TargetBehaviour")
	if behaviourValue and behaviourValue:IsA("StringValue") and VALID_BEHAVIOURS[behaviourValue.Value] then
		return behaviourValue.Value
	end

	return DEFAULT_BEHAVIOUR
end

function TargetBehaviour.IsTargetModel(model)
	local config = getConfiguration(model)
	return config ~= nil and config:FindFirstChild("TargetName") ~= nil
end

function TargetBehaviour.GetBehaviour(enemy)
	if not enemy or not enemy.Model then
		return DEFAULT_BEHAVIOUR
	end
	if typeof(enemy.TargetBehaviour) == "string" and VALID_BEHAVIOURS[enemy.TargetBehaviour] then
		return enemy.TargetBehaviour
	end
	return getConfiguredBehaviour(enemy.Model)
end

function TargetBehaviour.ShouldEquipWeapon(enemy)
	if not enemy or not enemy.IsTarget then
		return true
	end
	return TargetBehaviour.GetBehaviour(enemy) == "Fighter"
end

function TargetBehaviour.ShouldUseCombat(enemy)
	if not enemy or not enemy.IsTarget then
		return true
	end
	return TargetBehaviour.GetBehaviour(enemy) == "Fighter"
end

local function playerHasWeaponEquipped(character)
	if not character then return false end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			return true
		end
	end
	return false
end

local function playerIsFacingTarget(character, targetModel)
	local playerRoot = getRoot(character)
	local targetRoot = getRoot(targetModel)
	if not playerRoot or not targetRoot then return false end
	local offset = targetRoot.Position - playerRoot.Position
	offset = Vector3.new(offset.X, 0, offset.Z)
	if offset.Magnitude <= 0.1 then return true end
	local look = Vector3.new(playerRoot.CFrame.LookVector.X, 0, playerRoot.CFrame.LookVector.Z)
	if look.Magnitude <= 0.1 then return false end
	return look.Unit:Dot(offset.Unit) >= 0.65
end

local function hasVisibleThreat(enemy)
	local perception = enemy and enemy.Perception
	local visibleTarget = perception and perception.VisibleTarget
	if not visibleTarget then return false end
	if enemy.Model and enemy.Model:GetAttribute("RecentlyShotByVisiblePlayer") == true then
		return true
	end
	return playerHasWeaponEquipped(visibleTarget) and playerIsFacingTarget(visibleTarget, enemy.Model)
end

function TargetBehaviour.IsAlerted(enemy)
	if not enemy or enemy.IsDead then return false end
	local perception = enemy.Perception
	if not perception then return false end
	return perception:HasVisibleTarget()
		or perception:HasLastKnownPosition()
		or perception:HasInvestigationPoint()
end

function TargetBehaviour.ShouldFlee(enemy)
	return enemy ~= nil
		and enemy.IsTarget == true
		and enemy.FleeGuardMissing ~= true
		and (not enemy.Model or enemy.Model:GetAttribute("TargetSurrendered") ~= true)
		and TargetBehaviour.GetBehaviour(enemy) == "Flee"
		and TargetBehaviour.IsAlerted(enemy)
end

function TargetBehaviour.ShouldSurrender(enemy)
	return enemy ~= nil
		and enemy.IsTarget == true
		and (
			TargetBehaviour.GetBehaviour(enemy) == "Surrender"
			or (enemy.Model and enemy.Model:GetAttribute("TargetSurrendered") == true)
		)
		and (hasVisibleThreat(enemy) or (enemy.Model and enemy.Model:GetAttribute("TargetSurrendered") == true))
end

function TargetBehaviour.GetEscapePosition(enemy)
	local model = enemy and enemy.Model
	local root = getRoot(model)
	if not model or not root then return nil end

	-- Guard-seeking flee is intentionally target-Flee only. Fighter targets should
	-- never use this path; they stay in Combat through ShouldUseCombat().
	if TargetBehaviour.GetBehaviour(enemy) ~= "Flee" then
		return nil
	end

	local guard = enemy.FleeGuard
	local guardModel = (guard and guard.Model) or enemy.FleeGuardModel
	if enemy.FleeGuardSelected == true then
		if guard and guard.IsDead == true then
			forceFleeTargetSurrender(enemy, "GuardDied")
			return nil
		end
		if not isAliveModel(guardModel) then
			forceFleeTargetSurrender(enemy, "GuardUnavailable")
			return nil
		end
	else
		guard, guardModel = findNearestAliveGuard(enemy)
		enemy.FleeGuard = guard
		enemy.FleeGuardModel = guardModel
		enemy.FleeGuardSelected = guardModel ~= nil
		if not guardModel then
			forceFleeTargetSurrender(enemy, "NoAliveGuard")
			return nil
		end
	end
	local guardRoot = getRoot(guardModel)
	return guardRoot and guardRoot.Position or nil
end

local function createTargetStateMarker(model, initialText, finalText, color)
	if not model then return end
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not head then return end

	local billboard = model:FindFirstChild("TargetFleePlaceholder", true)
	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "TargetFleePlaceholder"
		billboard.Size = UDim2.fromOffset(180, 40)
		billboard.StudsOffset = Vector3.new(0, 4.45, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 140
		billboard.Parent = head

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.Jura
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.15
		label.TextScaled = true
		label.Parent = billboard
	end

	local label = billboard:FindFirstChild("Label")
	if not label or not label:IsA("TextLabel") then return end

	label.TextColor3 = color or Color3.fromRGB(255, 180, 80)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.15
	label.Text = initialText or finalText or "FLEEING"

	if finalText and finalText ~= label.Text then
		local markerToken = (billboard:GetAttribute("MarkerToken") or 0) + 1
		billboard:SetAttribute("MarkerToken", markerToken)
		task.delay(0.8, function()
			if not billboard.Parent or billboard:GetAttribute("MarkerToken") ~= markerToken then return end
			local fadeOut = TweenService:Create(label, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			})
			fadeOut:Play()
			fadeOut.Completed:Once(function()
				if not billboard.Parent or billboard:GetAttribute("MarkerToken") ~= markerToken then return end
				label.Text = finalText
				local fadeIn = TweenService:Create(label, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					TextTransparency = 0,
					TextStrokeTransparency = 0.15,
				})
				fadeIn:Play()
			end)
		end)
	end
end

function TargetBehaviour.BeginCombat(enemy)
	if not enemy or not enemy.IsTarget or TargetBehaviour.GetBehaviour(enemy) ~= "Fighter" then
		return
	end
	local model = enemy.Model
	if not model then return end
	model:SetAttribute("TargetInCombat", true)
	model:SetAttribute("TargetAlertState", "PlayerSighted")
	createTargetStateMarker(model, "PLAYER SIGHTED", "ENGAGING", Color3.fromRGB(255, 80, 80))
	task.delay(1.25, function()
		if model.Parent and model:GetAttribute("TargetInCombat") == true then
			model:SetAttribute("TargetAlertState", "Combat")
		end
	end)
end

function TargetBehaviour.EndCombat(enemy)
	if not enemy or not enemy.IsTarget then
		return
	end
	local model = enemy.Model
	if model then
		model:SetAttribute("TargetInCombat", false)
	end
end

function TargetBehaviour.BeginFlee(enemy)
	local model = enemy and enemy.Model
	if model then
		model:SetAttribute("TargetFleeing", true)
		model:SetAttribute("TargetAlertState", "PlayerSighted")
		createTargetStateMarker(model, "PLAYER SIGHTED", "FLEEING", Color3.fromRGB(255, 185, 80))
	end
	if enemy and enemy.Audio then
		enemy.Audio:PlayBark("Flee", 1)
	end
	if model then
		task.delay(1.25, function()
			if model.Parent and model:GetAttribute("TargetFleeing") == true then
				model:SetAttribute("TargetAlertState", "Fleeing")
			end
		end)
	end
	TargetBehaviour.BeginFleeMovement(enemy)
end

function TargetBehaviour.BeginFleeMovement(enemy)
	if not enemy then return end
	enemy.TargetFleeTimer = 0
	enemy.TargetHasEscaped = false
	enemy.FleeGuardMissing = false
	local guard, guardModel = findNearestAliveGuard(enemy)
	enemy.FleeGuard = guard
	enemy.FleeGuardModel = guardModel
	enemy.FleeGuardSelected = guardModel ~= nil
	if not guardModel then
		forceFleeTargetSurrender(enemy, "NoAliveGuard")
		return
	end
	if enemy.Combat then
		enemy.Combat:EndCombat()
	end
end

function TargetBehaviour.UpdateFlee(enemy, deltaTime)
	if not enemy or enemy.IsDead or enemy.TargetHasEscaped then return end
	if TargetBehaviour.GetBehaviour(enemy) ~= "Flee" then return end
	local movement = enemy.Movement
	if not movement then return end

	local guard = enemy.FleeGuard
	local guardModel = (guard and guard.Model) or enemy.FleeGuardModel
	if guard and guard.IsDead == true then
		forceFleeTargetSurrender(enemy, "GuardDied")
		return
	end
	if enemy.FleeGuardSelected == true and not isAliveModel(guardModel) then
		forceFleeTargetSurrender(enemy, "GuardUnavailable")
		return
	end
	if not enemy.FleeGuardSelected then
		guard, guardModel = findNearestAliveGuard(enemy)
		enemy.FleeGuard = guard
		enemy.FleeGuardModel = guardModel
		enemy.FleeGuardSelected = guardModel ~= nil
		if not guardModel then
			forceFleeTargetSurrender(enemy, "NoAliveGuard")
			return
		end
	end

	enemy.TargetFleeTimer = (enemy.TargetFleeTimer or 0) + deltaTime
	local escapePosition = TargetBehaviour.GetEscapePosition(enemy)
	if not escapePosition then return end

	local currentPosition = movement:GetPosition()
	if currentPosition and (currentPosition - escapePosition).Magnitude <= FLEE_GUARD_REACHED_DISTANCE then
		movement:Stop()
		local model = enemy.Model
		if model then
			model:SetAttribute("TargetFleeing", false)
			model:SetAttribute("TargetAlertState", "WithGuard")
			createTargetStateMarker(model, "FOUND GUARD", "STAYING NEAR GUARD", Color3.fromRGB(120, 200, 255))
		end
		if enemy.Audio then
			enemy.Audio:PlayBark("GuardReached", 1)
		end
		return
	end

	if enemy.TargetFleeTimer >= FLEE_REISSUE_INTERVAL or not movement:IsMoving() then
		enemy.TargetFleeTimer = 0
		movement:MoveTo(escapePosition)
	end
end

local function hasSurrenderAnimation()
	local animations = ReplicatedStorage:FindFirstChild("Animations")
	local surrenderAnimation = animations and animations:FindFirstChild("SurrenderAnimation")
	return surrenderAnimation ~= nil
		and surrenderAnimation:IsA("Animation")
		and surrenderAnimation.AnimationId ~= ""
end

local function applySurrenderPose(model)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
	end

	local upperTorso = model and (model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso"))
	local leftShoulder = upperTorso and (upperTorso:FindFirstChild("LeftShoulder") or upperTorso:FindFirstChild("Left Shoulder"))
	local rightShoulder = upperTorso and (upperTorso:FindFirstChild("RightShoulder") or upperTorso:FindFirstChild("Right Shoulder"))

	if leftShoulder and leftShoulder:IsA("Motor6D") and leftShoulder:GetAttribute("SurrenderPoseApplied") ~= true then
		leftShoulder:SetAttribute("OriginalC0", leftShoulder.C0)
		leftShoulder.C0 = leftShoulder.C0 * CFrame.Angles(math.rad(-125), 0, math.rad(-18))
		leftShoulder:SetAttribute("SurrenderPoseApplied", true)
	end

	if rightShoulder and rightShoulder:IsA("Motor6D") and rightShoulder:GetAttribute("SurrenderPoseApplied") ~= true then
		rightShoulder:SetAttribute("OriginalC0", rightShoulder.C0)
		rightShoulder.C0 = rightShoulder.C0 * CFrame.Angles(math.rad(-125), 0, math.rad(18))
		rightShoulder:SetAttribute("SurrenderPoseApplied", true)
	end
end

function TargetBehaviour.BeginSurrender(enemy)
	if enemy.Combat then
		enemy.Combat:EndCombat()
	end
	if enemy.Movement then
		enemy.Movement:Stop()
	end

	local model = enemy.Model
	if not model then return end
	model:SetAttribute("TargetSurrendered", true)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end

	for _, tool in model:GetChildren() do
		if tool:IsA("Tool") then
			tool.Parent = nil
		end
	end

	-- Clear any previous placeholder before creating the current readable state marker.
	local oldMarker = model:FindFirstChild("SurrenderPlaceholder", true)
	if oldMarker then
		oldMarker.Parent = nil
	end

	if not hasSurrenderAnimation() then
		applySurrenderPose(model)
	end

	-- Surrender has its own marker. The client hides the normal TARGET billboard
	-- while TargetSurrendered is true so these labels do not collide.
	local head = model:FindFirstChild("Head")
	if head and not head:FindFirstChild("SurrenderPlaceholder") then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "SurrenderPlaceholder"
		billboard.Size = UDim2.fromOffset(160, 36)
		billboard.StudsOffset = Vector3.new(0, 4.1, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 120
		billboard.Parent = head

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.Jura
		label.Text = "SURRENDERED"
		label.TextColor3 = Color3.fromRGB(120, 200, 255)
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.15
		label.TextScaled = true
		label.Parent = billboard
	end
end

function TargetBehaviour.UpdateSurrender(enemy, _deltaTime)
	if enemy and enemy.Movement then
		enemy.Movement:Stop()
	end
end

return TargetBehaviour