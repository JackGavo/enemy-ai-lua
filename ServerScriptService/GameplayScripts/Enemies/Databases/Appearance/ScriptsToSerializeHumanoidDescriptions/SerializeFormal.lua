local Formal = Instance.new("HumanoidDescription")
Formal.Name = "Formal"
Formal.Pants = 5980310519
Formal.WaistAccessory = "105077363952869"
Formal.Shirt = 16962629976
Formal.HatAccessory = "14640134963"

local AccessoryDescription = Instance.new("AccessoryDescription")
AccessoryDescription.AccessoryType = Enum.AccessoryType.Hat
AccessoryDescription.AssetId = 14640134963
AccessoryDescription.Parent = Formal

local AccessoryDescription1 = Instance.new("AccessoryDescription")
AccessoryDescription1.AccessoryType = Enum.AccessoryType.Waist
AccessoryDescription1.AssetId = 105077363952869
AccessoryDescription1.Parent = Formal

Formal.Parent = game:GetService("ServerScriptService").GameplayScripts.Enemies.Databases.Appearance.EnemyOutfits
return Formal