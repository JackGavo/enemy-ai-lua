local Industrial = Instance.new("HumanoidDescription")
Industrial.Name = "Industrial"
Industrial.Pants = 112331734997112
Industrial.Shirt = 8410010539
Industrial.HatAccessory = "17537885732"
Industrial.NeckAccessory = "129579813835632"

local AccessoryDescription = Instance.new("AccessoryDescription")
AccessoryDescription.AccessoryType = Enum.AccessoryType.Neck
AccessoryDescription.AssetId = 129579813835631.98
AccessoryDescription.Parent = Industrial

local AccessoryDescription1 = Instance.new("AccessoryDescription")
AccessoryDescription1.AccessoryType = Enum.AccessoryType.Hat
AccessoryDescription1.AssetId = 17537885732
AccessoryDescription1.Parent = Industrial

Industrial.Parent = game:GetService("ServerScriptService").GameplayScripts.Enemies.Databases.Appearance.EnemyOutfits
return Industrial