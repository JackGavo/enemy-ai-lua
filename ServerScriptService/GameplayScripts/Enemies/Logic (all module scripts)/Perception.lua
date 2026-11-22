local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local EventsService = require(ServerScriptService.GameplayScripts.Events.EventsService)
local Perception = {}
Perception.__index = Perception

local EnemyService = nil

function Perception.SetEnemyService(service)
	EnemyService = service
end

local function getPlayerCharacters()
	if EnemyService and typeof(EnemyService.GetPlayerCharacters) == "function" then
		return EnemyService.GetPlayerCharacters()
	end

	local characters = {}
	local players = Players:GetPlayers()
	for i = 1, #players do
		local character = players[i].Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and character.Parent and humanoid and humanoid.Health > 1 and root then
			table.insert(characters, {
				Character = character,
				Position = root.Position,
			})
		end
	end
	return characters
end

local function getDeadBodies()
	if EnemyService and typeof(EnemyService.GetDeadBodies) == "function" then
		return EnemyService.GetDeadBodies()
	end
	return {}
end

-- Default perception parameters
-- Vision: distance, FOV cone, close-range detection, line of sight via raycast
-- Hearing: simple distance-based check
local DEFAULT_VISION_RANGE = 75   -- studs
local DEFAULT_FOV = 100           -- degrees (total cone)
local DEFAULT_CLOSE_RANGE = 12    -- studs — detect even behind at this range
local DEFAULT_HEARING_RANGE = 45 -- studs
local PLAYER_DEATH_HEALTH = 1
local OPTICAL_CAMOUFLAGE_ATTRIBUTE = "OpticalCamouflageActive"
local SMOKE_BLINDED_ATTRIBUTE = "SmokeBlinded"

local SharedRaycastParams = RaycastParams.new()
SharedRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

-- A part is considered see-through glass if it is a WINDOW named, glass material,
-- with partial transparency (not fully opaque, not fully invisible).
local function isSeeThroughWindow(part)
	return part ~= nil
		and part:IsA("BasePart")
		and part.Name == "WINDOW"
		and part.Material == Enum.Material.Glass
		and part.Transparency >= 0.5
		and part.Transparency < 1
end

-- Multi-step raycast that passes through see-through WINDOW parts. Returns nil if
-- the path is clear (no obstruction), or the first non-window RaycastResult if
-- something solid blocks the line of sight.
local function raycastSeeThrough(origin, direction, raycastParams)
	local totalDistance = direction.Magnitude
	if totalDistance <= 0 then return nil end
	local dirUnit = direction.Unit
	local currentPos = origin
	local remaining = totalDistance

	local lastResult = nil
	for _ = 1, 10 do
		local result = Workspace:Raycast(currentPos, dirUnit * remaining, raycastParams)
		lastResult = result
		if not result then
			return nil -- clear path
		end

		if isSeeThroughWindow(result.Instance) then
			-- Step just past this window and continue raycasting
			local traveled = (result.Position - origin).Magnitude
			currentPos = result.Position + dirUnit * 0.01
			remaining = totalDistance - traveled - 0.01
			if remaining <= 0 then return nil end
		else
			return result -- hit a solid obstruction
		end
	end

	-- Hit too many windows in one ray; treat as blocked
	return lastResult or { Instance = nil, Position = currentPos }
end

local function setAwarenessIndicator(model, symbol, color, duration)
	if not model then return end
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not head then return end

	local existing = model:FindFirstChild("AwarenessIndicator", true)
	if existing and existing:IsA("BillboardGui") then
		existing.Parent = nil
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "AwarenessIndicator"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(44, 44)
	gui.StudsOffset = Vector3.new(0, 2.9, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 150

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Jura
	label.Text = symbol or "?"
	label.TextColor3 = color or Color3.fromRGB(255, 230, 80)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Parent = gui

	gui.Parent = head

	local lifetime = duration or 2.25
	task.delay(lifetime, function()
		if gui and gui.Parent then
			local tween = TweenService:Create(label, TweenInfo.new(0.35), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			})
			tween:Play()
			tween.Completed:Wait()
			if gui then
				gui.Parent = nil
			end
		end
	end)
end

