local Casual = Instance.new("HumanoidDescription")
Casual.Name = "Casual"
Casual.BackAccessory = "16747036784"
Casual.Pants = 97964255846265
Casual.Shirt = 15350637154
Casual.NeckAccessory = "86511650437542"

local AccessoryDescription = Instance.new("AccessoryDescription")
AccessoryDescription.AccessoryType = Enum.AccessoryType.Neck
AccessoryDescription.AssetId = 86511650437542
AccessoryDescription.Parent = Casual

local AccessoryDescription1 = Instance.new("AccessoryDescription")
AccessoryDescription1.AccessoryType = Enum.AccessoryType.Back
AccessoryDescription1.AssetId = 16747036784
AccessoryDescription1.Parent = Casual

Casual.Parent = game:GetService("ServerScriptService").GameplayScripts.Enemies.Databases.Appearance.EnemyOutfits
return Casual