local Military = Instance.new("HumanoidDescription")
Military.Name = "Military"
Military.FrontAccessory = "93927778707296"
Military.FaceAccessory = "108720850979392"
Military.BackAccessory = "121494415920919"
Military.Pants = 12623832394
Military.WaistAccessory = "108733335713641"
Military.ShouldersAccessory = "129394318113384,78245014542630"
Military.Shirt = 14652939582
Military.HatAccessory = "126696340075766"
Military.NeckAccessory = "139928309261937"

local AccessoryDescription = Instance.new("AccessoryDescription")
AccessoryDescription.AccessoryType = Enum.AccessoryType.Hat
AccessoryDescription.AssetId = 126696340075766.02
AccessoryDescription.Parent = Military

local AccessoryDescription1 = Instance.new("AccessoryDescription")
AccessoryDescription1.AccessoryType = Enum.AccessoryType.Front
AccessoryDescription1.AssetId = 93927778707296
AccessoryDescription1.Parent = Military

local AccessoryDescription2 = Instance.new("AccessoryDescription")
AccessoryDescription2.AccessoryType = Enum.AccessoryType.Back
AccessoryDescription2.AssetId = 121494415920919
AccessoryDescription2.Parent = Military

local AccessoryDescription3 = Instance.new("AccessoryDescription")
AccessoryDescription3.AccessoryType = Enum.AccessoryType.Waist
AccessoryDescription3.AssetId = 108733335713641
AccessoryDescription3.Parent = Military

local AccessoryDescription4 = Instance.new("AccessoryDescription")
AccessoryDescription4.AccessoryType = Enum.AccessoryType.Shoulder
AccessoryDescription4.AssetId = 78245014542630
AccessoryDescription4.Parent = Military

local AccessoryDescription5 = Instance.new("AccessoryDescription")
AccessoryDescription5.AccessoryType = Enum.AccessoryType.Shoulder
AccessoryDescription5.AssetId = 129394318113384.02
AccessoryDescription5.Parent = Military

local AccessoryDescription6 = Instance.new("AccessoryDescription")
AccessoryDescription6.AccessoryType = Enum.AccessoryType.Neck
AccessoryDescription6.AssetId = 139928309261936.98
AccessoryDescription6.Parent = Military

local AccessoryDescription7 = Instance.new("AccessoryDescription")
AccessoryDescription7.AccessoryType = Enum.AccessoryType.Face
AccessoryDescription7.AssetId = 108720850979392
AccessoryDescription7.Parent = Military

Military.Parent = game:GetService("ServerScriptService").GameplayScripts.Enemies.Databases.Appearance.EnemyOutfits
return Military