local function facePosition(model, position)
	if not model or not position then return end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end

	-- Do not PivotTo the whole model here. Some enemy model pivots are offset from
	-- the HumanoidRootPart, so PivotTo can subtly rewrite the rig's position/Y when
	-- the enemy is repeatedly hit and turns toward the shooter. Match the Marine
	-- style instead: rotate only the root on the horizontal yaw plane.
	local rootPosition = root.Position
	local flatTarget = Vector3.new(position.X, rootPosition.Y, position.Z)
	local flatOffset = flatTarget - rootPosition
	if flatOffset.Magnitude <= 0.1 then return end

	local velocity = root.AssemblyLinearVelocity
	local angularVelocity = root.AssemblyAngularVelocity
	root.CFrame = CFrame.lookAt(rootPosition, rootPosition + flatOffset.Unit, Vector3.yAxis)
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.min(velocity.Y, 0), velocity.Z)
	root.AssemblyAngularVelocity = angularVelocity
end

-- Public wrapper so other modules (Enemy) can turn an enemy toward a position
-- without duplicating the root-rotation logic.
function Perception:FacePosition(position)
	if not self.Enemy or not self.Enemy.Model then return end
	facePosition(self.Enemy.Model, position)
end

local function isCharacterCamouflaged(character)
	return character ~= nil and character:GetAttribute(OPTICAL_CAMOUFLAGE_ATTRIBUTE) == true
end

