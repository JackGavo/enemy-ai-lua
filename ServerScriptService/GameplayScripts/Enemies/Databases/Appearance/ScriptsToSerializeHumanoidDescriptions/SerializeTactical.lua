local Tactical = Instance.new("HumanoidDescription")
Tactical.Name = "Tactical"
Tactical.FrontAccessory = "16457201737"
Tactical.BackAccessory = "15407878281"
Tactical.Pants = 77078384964016
Tactical.WaistAccessory = "11922418880"
Tactical.Shirt = 100448681115184
Tactical.HatAccessory = "14930693786"
Tactical.NeckAccessory = "89984356453187"

local AccessoryDescription = Instance.new("AccessoryDescription")
AccessoryDescription.AccessoryType = Enum.AccessoryType.Hat
AccessoryDescription.AssetId = 14930693786
AccessoryDescription.Parent = Tactical

local AccessoryDescription1 = Instance.new("AccessoryDescription")
AccessoryDescription1.AccessoryType = Enum.AccessoryType.Front
AccessoryDescription1.AssetId = 16457201737
AccessoryDescription1.Parent = Tactical

local AccessoryDescription2 = Instance.new("AccessoryDescription")
AccessoryDescription2.AccessoryType = Enum.AccessoryType.Back
AccessoryDescription2.AssetId = 15407878281
AccessoryDescription2.Parent = Tactical

local AccessoryDescription3 = Instance.new("AccessoryDescription")
AccessoryDescription3.AccessoryType = Enum.AccessoryType.Waist
AccessoryDescription3.AssetId = 11922418880
AccessoryDescription3.Parent = Tactical

local AccessoryDescription4 = Instance.new("AccessoryDescription")
AccessoryDescription4.AccessoryType = Enum.AccessoryType.Neck
AccessoryDescription4.AssetId = 89984356453187
AccessoryDescription4.Parent = Tactical

Tactical.Parent = game:GetService("ServerScriptService").GameplayScripts.Enemies.Databases.Appearance.EnemyOutfits
return Tactical