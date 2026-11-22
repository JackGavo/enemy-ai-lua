local SkinColors = {
	
	Races = {
		["British"] = {
			{Color = Color3.fromRGB(246, 225, 203), Weight = 25}, -- Very light
			{Color = Color3.fromRGB(235, 203, 176), Weight = 20}, -- Light
			{Color = Color3.fromRGB(214, 174, 143), Weight = 15}, -- Light-medium
			{Color = Color3.fromRGB(190, 145, 112), Weight = 10}, -- Medium
			{Color = Color3.fromRGB(155, 110, 82), Weight = 10}, -- Brown
			{Color = Color3.fromRGB(115, 76, 55), Weight = 8}, -- Dark brown
			{Color = Color3.fromRGB(75, 48, 36), Weight = 5}, -- Dark
		},

		["French"] = {
			{Color = Color3.fromRGB(246, 225, 203), Weight = 20},
			{Color = Color3.fromRGB(235, 203, 176), Weight = 18},
			{Color = Color3.fromRGB(214, 174, 143), Weight = 17},
			{Color = Color3.fromRGB(190, 145, 112), Weight = 12},
			{Color = Color3.fromRGB(155, 110, 82), Weight = 10},
			{Color = Color3.fromRGB(115, 76, 55), Weight = 8},
			{Color = Color3.fromRGB(75, 48, 36), Weight = 5},
		},

		["East Asian"] = {
			{Color = Color3.fromRGB(250, 226, 198), Weight = 25},
			{Color = Color3.fromRGB(238, 205, 170), Weight = 25},
			{Color = Color3.fromRGB(218, 176, 137), Weight = 20},
			{Color = Color3.fromRGB(190, 145, 108), Weight = 12},
			{Color = Color3.fromRGB(160, 115, 82), Weight = 7},
			{Color = Color3.fromRGB(120, 80, 58), Weight = 3},
		},

		["American"] = {
			{Color = Color3.fromRGB(246, 225, 203), Weight = 20},
			{Color = Color3.fromRGB(235, 203, 176), Weight = 15},
			{Color = Color3.fromRGB(214, 174, 143), Weight = 12},
			{Color = Color3.fromRGB(190, 145, 112), Weight = 10},
			{Color = Color3.fromRGB(155, 110, 82), Weight = 10},
			{Color = Color3.fromRGB(115, 76, 55), Weight = 12},
			{Color = Color3.fromRGB(75, 48, 36), Weight = 8},
			{Color = Color3.fromRGB(52, 34, 27), Weight = 5},
		},

		["Spanish"] = {
			{Color = Color3.fromRGB(246, 225, 203), Weight = 15},
			{Color = Color3.fromRGB(235, 203, 176), Weight = 18},
			{Color = Color3.fromRGB(214, 174, 143), Weight = 22},
			{Color = Color3.fromRGB(190, 145, 112), Weight = 20},
			{Color = Color3.fromRGB(155, 110, 82), Weight = 12},
			{Color = Color3.fromRGB(115, 76, 55), Weight = 7},
			{Color = Color3.fromRGB(75, 48, 36), Weight = 3},
		},

		["Italian"] = {
			{Color = Color3.fromRGB(246, 225, 203), Weight = 15},
			{Color = Color3.fromRGB(235, 203, 176), Weight = 20},
			{Color = Color3.fromRGB(214, 174, 143), Weight = 22},
			{Color = Color3.fromRGB(190, 145, 112), Weight = 20},
			{Color = Color3.fromRGB(155, 110, 82), Weight = 13},
			{Color = Color3.fromRGB(115, 76, 55), Weight = 7},
			{Color = Color3.fromRGB(75, 48, 36), Weight = 3},
		},

		["German"] = {
			{Color = Color3.fromRGB(250, 228, 207), Weight = 30},
			{Color = Color3.fromRGB(238, 208, 180), Weight = 25},
			{Color = Color3.fromRGB(216, 176, 143), Weight = 18},
			{Color = Color3.fromRGB(190, 145, 112), Weight = 10},
			{Color = Color3.fromRGB(155, 110, 82), Weight = 8},
			{Color = Color3.fromRGB(115, 76, 55), Weight = 6},
			{Color = Color3.fromRGB(75, 48, 36), Weight = 3},
		},

		["Eastern European"] = {
			{Color = Color3.fromRGB(250, 228, 207), Weight = 25},
			{Color = Color3.fromRGB(238, 208, 180), Weight = 25},
			{Color = Color3.fromRGB(216, 176, 143), Weight = 20},
			{Color = Color3.fromRGB(190, 145, 112), Weight = 12},
			{Color = Color3.fromRGB(155, 110, 82), Weight = 8},
			{Color = Color3.fromRGB(115, 76, 55), Weight = 7},
			{Color = Color3.fromRGB(75, 48, 36), Weight = 3},
		},

		["Arabic"] = {
			{Color = Color3.fromRGB(246, 225, 203), Weight = 8},
			{Color = Color3.fromRGB(235, 203, 176), Weight = 12},
			{Color = Color3.fromRGB(214, 174, 143), Weight = 20},
			{Color = Color3.fromRGB(190, 145, 112), Weight = 25},
			{Color = Color3.fromRGB(155, 110, 82), Weight = 20},
			{Color = Color3.fromRGB(115, 76, 55), Weight = 12},
			{Color = Color3.fromRGB(75, 48, 36), Weight = 3},
		},

		["African"] = {
			{Color = Color3.fromRGB(155, 110, 82), Weight = 15},
			{Color = Color3.fromRGB(115, 76, 55), Weight = 25},
			{Color = Color3.fromRGB(90, 57, 43), Weight = 25},
			{Color = Color3.fromRGB(75, 48, 36), Weight = 20},
			{Color = Color3.fromRGB(52, 34, 27), Weight = 10},
		},

		["South American"] = {
			{Color = Color3.fromRGB(246, 225, 203), Weight = 10},
			{Color = Color3.fromRGB(235, 203, 176), Weight = 15},
			{Color = Color3.fromRGB(214, 174, 143), Weight = 22},
			{Color = Color3.fromRGB(190, 145, 112), Weight = 25},
			{Color = Color3.fromRGB(155, 110, 82), Weight = 18},
			{Color = Color3.fromRGB(115, 76, 55), Weight = 8},
			{Color = Color3.fromRGB(75, 48, 36), Weight = 2},
		},

		["South Asian"] = {
			{Color = Color3.fromRGB(214, 174, 143), Weight = 10},
			{Color = Color3.fromRGB(190, 145, 112), Weight = 25},
			{Color = Color3.fromRGB(155, 110, 82), Weight = 30},
			{Color = Color3.fromRGB(115, 76, 55), Weight = 20},
			{Color = Color3.fromRGB(90, 57, 43), Weight = 10},
			{Color = Color3.fromRGB(75, 48, 36), Weight = 5},
		},
	}
}

function SkinColors.GetRandomSkinColor(rng: Random?)
	local AllKeys = {}

	for Key in pairs(SkinColors.Races) do
		table.insert(AllKeys, Key)
	end
	table.sort(AllKeys) -- deterministic key ordering

	if rng then
		local ChosenRace = AllKeys[rng:NextInteger(1, #AllKeys)]
		local ChosenSkin = SkinColors.Races[ChosenRace][rng:NextInteger(1, #SkinColors.Races[ChosenRace])]
		return ChosenSkin.Color
	else
		local ChosenRace = AllKeys[math.random(1, #AllKeys)]
		local ChosenSkin = SkinColors.Races[ChosenRace][math.random(1, #SkinColors.Races[ChosenRace])]
		return ChosenSkin.Color
	end
end

return SkinColors