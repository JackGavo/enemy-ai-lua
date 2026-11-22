-- Module Script
local MapTargetProfiles = {

	["Luxury"] = {
		Archetypes = {
			"Corporate Executive",
			"Criminal Broker",
			"Political Figure",
			"Intelligence Asset",
		},

		Outfits = {
			"Formal",
			"Business"
		},
	},

	["Military"] = {
		Archetypes = {
			"Military Officer",
			"Arms Dealer",
			"Intelligence Asset",
			"PMC Executive",
		},

		Outfits = {
			"Military",
			"Tactical"
		},
	},

	["Industrial"] = {
		Archetypes = {
			"Arms Dealer",
			"Smuggler",
			"Criminal Broker",
			"Corporate Executive",
			"PMC Executive",
		},

		Outfits = {
			"Business",
			"Industrial",
			"Casual",
			"Tactical",
		},
	},

	["Urban"] = {
		Archetypes = {
			"Corporate Executive",
			"Criminal Broker",
			"Cybercriminal",
			"Smuggler",
			"Intelligence Asset",
		},

		Outfits = {
			"Business",
			"Formal",
			"Casual",
			"Street",
		},
	},

	["Research"] = {
		Archetypes = {
			"Scientist",
			"Cybercriminal",
			"Corporate Executive",
			"Intelligence Asset",
		},

		Outfits = {
			"Business",
			"Casual",
			"Research",
			"Formal",
		},
	},
}

local GetTargetProfilesFunction = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunctions"):WaitForChild("GetTargetProfiles")
GetTargetProfilesFunction.OnServerInvoke = function()
	local TargetProfiles = {}

	for Profile,_ in pairs(MapTargetProfiles) do
		TargetProfiles[#TargetProfiles+1] = Profile
	end

	return TargetProfiles

end

return MapTargetProfiles
