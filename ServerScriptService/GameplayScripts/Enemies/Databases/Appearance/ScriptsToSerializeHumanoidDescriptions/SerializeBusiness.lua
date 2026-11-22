local Business = Instance.new("HumanoidDescription")
Business.Name = "Business"
Business.Pants = 130715955949010
Business.ShouldersAccessory = "92013407959910"
Business.Shirt = 14873818191

local AccessoryDescription = Instance.new("AccessoryDescription")
AccessoryDescription.AccessoryType = Enum.AccessoryType.Shoulder
AccessoryDescription.AssetId = 92013407959910
AccessoryDescription.Parent = Business

Business.Parent = game:GetService("ServerScriptService").GameplayScripts.Enemies.Databases.Appearance.EnemyOutfits
return Business