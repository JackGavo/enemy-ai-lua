local Research = Instance.new("HumanoidDescription")
Research.Name = "Research"
Research.FrontAccessory = "16904542712"
Research.BackAccessory = "16904566027"
Research.Pants = 87525310358364
Research.WaistAccessory = "72655251088306"
Research.ShouldersAccessory = "16904563498,16904569122"
Research.Shirt = 1396014535
Research.HatAccessory = "139497142937804"

local AccessoryDescription = Instance.new("AccessoryDescription")
AccessoryDescription.AccessoryType = Enum.AccessoryType.Front
AccessoryDescription.AssetId = 16904542712
AccessoryDescription.Parent = Research

local AccessoryDescription1 = Instance.new("AccessoryDescription")
AccessoryDescription1.AccessoryType = Enum.AccessoryType.Shoulder
AccessoryDescription1.AssetId = 16904569122
AccessoryDescription1.Parent = Research

local AccessoryDescription2 = Instance.new("AccessoryDescription")
AccessoryDescription2.AccessoryType = Enum.AccessoryType.Back
AccessoryDescription2.AssetId = 16904566027
AccessoryDescription2.Parent = Research

local AccessoryDescription3 = Instance.new("AccessoryDescription")
AccessoryDescription3.AccessoryType = Enum.AccessoryType.Waist
AccessoryDescription3.AssetId = 72655251088306
AccessoryDescription3.Parent = Research

local AccessoryDescription4 = Instance.new("AccessoryDescription")
AccessoryDescription4.AccessoryType = Enum.AccessoryType.Shoulder
AccessoryDescription4.AssetId = 16904563498
AccessoryDescription4.Parent = Research

local AccessoryDescription5 = Instance.new("AccessoryDescription")
AccessoryDescription5.AccessoryType = Enum.AccessoryType.Hat
AccessoryDescription5.AssetId = 139497142937804
AccessoryDescription5.Parent = Research

Research.Parent = game:GetService("ServerScriptService").GameplayScripts.Enemies.Databases.Appearance.EnemyOutfits
return Research