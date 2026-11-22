local AppearanceFolder = game:GetService("ServerScriptService"):WaitForChild("GameplayScripts"):WaitForChild("Enemies"):WaitForChild("Databases"):WaitForChild("Appearance")
local SkinColorModule = require(AppearanceFolder:WaitForChild("SkinColors"))
local HairModule = require(AppearanceFolder:WaitForChild("Hair"))

local Outfits = {
	["Formal"] = script.Formal,
	["Business"] = script.Business,
	["Casual"] = script.Casual,
	["Military"] = script.Military,
	["Tactical"] = script.Tactical,
	["Industrial"] = script.Industrial,
	["Street"] = script.Street,
	["Research"] = script.Research,
}

-- Generate a shared appearance (skin color + hair) for all guards in a contract.
-- rng: optional Random for deterministic generation. If nil, uses math.random.
function Outfits.GenerateAppearance(rng: Random?)
	return {
		SkinColor = SkinColorModule.GetRandomSkinColor(rng),
		HairId = HairModule.GetRandomHair(rng),
	}
end

-- Apply a visual appearance to an enemy rig.
-- appearance: optional table { SkinColor: Color3, HairId: number } from GenerateAppearance.
-- If nil, generates a random appearance on the spot (non-deterministic).
function Outfits.ApplyAppearance(Enemy, AppearanceType, appearance: {SkinColor: Color3, HairId: number}?)
	local SkinColor, HairId
	if appearance then
		SkinColor = appearance.SkinColor
		HairId = appearance.HairId
	else
		SkinColor = SkinColorModule.GetRandomSkinColor()
		HairId = HairModule.GetRandomHair()
	end
	
	local HumanoidDescription = Enemy.Humanoid:GetAppliedDescription()
	
	HumanoidDescription.HeadColor = SkinColor
	HumanoidDescription.LeftArmColor = SkinColor
	HumanoidDescription.RightArmColor = SkinColor
	HumanoidDescription.LeftLegColor = SkinColor
	HumanoidDescription.RightLegColor = SkinColor
	HumanoidDescription.TorsoColor = SkinColor

	-- Hair
	if HairId and HairId ~= 0 then
		HumanoidDescription.HairAccessory = tostring(HairId)
	end
	
	-- Outfit (shirt, pants, accessories)
	local OutfitData = Outfits[AppearanceType]
	if OutfitData then
		if OutfitData.Shirt and OutfitData.Shirt ~= 0 then
			HumanoidDescription.Shirt = tostring(OutfitData.Shirt)
		end
		if OutfitData.Pants and OutfitData.Pants ~= 0 then
			HumanoidDescription.Pants = tostring(OutfitData.Pants)
		end
		
		HumanoidDescription.BackAccessory = tostring(OutfitData.BackAccessory)
		HumanoidDescription.FaceAccessory = tostring(OutfitData.FaceAccessory)
		HumanoidDescription.FrontAccessory = tostring(OutfitData.FrontAccessory)
		HumanoidDescription.HatAccessory = tostring(OutfitData.HatAccessory)
		HumanoidDescription.NeckAccessory = tostring(OutfitData.NeckAccessory)
		HumanoidDescription.ShouldersAccessory = tostring(OutfitData.ShouldersAccessory)
		HumanoidDescription.WaistAccessory = tostring(OutfitData.WaistAccessory)
	end
	
	Enemy.Humanoid:ApplyDescription(HumanoidDescription)
	
	return "Appearance Applied"
end

return Outfits
