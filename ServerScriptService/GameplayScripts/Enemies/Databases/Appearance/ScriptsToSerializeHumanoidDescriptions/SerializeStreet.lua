local Street = Instance.new("HumanoidDescription")
Street.Name = "Street"
Street.FrontAccessory = "105392358018955"
Street.FaceAccessory = "13734096288"
Street.Pants = 106299314965836
Street.Shirt = 17478437058

local AccessoryDescription = Instance.new("AccessoryDescription")
AccessoryDescription.AccessoryType = Enum.AccessoryType.Face
AccessoryDescription.AssetId = 13734096288
AccessoryDescription.Parent = Street

local AccessoryDescription1 = Instance.new("AccessoryDescription")
AccessoryDescription1.AccessoryType = Enum.AccessoryType.Front
AccessoryDescription1.AssetId = 105392358018955
AccessoryDescription1.Parent = Street

Street.Parent = game:GetService("ServerScriptService").GameplayScripts.Enemies.Databases.Appearance.EnemyOutfits
return Street