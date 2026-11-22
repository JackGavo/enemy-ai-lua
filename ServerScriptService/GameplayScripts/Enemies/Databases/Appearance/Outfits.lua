--[[
	Each OutfitProfile corresponds to an outfit name used in MapTargetProfiles.
	Fill in the Shirts, Pants, FaceAccessories, and HatAccessories lists with asset IDs.

	Shirts           -> List of shirt asset IDs (one is randomly chosen)
	Pants            -> List of pants asset IDs (one is randomly chosen)
	FaceAccessories  -> List of face accessory asset IDs (randomly chosen or none)
	HatAccessories   -> List of hat accessory asset IDs (randomly chosen or none)
]]

local Outfits = {

	["Formal"] = { --eg. Politician
		Shirts = {120968489106939, 16403806782, 9531190643, 6163928929, 6441272856, 8975238909, 73580047963249, 18951287027},
		Pants = {129459077},
		FaceAccessories = {99699112583130,92122350080935,13895617178,97523510749859, 13895692779, 4566955443 },
		HatAccessories = {0, 0},
	},

	["Business"] = { --eg. Mafia Boss
		Shirts = {8194652844, 8576501842, 6430379228, 8399762292, 108365778918095, 2341057785, 13579647665, 5317507329, 11785622290, 6430387753},
		Pants = {129459077},
		FaceAccessories = {14756083995, 97523510749859, 13895692779, 14400254687, 4566955443},
		HatAccessories = {15414670699},
	},

	["Casual"] = { --eg. Civillian
		Shirts = {
			989569058, 1084671829, 5089880729, 17012914446, 10879148733, 9651822965, 1966266996, 10912195525, 9030781536, 
			1724683224, 1988648762, 4669171298, 14410576050, 12136079062, 18520324730, 451742043, 119326470448383,
			16785536760, 11803197212
		},
		Pants = {129458426, 382537569, 398633812},
		FaceAccessories = {71633776261237,97523510749859, 13895692779, 14400254687},
		HatAccessories = {0,0,0,0,0, 130423534764188, 70995240773400, 17537885732,113517555491911,  },
	},

	["Military"] = { --eg. Dictator
		Shirts = {6554585122, 3831703686, 7258734198, 84900219535819, 5153670245, 13736940603, 617727995},
		Pants = {129459077},
		FaceAccessories = {134025304816175, 136591222747465, 99699112583130, 100014532645105, 71633776261237, 100712260187350, 105531815232256 },
		HatAccessories = {113771397716953, 139604058405461, 73363839882340, 114244612940867, 136736642924638, 116044009934320, 112265222129671},
	},

	["Tactical"] = { --eg. Soldier
		Shirts = {17247857157, 16228727354, 115452133552257, 114026752170804, 15319848545, 16228849906, 84940813904843},
		Pants = {114185738627902, 117754492284844, 17247861524, 137569145986256, 122229863313069, 12392538903},
		FaceAccessories = {13950662956, 98868155993924, 14353960778, 87669926185132, 139123655751888},
		HatAccessories = {0, 0},
	},

	["Industrial"] = { --eg. Arms Dealer
		Shirts = {15932007106, 95463552895770, 14890815749, 15764166906, 10529508920, 89806220438748, 2933479297, 7131307422},
		Pants = {93794090682826, 5666581419, 11260366718, 139477514804467},
		FaceAccessories = {100014532645105, 102702422571506, 140468746932375, 4995497755, 13895617178, 90508774599329, 139183236932780, 18613002727, 120966214228970},
		HatAccessories = {0, 111658821303922, 126079429790779},
	},

	["Street"] = { --eg. Gangster
		Shirts = {71846498926163, 82100521805324, 137464426804937, 99785713680816, 12777837822, 14971251916, 17477482351, 111090354601819, 16028242418, 17478867529, 8408502740 },
		Pants = {129458426, 382537569, 398633812},
		FaceAccessories = {15363570725,106341368015973,105288880359127,83252900208687},
		HatAccessories = {0, 0},
	},

	["Research"] = { --eg. Professor
		Shirts = {5341870490, 4748282155, 4963364290, 13681891951, 17810710684},
		Pants = {6277951635, 13681894398, 111134251569837, 13955628695},
		FaceAccessories = {97523510749859, 13895692779, 4566955443, 107769091300864, 103715181625160},
		HatAccessories = {0, 0},
	},

}

-- Picks a random element from a list, or returns nil if the list is empty
local function PickRandom(list: {number}): number?
	if not list or #list == 0 then return nil end
	return list[math.random(1, #list)]
end

-- 50% chance to pick an accessory from the list, otherwise returns nil
local function PickAccessory(list: {number}): number?
	if not list or #list == 0 then return nil end
	if math.random() <= 0.5 then
		return PickRandom(list)
	end
	return nil
end

function Outfits.GenerateOutfit(OutfitName: string): table?
	local profile = Outfits[OutfitName]
	if not profile then
		warn("[Outfits] Outfit not found:", OutfitName)
		return nil
	end

	return {
		Shirt = PickRandom(profile.Shirts),
		Pants = PickRandom(profile.Pants),
		FaceAccessory = PickAccessory(profile.FaceAccessories),
		HatAccessory = PickAccessory(profile.HatAccessories),
	}
end

return Outfits