local function isValidLivingTarget(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and root ~= nil and humanoid.Health > 1 and not isCharacterCamouflaged(character)
end


local function isInActiveWorld(instance)
	local world = Workspace:FindFirstChild("World")
	if not world then return true end
	return instance ~= nil and instance:IsDescendantOf(world)
end

function Perception.new(Enemy)
	local self = setmetatable({}, Perception)

	self.Enemy = Enemy

	-- Configuration
	local config = Enemy.Config or {}
	self.VisionRange = config.DetectionRange or DEFAULT_VISION_RANGE
	self.FOV = config.VisionFOV or DEFAULT_FOV
	self.CloseRange = config.CloseRange or DEFAULT_CLOSE_RANGE
	self.HearingRange = config.HearingRange or DEFAULT_HEARING_RANGE

	-- State
	self.VisibleTarget = nil          -- character model currently visible
	self.LastKnownPosition = nil      -- Vector3
	self.InvestigationPoint = nil     -- Vector3
	self.WasVisible = false           -- track transitions for event firing

	-- Pursuit state: when the player leaves normal vision range/FOV but still has
	-- clear line of sight, we maintain the target via LOS-only checks (no FOV cone).
	self.PursuitTarget = nil           -- character being pursued via LOS-only
	self.LastVisibleTarget = nil       -- last character that was normally visible
	self.LastVisibleTime = 0           -- os.clock() when we last had normal vision
	self.PursuitRange = config.PursuitRange or math.huge  -- LOS-only pursuit has no distance limit by default

	return self
end

function Perception:HasVisibleTarget()
	return self.VisibleTarget ~= nil
end

function Perception:HasPursuitTarget()
	return self.PursuitTarget ~= nil
end

function Perception:GetPursuitTarget()
	return self.PursuitTarget
end

function Perception:IsPursuing()
	return self.PursuitTarget ~= nil
end

function Perception:HasInvestigationPoint()
	return self.InvestigationPoint ~= nil
end

function Perception:GetInvestigationPoint()
	return self.InvestigationPoint
end

function Perception:HasLastKnownPosition()
	return self.LastKnownPosition ~= nil
end

function Perception:GetLastKnownPosition()
	return self.LastKnownPosition
end

function Perception:IsTargetWithinVisionCone(originPart, targetPosition)
	if not originPart or not targetPosition then return false end
	local origin = originPart.Position
	local offset = targetPosition - origin
	local distance = offset.Magnitude

	if distance > self.VisionRange then return false end
	if distance <= self.CloseRange then return true end
	if distance <= 0.1 then return true end

	local dot = originPart.CFrame.LookVector:Dot(offset.Unit)
	local cosHalfFOV = math.cos(math.rad(self.FOV / 2))
	return dot >= cosHalfFOV
end

function Perception:HasLineOfSight(originPart, targetModel, targetPosition)
	if not originPart or not targetModel or not targetPosition then return false end
	SharedRaycastParams.FilterDescendantsInstances = { self.Enemy.Model, targetModel }
	local result = raycastSeeThrough(originPart.Position, targetPosition - originPart.Position, SharedRaycastParams)
	return result == nil
end

function Perception:IsSmokeBlinded()
	local model = self.Enemy and self.Enemy.Model
	return model ~= nil and model:GetAttribute(SMOKE_BLINDED_ATTRIBUTE) == true
end

function Perception:CanSeeTarget(Character)
	if self:IsSmokeBlinded() then return false end
	if not Character or isCharacterCamouflaged(Character) then return false end
	if not self.Enemy or not isInActiveWorld(self.Enemy.Model) then return false end

	local hrp = Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	-- Skip downed/dead characters. This project uses Health == 1 as the player
	-- death/contract-failed state, so enemies should stop targeting at that point.
	local humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= PLAYER_DEATH_HEALTH then return false end

	local originPart = self:GetOriginPart()
	if not originPart then return false end

	local targetPos = hrp.Position
	if not self:IsTargetWithinVisionCone(originPart, targetPos) then return false end

	return self:HasLineOfSight(originPart, Character, targetPos)
end

function Perception:CanSeeTargetByLineOfSightOnly(Character)
	if self:IsSmokeBlinded() then return false end
	if not isValidLivingTarget(Character) then return false end
	if not self.Enemy or not isInActiveWorld(self.Enemy.Model) then return false end

	local hrp = Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local originPart = self:GetOriginPart()
	if not originPart then return false end

	-- No FOV check and no range check: pure raycast visibility.
	return self:HasLineOfSight(originPart, Character, hrp.Position)
end

function Perception:CanSeeTargetFromShotReaction(Character)
	if self:IsSmokeBlinded() then return false end
	if not isValidLivingTarget(Character) then return false end
	if not self.Enemy or not isInActiveWorld(self.Enemy.Model) then return false end

	local originPart = self:GetOriginPart()
	if not originPart then return false end

	local maxRange = (self.VisionRange or DEFAULT_VISION_RANGE) * 2
	local targets = {
		Character:FindFirstChild("HumanoidRootPart"),
		Character:FindFirstChild("Head"),
	}

	for i = 1, #targets do
		local part = targets[i]
		if part and part:IsA("BasePart") then
			local offset = part.Position - originPart.Position
			if offset.Magnitude <= maxRange and self:HasLineOfSight(originPart, Character, part.Position) then
				return true
			end
		end
	end

	return false
end

function Perception:CanHear(Position)
	if not Position then return false end
	local myPos = self:GetPosition()
	if not myPos then return false end
	return (Position - myPos).Magnitude <= self.HearingRange
end

function Perception:GetVisibleTargets()
	local visible = {}
	if self:IsSmokeBlinded() then return visible end
	local originPart = self:GetOriginPart()
	if not originPart then return visible end

	local characters = getPlayerCharacters()
	for i = 1, #characters do
		local entry = characters[i]
		local character = entry.Character
		if character and character.Parent and not isCharacterCamouflaged(character) and self:IsTargetWithinVisionCone(originPart, entry.Position) then
			if self:HasLineOfSight(originPart, character, entry.Position) then
				table.insert(visible, character)
			end
		end
	end
	return visible
end

function Perception:GetNearestVisibleTarget()
	local nearest = nil
	if self:IsSmokeBlinded() then return nil end
	local nearestDist = math.huge
	local myPos = self:GetPosition()
	local originPart = self:GetOriginPart()
	if not myPos or not originPart then return nil end

	local characters = getPlayerCharacters()
	for i = 1, #characters do
		local entry = characters[i]
		local character = entry.Character
		if character and character.Parent and not isCharacterCamouflaged(character) and self:IsTargetWithinVisionCone(originPart, entry.Position) then
			local dist = (entry.Position - myPos).Magnitude
			if dist < nearestDist and self:HasLineOfSight(originPart, character, entry.Position) then
				nearestDist = dist
				nearest = character
			end
		end
	end
	return nearest
end

-- Check if a dead body is visible (same vision checks, no alive requirement)
function Perception:CanSeeBody(Model)
	if not Model or not Model.Parent then return false end

	local hrp = Model:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local originPart = self:GetOriginPart()
	if not originPart then return false end

	local targetPos = hrp.Position
	if not self:IsTargetWithinVisionCone(originPart, targetPos) then return false end

	return self:HasLineOfSight(originPart, Model, targetPos)
end
-- Check if a world position is visible (within vision cone and line of sight)
function Perception:CanSeePoint(position)
	if not position then return false end
	if not self.Enemy or not self.Enemy.Model or self.Enemy.IsDead then return false end
	if not isInActiveWorld(self.Enemy.Model) then return false end

	local originPart = self:GetOriginPart()
	if not originPart then return false end

	if not self:IsTargetWithinVisionCone(originPart, position) then return false end

	SharedRaycastParams.FilterDescendantsInstances = { self.Enemy.Model }
	local result = raycastSeeThrough(originPart.Position, position - originPart.Position, SharedRaycastParams)
	return result == nil
end


-- Get all visible dead enemy bodies from EnemyService's lightweight body registry
function Perception:GetVisibleBodies()
	local visible = {}
	local bodies = getDeadBodies()
	for i = 1, #bodies do
		local bodyModel = bodies[i]
		if bodyModel ~= self.Enemy.Model and self:CanSeeBody(bodyModel) then
			table.insert(visible, bodyModel)
		end
	end
	return visible
end

function Perception:ReactToShot(shotOrigin, suspectedTarget, wasHit, hitPoint)
	if not shotOrigin then return end
	if not self.Enemy or not self.Enemy.Model or self.Enemy.IsDead then return end
	if not isInActiveWorld(self.Enemy.Model) then return end

	local model = self.Enemy.Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- A direct hit gives the enemy a stronger clue: look toward the shot origin,
	-- then fight only if the attacker is actually visible. This keeps sniper shots
	-- from magically revealing the shooter from far away / out of line-of-sight.
	facePosition(model, shotOrigin)

	if wasHit and isValidLivingTarget(suspectedTarget) and self:CanSeeTargetFromShotReaction(suspectedTarget) then
		if self.Enemy and self.Enemy.IsTarget and model then
			model:SetAttribute("RecentlyShotByVisiblePlayer", true)
			task.delay(4, function()
				if model and model.Parent then
					model:SetAttribute("RecentlyShotByVisiblePlayer", false)
				end
			end)
		end
		self.VisibleTarget = suspectedTarget
		self.LastKnownPosition = suspectedTarget.HumanoidRootPart.Position
		self.InvestigationPoint = nil
		self.WasVisible = true
		setAwarenessIndicator(model, "!", Color3.fromRGB(255, 75, 75), 1.75)
		EventsService:FireEvent("PlayerSpotted", {
			Position = self.LastKnownPosition,
			Target = suspectedTarget,
			Spotter = model,
		})
		if self.Enemy and self.Enemy.AI then
			self.Enemy.AI:Evaluate()
		end
		return
	end

	-- If this enemy heard a nearby shot, turning toward the shot origin may reveal
	-- the shooter. Check visibility immediately after facing the shot source before
	-- falling back to a grounded investigation point.
	if (not wasHit) and isValidLivingTarget(suspectedTarget) and self:CanSeeTarget(suspectedTarget) then
		self.VisibleTarget = suspectedTarget
		self.LastKnownPosition = suspectedTarget.HumanoidRootPart.Position
		self.InvestigationPoint = nil
		self.WasVisible = true
		setAwarenessIndicator(model, "!", Color3.fromRGB(255, 75, 75), 1.4)
		EventsService:FireEvent("PlayerSpotted", {
			Position = self.LastKnownPosition,
			Target = suspectedTarget,
			Spotter = model,
		})
		if self.Enemy and self.Enemy.AI then
			self.Enemy.AI:Evaluate()
		end
		return
	end

	local fallbackPoint = shotOrigin
	if wasHit then
		fallbackPoint = shotOrigin
	elseif hitPoint then
		-- A missed shot with a known impact gives a directional clue. Investigate and
		-- face the shot origin rather than only walking to the bullet mark.
		fallbackPoint = shotOrigin
	else
		fallbackPoint = shotOrigin
	end

	self.InvestigationPoint = fallbackPoint
	self.LastKnownPosition = hitPoint and shotOrigin or nil
	if self.Enemy and self.Enemy.Combat then
		-- Keep the enemy weapon-up and looking toward the likely shooter direction for
		-- both direct hits and near/visible misses.
		self.Enemy.Combat:BeginAlertPosture(shotOrigin)
	end
	if not wasHit and not hitPoint then
		-- Heard a shot but has no impact clue or confirmed visual.
		self.LastKnownPosition = nil
	end
	setAwarenessIndicator(model, "?", Color3.fromRGB(255, 230, 80), 2.25)
	if self.Enemy and self.Enemy.AI then
		self.Enemy.AI:Evaluate()
	end
end

-- React to gunfire heard from anywhere on the map (no distance limit).
-- The enemy turns toward the shot origin, raycasts to see if the shooter is
-- visible, and engages if so. Otherwise falls back to investigating the origin.
function Perception:ReactToDistantShot(shotOrigin, suspectedTarget)
	if not shotOrigin then return end
	if not self.Enemy or not self.Enemy.Model or self.Enemy.IsDead then return end
	if not isInActiveWorld(self.Enemy.Model) then return end

	local model = self.Enemy.Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Turn toward the gunfire origin
	facePosition(model, shotOrigin)

	-- After turning, raycast to see if the shooter is visible
	if isValidLivingTarget(suspectedTarget) and self:CanSeeTargetFromShotReaction(suspectedTarget) then
		self.VisibleTarget = suspectedTarget
		self.LastKnownPosition = suspectedTarget.HumanoidRootPart.Position
		self.InvestigationPoint = nil
		self.WasVisible = true
		setAwarenessIndicator(model, "!", Color3.fromRGB(255, 75, 75), 1.75)
		EventsService:FireEvent("PlayerSpotted", {
			Position = self.LastKnownPosition,
			Target = suspectedTarget,
			Spotter = model,
		})
		if self.Enemy and self.Enemy.AI then
			self.Enemy.AI:Evaluate()
		end
		return
	end

	-- Heard gunfire from afar but cannot see the shooter: investigate the origin
	self.InvestigationPoint = shotOrigin
	self.LastKnownPosition = nil
	setAwarenessIndicator(model, "?", Color3.fromRGB(255, 230, 80), 2.25)
	if self.Enemy and self.Enemy.AI then
		self.Enemy.AI:Evaluate()
	end
end


-- React to a bullet impact that landed nearby (within IMPACT_PROXIMITY_RANGE).
-- The enemy turns toward the shooter, raycasts with generous range (no FOV cone),
-- and either engages or investigates the impact point.
function Perception:ReactToNearbyImpact(shotOrigin, suspectedTarget, impactPoint)
	if not shotOrigin then return end
	if not self.Enemy or not self.Enemy.Model or self.Enemy.IsDead then return end
	if not isInActiveWorld(self.Enemy.Model) then return end

	local model = self.Enemy.Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Turn toward the shooter
	facePosition(model, shotOrigin)

	-- After turning, check if the shooter is visible (generous range, line of sight only — no FOV cone)
	if isValidLivingTarget(suspectedTarget) and self:CanSeeTargetFromShotReaction(suspectedTarget) then
		self.VisibleTarget = suspectedTarget
		self.LastKnownPosition = suspectedTarget.HumanoidRootPart.Position
		self.InvestigationPoint = nil
		self.WasVisible = true
		setAwarenessIndicator(model, "!", Color3.fromRGB(255, 75, 75), 1.75)
		EventsService:FireEvent("PlayerSpotted", {
			Position = self.LastKnownPosition,
			Target = suspectedTarget,
			Spotter = model,
		})
		if self.Enemy and self.Enemy.AI then
			self.Enemy.AI:Evaluate()
		end
		return
	end

	-- A nearby impact tells the enemy the shot came from the shooter direction, not
	-- just the surface that was hit. Go weapon-up and investigate the shot origin so
	-- repeated near misses make the enemy keep turning/checking toward the player.
	self.InvestigationPoint = shotOrigin
	self.LastKnownPosition = shotOrigin
	if self.Enemy and self.Enemy.Combat then
		self.Enemy.Combat:BeginAlertPosture(shotOrigin)
	end
	setAwarenessIndicator(model, "?", Color3.fromRGB(255, 230, 80), 2.25)
	if self.Enemy and self.Enemy.AI then
		self.Enemy.AI:Evaluate()
	end
end

-- Get the enemy's HumanoidRootPart for vision calculations
function Perception:GetOriginPart()
	local model = self.Enemy and self.Enemy.Model
	if not model then return nil end
	return model:FindFirstChild("HumanoidRootPart")
end

-- Get the enemy's current position
function Perception:GetPosition()
	local part = self:GetOriginPart()
	if part then return part.Position end
	if self.Enemy and self.Enemy.Model then
		return self.Enemy.Model:GetPivot().Position
	end
	return nil
end

-- Check if we still have line of sight to the last visible target, even though
-- they've left normal vision range/FOV. This enables pursuit behaviour: the enemy
-- keeps chasing as long as LOS is clear, without requiring the player to be in the
-- vision cone.
function Perception:CheckPursuit()
	if self:IsSmokeBlinded() then return nil end
	local lastTarget = self.LastVisibleTarget
	if not lastTarget or not lastTarget.Parent or isCharacterCamouflaged(lastTarget) then return nil end

	-- Validate target is still alive
	local humanoid = lastTarget:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= PLAYER_DEATH_HEALTH then return nil end

	local hrp = lastTarget:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local originPart = self:GetOriginPart()
	if not originPart then return nil end

	local targetPos = hrp.Position

	-- Extended pursuit has no hard range limit by default. It is governed by
	-- raycast line-of-sight only, so enemies continue running after a fleeing
	-- player as long as they can clearly see them.
	local maxPursuitRange = self.PursuitRange or math.huge
	if maxPursuitRange ~= math.huge then
		local dist = (targetPos - originPart.Position).Magnitude
		if dist > maxPursuitRange then return nil end
	end

	if not self:HasLineOfSight(originPart, lastTarget, targetPos) then return nil end

	return lastTarget
end

function Perception:GetNearestLineOfSightTarget()
	local nearest = nil
	local nearestDist = math.huge
	local myPos = self:GetPosition()
	local originPart = self:GetOriginPart()
	if not myPos or not originPart then return nil end

	local characters = getPlayerCharacters()
	for i = 1, #characters do
		local entry = characters[i]
		local character = entry.Character
		if character and character.Parent and self:CanSeeTargetByLineOfSightOnly(character) then
			local dist = (entry.Position - myPos).Magnitude
			if dist < nearestDist then
				nearestDist = dist
				nearest = character
			end
		end
	end
	return nearest
end

-- Main update — called each AI tick (20 Hz) before state evaluation
function Perception:Update(DeltaTime)
	-- Skip if enemy is dead
	local model = self.Enemy and self.Enemy.Model
	if not model then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		self.VisibleTarget = nil
		self.PursuitTarget = nil
		self.WasVisible = false
		return
	end

	-- Track the last normally-visible target for pursuit checks
	if self.VisibleTarget and self.VisibleTarget.Parent then
		self.LastVisibleTarget = self.VisibleTarget
		self.LastVisibleTime = os.clock()
	end

	local nearest = self:GetNearestVisibleTarget()

	if nearest then
		-- Player is visible via normal vision (within range + FOV + LOS)
		self.VisibleTarget = nearest
		self.LastVisibleTarget = nearest
		self.LastVisibleTime = os.clock()
		self.PursuitTarget = nil
		self.InvestigationPoint = nil

		-- Update last known position
		local hrp = nearest:FindFirstChild("HumanoidRootPart")
		if hrp then
			self.LastKnownPosition = hrp.Position
		end

		-- Fire PlayerSpotted event on new detection (transition from not-visible to visible)
		if not self.WasVisible and hrp then
			self.WasVisible = true
			EventsService:FireEvent("PlayerSpotted", {
				Position = hrp.Position,
				Target = nearest,
				Spotter = model,
			})
		end
	else
		-- Normal vision failed. First, use pure LOS-only detection with no distance
		-- limit. This catches the case where the player is running away in clear
		-- sight but outside the enemy's normal detection/combat range.
		local pursuitTarget = self:CheckPursuit() or self:GetNearestLineOfSightTarget()
		if pursuitTarget then
			-- Still have clear LOS but player is outside normal vision range/FOV.
			-- Don't set VisibleTarget — that is reserved for Combat. Instead, set
			-- PursuitTarget so the Pursuing state takes over and runs directly
			-- toward the player without pathfinding.
			self.VisibleTarget = nil
			self.PursuitTarget = pursuitTarget
			self.LastVisibleTarget = pursuitTarget
			self.LastVisibleTime = os.clock()
			self.InvestigationPoint = nil

			-- Keep updating last known position as the player moves
			local pursuitHrp = pursuitTarget:FindFirstChild("HumanoidRootPart")
			if pursuitHrp then
				self.LastKnownPosition = pursuitHrp.Position
			end
			-- Keep WasVisible true so we don't re-fire PlayerSpotted every tick
		else
			-- Lost LOS entirely — clear target, let LastKnownPosition drive Search state
			self.VisibleTarget = nil
			self.PursuitTarget = nil
			self.WasVisible = false
		end
	end
end

return Perception