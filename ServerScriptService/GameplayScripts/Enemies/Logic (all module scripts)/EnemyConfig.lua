local EnemyConfig = {}

local DEFAULTS = {
	DetectionRange = 110,
	VisionFOV = 100,
	CloseRange = 8,
	HearingRange = 30,
	WeaponName = "MP5",
	Accuracy = 0.7,
	ReactionTime = 0.25,
	MovementSpeed = 12,
	CombatMaxRange = 60,
	CombatMinRange = 8,
	StrafeInterval = 2.5,
	CombatMoveTick = 0.5,
	AlertRadius = 40,
	SearchDuration = 15,
	SearchRadius = 25,
	SearchMaxPoints = 4,
	SearchPointCooldown = 0.75,
	InvestigateDuration = 10,
	InvestigateRadius = 15,
	MeleeRange = 7,
	ClusterDetectionRadius = 15,
	UnlimitedMags = true,
}

local ARCHETYPES = {
	Street = {
		DetectionRange = 85,
		VisionFOV = 95,
		HearingRange = 28,
		WeaponName = "Glock 17",
		Accuracy = 0.55,
		ReactionTime = 0.45,
		MovementSpeed = 12,
		CombatMaxRange = 48,
		AlertRadius = 35,
	},
	Casual = {
		DetectionRange = 80,
		VisionFOV = 90,
		HearingRange = 25,
		WeaponName = "Sauer P320",
		Accuracy = 0.5,
		ReactionTime = 0.5,
		MovementSpeed = 12,
		CombatMaxRange = 45,
		AlertRadius = 30,
	},
	Business = {
		DetectionRange = 82,
		VisionFOV = 95,
		HearingRange = 26,
		WeaponName = "Glock 17",
		Accuracy = 0.55,
		ReactionTime = 0.45,
		MovementSpeed = 12,
		CombatMaxRange = 45,
	},
	Formal = {
		DetectionRange = 80,
		VisionFOV = 90,
		HearingRange = 24,
		WeaponName = "Sauer P320",
		Accuracy = 0.5,
		ReactionTime = 0.5,
		MovementSpeed = 11,
		CombatMaxRange = 42,
	},
	Industrial = {
		DetectionRange = 85,
		VisionFOV = 100,
		HearingRange = 32,
		WeaponName = "UMP45 Tactical",
		Accuracy = 0.62,
		ReactionTime = 0.35,
		MovementSpeed = 12,
		CombatMaxRange = 57,
	},
	Research = {
		DetectionRange = 90,
		VisionFOV = 105,
		HearingRange = 30,
		WeaponName = "MP5",
		Accuracy = 0.62,
		ReactionTime = 0.35,
		MovementSpeed = 12,
		CombatMaxRange = 57,
	},
	Military = {
		DetectionRange = 105,
		VisionFOV = 110,
		HearingRange = 40,
		WeaponName = "M4A1",
		Accuracy = 0.78,
		ReactionTime = 0.2,
		MovementSpeed = 13,
		CombatMaxRange = 80,
		AlertRadius = 55,
		MeleeRange = 7,
		ClusterDetectionRadius = 15,
	},
	Tactical = {
		DetectionRange = 115,
		VisionFOV = 120,
		HearingRange = 45,
		WeaponName = "HK416",
		Accuracy = 0.85,
		ReactionTime = 0.15,
		MovementSpeed = 14,
		CombatMaxRange = 90,
		CombatMinRange = 10,
		AlertRadius = 65,
		MeleeRange = 7,
		ClusterDetectionRadius = 15,
	},
}

local NUMERIC_KEYS = {
	"DetectionRange", "VisionFOV", "CloseRange", "HearingRange", "Accuracy", "ReactionTime",
	"MovementSpeed", "CombatMaxRange", "CombatMinRange", "StrafeInterval", "CombatMoveTick",
	"AlertRadius", "SearchDuration", "SearchRadius", "SearchMaxPoints", "SearchPointCooldown",
	"InvestigateDuration", "InvestigateRadius", "MeleeRange", "ClusterDetectionRadius",
}

local STRING_KEYS = { "WeaponName", "CombatBehaviour", "AlertBehaviour" }
local BOOLEAN_KEYS = { "UnlimitedMags" }

local function readValueObject(folder, key)
	if not folder then return nil end
	local value = folder:FindFirstChild(key)
	if value and value:IsA("ValueBase") then
		return value.Value
	end
	return nil
end

local function readOverride(model, key)
	if not model then return nil end
	local attribute = model:GetAttribute(key)
	if attribute ~= nil then
		return attribute
	end
	local folder = model:FindFirstChild("EnemyConfiguration") or model:FindFirstChild("Configuration")
	return readValueObject(folder, key)
end

function EnemyConfig.Resolve(model)
	local archetype = readOverride(model, "EnemyArchetype") or readOverride(model, "Archetype") or "Street"
	local resolved = {}

	for key, value in DEFAULTS do
		resolved[key] = value
	end

	local archetypeDefaults = ARCHETYPES[archetype]
	if archetypeDefaults then
		for key, value in archetypeDefaults do
			resolved[key] = value
		end
	end

	for i = 1, #NUMERIC_KEYS do
		local key = NUMERIC_KEYS[i]
		local override = readOverride(model, key)
		if typeof(override) == "number" then
			resolved[key] = override
		end
	end

	for i = 1, #STRING_KEYS do
		local key = STRING_KEYS[i]
		local override = readOverride(model, key)
		if typeof(override) == "string" and override ~= "" then
			resolved[key] = override
		end
	end

	for i = 1, #BOOLEAN_KEYS do
		local key = BOOLEAN_KEYS[i]
		local override = readOverride(model, key)
		if typeof(override) == "boolean" then
			resolved[key] = override
		end
	end

	resolved.EnemyArchetype = archetype
	resolved.Accuracy = math.clamp(resolved.Accuracy, 0, 1)
	resolved.SearchMaxPoints = math.max(1, math.floor(resolved.SearchMaxPoints))
	return resolved
end

function EnemyConfig.ApplyAttributes(model, config)
	if not model or not config then return end
	model:SetAttribute("EnemyArchetype", config.EnemyArchetype)
	model:SetAttribute("DetectionRange", config.DetectionRange)
	model:SetAttribute("VisionFOV", config.VisionFOV)
	model:SetAttribute("HearingRange", config.HearingRange)
	model:SetAttribute("WeaponName", config.WeaponName)
	model:SetAttribute("Accuracy", config.Accuracy)
	model:SetAttribute("ReactionTime", config.ReactionTime)
	model:SetAttribute("MovementSpeed", config.MovementSpeed)
	model:SetAttribute("CombatMaxRange", config.CombatMaxRange)
	model:SetAttribute("AlertRadius", config.AlertRadius)
	model:SetAttribute("MeleeRange", config.MeleeRange)
	model:SetAttribute("ClusterDetectionRadius", config.ClusterDetectionRadius)
	model:SetAttribute("UnlimitedMags", config.UnlimitedMags ~= false)
end

return EnemyConfig
