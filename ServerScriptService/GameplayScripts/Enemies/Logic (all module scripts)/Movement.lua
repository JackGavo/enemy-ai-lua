local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local Movement = {}
Movement.__index = Movement

-- Configuration
local WAYPOINT_REACH_THRESHOLD = 4   -- studs to consider a waypoint reached
local STUCK_TIMEOUT = 3               -- seconds without progress before recovery
local STUCK_MIN_DISTANCE = 0.5       -- studs of movement per tick to not be considered stuck
local MAX_STUCK_RECOVERIES = 3       -- after this, report movement failure to the AI owner
local DESTINATION_REISSUE_THRESHOLD = 4 -- studs; avoid recomputing paths for tiny destination changes
local PATH_RECOMPUTE_COOLDOWN = 1.25   -- seconds; prevents combat movement from flooding PathfindingService
local GROUND_RAY_HEIGHT = 6
local GROUND_RAY_DEPTH = 14
local WALL_CHECK_HEIGHT = 1.0 -- measured from grounded feet position, not HumanoidRootPart/head height

local GroundRayParams = RaycastParams.new()
GroundRayParams.FilterType = Enum.RaycastFilterType.Exclude

local WallRayParams = RaycastParams.new()
WallRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function flatVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function safeSetStateEnabled(humanoid, state, enabled)
	pcall(function()
		humanoid:SetStateEnabled(state, enabled)
	end)
end

local function sortByNumericName(a, b)
	local numA = tonumber(string.match(a.Name, "%d+")) or math.huge
	local numB = tonumber(string.match(b.Name, "%d+")) or math.huge
	if numA == numB then
		return a.Name < b.Name
	end
	return numA < numB
end

local function getSegmentIndexFromName(name)
	return tonumber(string.match(name or "", "%d+")) or math.huge
end

function Movement.new(Enemy)
	local self = setmetatable({}, Movement)

	self.Enemy = Enemy
	self.Moving = false
	self.Destination = nil

	-- Mode: "Idle" | "Patrol" | "MoveTo" | "Pursuit"
	self.Mode = "Idle"
	self.IsPaused = false

	-- Patrol state
	self.Path = nil                  -- the path folder
	self.Waypoints = {}              -- array of waypoint Parts (sorted)
	self.WaypointIndex = 1           -- current target waypoint
	self.PathDirection = 1           -- 1 = forward, -1 = reverse
	self.WaitTimer = 0               -- countdown for EndOfPathTimeWait
	self.IsWaiting = false           -- currently waiting at end of path
	self.ReverseAtEnd = false        -- from ReverseAtEndOfPath value
	self.EndWaitTime = 0             -- from EndOfPathTimeWait value

	-- Cached patrol path support
	self.UsingPrecomputedPath = false
	self.PrecomputedSegments = {}
	self.PrecomputedSegmentIndex = 1
	self.PrecomputedWaypointIndex = 1

	-- MoveTo state
	self.MoveToTarget = nil          -- target Vector3
	self.PathfindingWaypoints = {}   -- waypoints from PathfindingService
	self.PathfindingIndex = 1        -- current index in pathfinding waypoints
	self.MoveToReachThreshold = nil  -- optional override for tight destinations like dead bodies

	-- MoveTo throttling / path reuse
	self.LastPathComputeTime = 0
	self.LastComputedTarget = nil

	-- Stuck detection
	self.LastPosition = nil
	self.StuckTimer = 0

	-- Failure / recovery state
	self.Failed = false
	self.FailureReason = nil
	self.StuckRecoveries = 0

	local humanoid = self:GetHumanoid()
	local config = Enemy.Config or {}
	self.WalkSpeed = config.MovementSpeed or 12
	self.RunSpeed = (config.MovementSpeed or 12) * 1.8
	self.IsRunning = false
	if humanoid then
		humanoid.WalkSpeed = self.WalkSpeed
		self:ConfigureHumanoid(humanoid)
	end

	return self
end

----------------------------------------------------------------------------
-- Run speed control
----------------------------------------------------------------------------

function Movement:SetRunning(active)
	self.IsRunning = active == true
	local humanoid = self:GetHumanoid()
	if humanoid then
		humanoid.WalkSpeed = self.IsRunning and self.RunSpeed or self.WalkSpeed
	end
end

function Movement:GetCurrentSpeed()
	return self.IsRunning and self.RunSpeed or self.WalkSpeed
end

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

function Movement:GetHumanoid()
	local model = self.Enemy and self.Enemy.Model
	if not model then return nil end
	return model:FindFirstChildOfClass("Humanoid")
end


function Movement:GetRootPart()
	local model = self.Enemy and self.Enemy.Model
	if not model then return nil end
	return model:FindFirstChild("HumanoidRootPart")
end

function Movement:ConfigureModelPhysics()
	local model = self.Enemy and self.Enemy.Model
	if not model then return end

	for _, obj in model:GetDescendants() do
		if obj:IsA("BasePart") then
			pcall(function()
				obj:SetNetworkOwner(nil)
			end)

			-- Marine-style NPCs should be server-driven and should not receive physics
			-- kicks from accessories/hit effects. Keep cosmetic/accessory pieces light
			-- and non-colliding so bullet impacts cannot launch the rig upward.
			if obj.Name ~= "HumanoidRootPart" then
				obj.Massless = true
			end
			if obj.Parent and obj.Parent:IsA("Accessory") then
				obj.CanCollide = false
				obj.CanTouch = false
				obj.Massless = true
			end
		end
	end
end

function Movement:ConfigureHumanoid(humanoid)
	if not humanoid then return end
	humanoid.WalkSpeed = self.IsRunning and (self.RunSpeed or self.WalkSpeed) or (self.WalkSpeed or humanoid.WalkSpeed)
	humanoid.PlatformStand = false
	humanoid.Sit = false

	-- Marine-style humanoid lockdown: prevent damage/path updates from kicking NPCs
	-- into physics/ragdoll/flying states that launch them upward.
	safeSetStateEnabled(humanoid, Enum.HumanoidStateType.Flying, false)
	safeSetStateEnabled(humanoid, Enum.HumanoidStateType.GettingUp, false)
	safeSetStateEnabled(humanoid, Enum.HumanoidStateType.Physics, false)
	safeSetStateEnabled(humanoid, Enum.HumanoidStateType.Ragdoll, false)
	safeSetStateEnabled(humanoid, Enum.HumanoidStateType.FallingDown, false)
	safeSetStateEnabled(humanoid, Enum.HumanoidStateType.RunningNoPhysics, false)
	safeSetStateEnabled(humanoid, Enum.HumanoidStateType.StrafingNoPhysics, false)
	safeSetStateEnabled(humanoid, Enum.HumanoidStateType.Swimming, false)
	safeSetStateEnabled(humanoid, Enum.HumanoidStateType.Jumping, false)

	pcall(function()
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 0
	end)
	humanoid.JumpHeight = 0
	humanoid.Jump = false
	self:ConfigureModelPhysics()
end

function Movement:GetPosition()
	local root = self:GetRootPart()
	if root then return root.Position end
	return nil
end

function Movement:GetIgnoreList(extraIgnore)
	local ignore = {}
	local model = self.Enemy and self.Enemy.Model
	if model then table.insert(ignore, model) end
	if extraIgnore then table.insert(ignore, extraIgnore) end
	return ignore
end

function Movement:ProjectToGround(position, extraIgnore)
	if not position then return nil end
	GroundRayParams.FilterDescendantsInstances = self:GetIgnoreList(extraIgnore)
	local result = Workspace:Raycast(
		position + Vector3.new(0, GROUND_RAY_HEIGHT, 0),
		Vector3.new(0, -GROUND_RAY_DEPTH, 0),
		GroundRayParams
	)
	if result then
		return Vector3.new(position.X, result.Position.Y, position.Z)
	end
	return nil
end

function Movement:IsGroundedMoveClear(origin, destination, extraIgnore)
	if not origin or not destination then return false end

	local groundedOrigin = self:ProjectToGround(origin, extraIgnore)
	local groundedDestination = self:ProjectToGround(destination, extraIgnore)
	if not groundedOrigin or not groundedDestination then return false end

	local flatOffset = flatVector(groundedDestination - groundedOrigin)
	if flatOffset.Magnitude <= 0.2 then return true end

	-- This is a movement clearance check, not vision. Cast from just above the
	-- enemy's feet so low walls/cover block direct movement and force pathfinding.
	WallRayParams.FilterDescendantsInstances = self:GetIgnoreList(extraIgnore)
	local wallHit = Workspace:Raycast(groundedOrigin + Vector3.new(0, WALL_CHECK_HEIGHT, 0), flatOffset, WallRayParams)
	if wallHit and wallHit.Instance and wallHit.Instance.CanCollide then
		return false
	end

	return math.abs(groundedDestination.Y - groundedOrigin.Y) <= 7
end

function Movement:IssueGroundedMoveTo(position, extraIgnore)
	local humanoid = self:GetHumanoid()
	local root = self:GetRootPart()
	if not humanoid or not root or not position then return false end
	self:ConfigureHumanoid(humanoid)

	local groundedOrigin = self:ProjectToGround(root.Position, extraIgnore)
	if not groundedOrigin then return false end
	local grounded = self:ProjectToGround(position, extraIgnore)
	if not grounded then return false end
	if not self:IsGroundedMoveClear(groundedOrigin, grounded, extraIgnore) then
		-- Marine-style fallback: move as far as we can along the flat direction rather
		-- than jumping/pathing upward through bad geometry.
		local offset = flatVector(grounded - groundedOrigin)
		if offset.Magnitude > 0.2 then
			local step = groundedOrigin + offset.Unit * math.min(offset.Magnitude, 8)
			grounded = self:ProjectToGround(step, extraIgnore)
		end
	end
	if not grounded then return false end

	self.Destination = grounded
	humanoid.Jump = false
	humanoid:MoveTo(grounded)
	return true
end

-- Extract waypoint parts from a path folder, sorted by numeric suffix
function Movement:ExtractWaypoints(pathFolder)
	local waypoints = {}
	for _, child in pathFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(waypoints, child)
		end
	end
	table.sort(waypoints, sortByNumericName)
	return waypoints
end

function Movement:ExtractPrecomputedSegments(pathFolder)
	local segmentsFolder = pathFolder and pathFolder:FindFirstChild("PrecomputedPathSegments")
	if not segmentsFolder then return {} end

	local segmentFolders = {}
	for _, segmentFolder in ipairs(segmentsFolder:GetChildren()) do
		if segmentFolder:IsA("Folder") then
			table.insert(segmentFolders, segmentFolder)
		end
	end
	table.sort(segmentFolders, function(a, b)
		return getSegmentIndexFromName(a.Name) < getSegmentIndexFromName(b.Name)
	end)

	local segments = {}
	for i = 1, #segmentFolders do
		local segmentFolder = segmentFolders[i]
		local values = {}
		for _, child in ipairs(segmentFolder:GetChildren()) do
			if child:IsA("Vector3Value") then
				table.insert(values, child)
			end
		end
		table.sort(values, sortByNumericName)

		local waypoints = {}
		for j = 1, #values do
			local value = values[j]
			table.insert(waypoints, {
				Position = value.Value,
				Jump = value:GetAttribute("Jump") == true,
			})
		end
		if #waypoints > 0 then
			table.insert(segments, waypoints)
		end
	end

	return segments
end

-- Read path configuration values (ReverseAtEndOfPath, EndOfPathTimeWait)
function Movement:ReadPathConfig(pathFolder)
	local reverseVal = pathFolder:FindFirstChild("ReverseAtEndOfPath")
	self.ReverseAtEnd = reverseVal and reverseVal:IsA("BoolValue") and reverseVal.Value or false

	local waitVal = pathFolder:FindFirstChild("EndOfPathTimeWait")
	self.EndWaitTime = waitVal and waitVal:IsA("NumberValue") and waitVal.Value or 0
end

-- Find the index of the nearest waypoint to the enemy's current position
function Movement:FindNearestWaypoint()
	local myPos = self:GetPosition()
	if not myPos then return 1 end

	local nearestIndex = 1
	local nearestDist = math.huge

	for i, wp in ipairs(self.Waypoints) do
		if wp.Parent then
			local dist = (wp.Position - myPos).Magnitude
			if dist < nearestDist then
				nearestDist = dist
				nearestIndex = i
			end
		end
	end

	return nearestIndex
end

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------

function Movement:MarkFailed(reason)
	self.Failed = true
	self.FailureReason = reason or "Unknown"
	self.Moving = false
	self.Destination = nil
	self.PathfindingWaypoints = {}
	self.PathfindingIndex = 1
end

function Movement:ClearFailure()
	self.Failed = false
	self.FailureReason = nil
	self.StuckRecoveries = 0
end

function Movement:HasFailed()
	return self.Failed == true
end

function Movement:GetFailureReason()
	return self.FailureReason
end

-- Start following a path folder's waypoints
function Movement:FollowPath(pathFolder)
	local humanoid = self:GetHumanoid()
	if humanoid then
		humanoid.WalkSpeed = self:GetCurrentSpeed()
	end

	if not pathFolder then
		self:MarkFailed("MissingPath")
		return
	end

	self:ClearFailure()
	self.Path = pathFolder
	self.Waypoints = self:ExtractWaypoints(pathFolder)
	self.PrecomputedSegments = self:ExtractPrecomputedSegments(pathFolder)
	self.UsingPrecomputedPath = #self.PrecomputedSegments > 0
	self.PrecomputedSegmentIndex = 1
	self.PrecomputedWaypointIndex = 1
	self:ReadPathConfig(pathFolder)

	if #self.Waypoints == 0 then
		self.Mode = "Idle"
		self.Moving = false
		self:MarkFailed("PathHasNoWaypoints")
		return
	end

	-- Start from the nearest waypoint to current position
	self.WaypointIndex = self:FindNearestWaypoint()
	self.PathDirection = 1
	self.IsWaiting = false
	self.WaitTimer = 0

	self.Mode = "Patrol"
	self.Moving = true

	if self.UsingPrecomputedPath then
		self:IssuePrecomputedPatrolMoveTo()
	else
		self:IssuePatrolMoveTo()
	end
end

function Movement:CanReuseCurrentPath(position)
	if self.Mode ~= "MoveTo" or #self.PathfindingWaypoints == 0 then
		return false
	end
	if not self.MoveToTarget then
		return false
	end
	return (self.MoveToTarget - position).Magnitude <= DESTINATION_REISSUE_THRESHOLD
end

function Movement:MoveDirect(position)
	local humanoid = self:GetHumanoid()
	if not humanoid or not position then return end
	self:ClearFailure()
	self.Mode = "MoveTo"
	self.MoveToTarget = position
	self.Moving = true
	self.Destination = position
	self.PathfindingWaypoints = {}
	self.PathfindingIndex = 1
	if not self:IssueGroundedMoveTo(position) then
		self:MarkFailed("DirectMoveFailed")
	end
end

-- Move directly toward a position when the route is clear; otherwise fall back to
-- pathfinding. Used by pursuit/combat chase so enemies do not freeze behind cover,
-- railings, corners, or uneven ground while the player is visible but out of range.
function Movement:MoveToDirect(position)
	local humanoid = self:GetHumanoid()
	if not humanoid or not position then return end
	self:ClearFailure()

	local root = self:GetRootPart()
	if root then
		local groundedOrigin = self:ProjectToGround(root.Position)
		local groundedTarget = self:ProjectToGround(position)
		if groundedOrigin and groundedTarget and self:IsGroundedMoveClear(groundedOrigin, groundedTarget) then
			self.Mode = "Pursuit"
			self.MoveToTarget = groundedTarget
			self.Moving = true
			self.Destination = groundedTarget
			self.PathfindingWaypoints = {}
			self.PathfindingIndex = 1
			if not self:IssueGroundedMoveTo(groundedTarget) then
				humanoid:MoveTo(groundedTarget)
			end
			return
		end
	end

	-- Blocked direct chase: use the pathfinder, but respect the existing recompute
	-- cooldown so a running target cannot flood PathfindingService every AI tick.
	local now = os.clock()
	if now - (self.LastPathComputeTime or 0) < PATH_RECOMPUTE_COOLDOWN then
		self.MoveToTarget = position
		self.Destination = position
		if #self.PathfindingWaypoints > 0 then
			-- Pathfinding has active waypoints: let UpdateMoveTo progress through them.
			self.Mode = "MoveTo"
			self.Moving = true
		else
			-- No pathfinding waypoints (NoPath or not yet computed): issue a raw
			-- MoveTo toward the target so the enemy keeps chasing even when
			-- pathfinding can't find a route (e.g., elevated target, higher ground).
			self.Mode = "Pursuit"
			self.Moving = true
			humanoid:MoveTo(position)
		end
		return
	end

	self:MoveTo(position)
end

-- Move to a specific Vector3 position using PathfindingService
function Movement:MoveTo(position)
	local humanoid = self:GetHumanoid()
	if humanoid then
		humanoid.WalkSpeed = self:GetCurrentSpeed()
	end

	if not position then
		self:MarkFailed("MissingDestination")
		return
	end

	if self:CanReuseCurrentPath(position) then
		self.MoveToTarget = position
		self.Destination = position
		return
	end

	local now = os.clock()
	if self.Mode == "MoveTo" and #self.PathfindingWaypoints > 0 and self.LastComputedTarget and now - self.LastPathComputeTime < PATH_RECOMPUTE_COOLDOWN then
		if (self.LastComputedTarget - position).Magnitude <= DESTINATION_REISSUE_THRESHOLD then
			self.MoveToTarget = position
			self.Destination = position
			return
		end
	end

	self:ClearFailure()
	self.Mode = "MoveTo"
	self.MoveToTarget = position
	self.Moving = true
	self.Destination = position

	-- Performance optimization: raycast to check if the path to the target is clear.
	-- If clear, move directly without the overhead of PathfindingService.
	-- If blocked, fall back to PathfindingService to navigate around obstacles.
	local root = self:GetRootPart()
	if root then
		local groundedOrigin = self:ProjectToGround(root.Position)
		local groundedTarget = self:ProjectToGround(position)
		if groundedOrigin and groundedTarget and self:IsGroundedMoveClear(groundedOrigin, groundedTarget) then
			self.PathfindingWaypoints = { { Position = groundedTarget } }
			self.PathfindingIndex = 1
			self.LastPathComputeTime = os.clock()
			self.LastComputedTarget = position
			if not self:IssueGroundedMoveTo(groundedTarget) then
				self:MarkFailed("DirectMoveFailed")
			end
			return
		end
	end

	self:ComputePathfinding(position)
end

-- Move to a specific part's position
function Movement:MoveToPart(part)
	if not part or not part.Parent then return end
	self:MoveTo(part.Position)
end

-- Stop all movement and reset to idle
function Movement:Stop()
	local humanoid = self:GetHumanoid()
	local root = self:GetRootPart()
	if humanoid and root then
		self:ConfigureHumanoid(humanoid)
		self:IssueGroundedMoveTo(root.Position)
	end

	self.Mode = "Idle"
	self.Moving = false
	self.Destination = nil
	self.IsWaiting = false
	self.WaitTimer = 0
	self.PathfindingWaypoints = {}
	self.PathfindingIndex = 1
	self.StuckTimer = 0
	self.StuckRecoveries = 0
end

-- Pause movement (keep state, stop walking)
function Movement:Pause()
	self.IsPaused = true
	local humanoid = self:GetHumanoid()
	local root = self:GetRootPart()
	if humanoid and root then
		self:ConfigureHumanoid(humanoid)
		self:IssueGroundedMoveTo(root.Position)
	end
end

-- Resume movement from where we left off
function Movement:Resume()
	if not self.IsPaused then return end
	self.IsPaused = false

	if self.Mode == "Patrol" then
		if self.UsingPrecomputedPath then
			self:IssuePrecomputedPatrolMoveTo()
		else
			self:IssuePatrolMoveTo()
		end
	elseif self.Mode == "MoveTo" and #self.PathfindingWaypoints > 0 then
		self:IssuePathfindingMoveTo()
	elseif self.Mode == "Pursuit" and self.MoveToTarget then
		self:MoveToDirect(self.MoveToTarget)
	end
end

function Movement:HasReachedDestination()
	local myPos = self:GetPosition()
	if not myPos or not self.Destination then return true end
	return flatVector(myPos - self.Destination).Magnitude <= (self.MoveToReachThreshold or WAYPOINT_REACH_THRESHOLD)
end

function Movement:IsMoving()
	return self.Moving and not self.IsPaused
end

function Movement:GetCurrentDestination()
	return self.Destination
end

----------------------------------------------------------------------------
-- Internal: issue Humanoid:MoveTo calls
----------------------------------------------------------------------------

function Movement:GetCurrentPrecomputedWaypoint()
	local segment = self.PrecomputedSegments[self.PrecomputedSegmentIndex]
	if not segment then return nil end
	return segment[self.PrecomputedWaypointIndex]
end

function Movement:IssuePrecomputedPatrolMoveTo()
	local humanoid = self:GetHumanoid()
	local waypoint = self:GetCurrentPrecomputedWaypoint()
	if not humanoid or not waypoint then
		self:MarkFailed("PrecomputedWaypointUnavailable")
		return
	end
	self.Destination = waypoint.Position
	-- Do not auto-jump on cached patrol segments. A bad/off-mesh generated path
	-- should not make NPCs hop repeatedly; keep patrol grounded and readable.
	if not self:IssueGroundedMoveTo(waypoint.Position) then
		self:MarkFailed("PrecomputedMoveFailed")
	end
end

function Movement:AdvancePrecomputedWaypoint()
	local segment = self.PrecomputedSegments[self.PrecomputedSegmentIndex]
	if not segment then
		return true
	end

	self.PrecomputedWaypointIndex += 1
	if self.PrecomputedWaypointIndex <= #segment then
		return false
	end

	self.PrecomputedWaypointIndex = 1
	self.PrecomputedSegmentIndex += 1
	if self.PrecomputedSegmentIndex > #self.PrecomputedSegments then
		if self.ReverseAtEnd then
			self.UsingPrecomputedPath = false
			return true
		end
		self.PrecomputedSegmentIndex = 1
		if self.EndWaitTime > 0 then
			self.IsWaiting = true
			self.WaitTimer = self.EndWaitTime
			return false
		end
	end
	return false
end

-- Issue MoveTo for the current patrol waypoint
function Movement:IssuePatrolMoveTo()
	local humanoid = self:GetHumanoid()
	local wp = self.Waypoints[self.WaypointIndex]
	if not humanoid or not wp or not wp.Parent then
		self:MarkFailed("PatrolWaypointUnavailable")
		return
	end

	self.Destination = wp.Position
	if not self:IssueGroundedMoveTo(wp.Position) then
		self:MarkFailed("PatrolMoveFailed")
	end
end

-- Issue MoveTo for the current pathfinding waypoint
function Movement:IssuePathfindingMoveTo()
	local humanoid = self:GetHumanoid()
	local wp = self.PathfindingWaypoints[self.PathfindingIndex]
	if not humanoid or not wp then
		self:MarkFailed("PathWaypointUnavailable")
		return
	end

	self.Destination = wp.Position

	-- Do not auto-jump on dynamic AI paths. Getting shot, investigating, or entering
	-- combat should never make enemies randomly hop.

	if not self:IssueGroundedMoveTo(wp.Position) then
		self:MarkFailed("PathMoveFailed")
	end
end

-- Compute a pathfinding path to the target position
function Movement:ComputePathfinding(targetPosition)
	local root = self:GetRootPart()
	if not root then
		self:MarkFailed("MissingRootPart")
		return
	end

	self.LastPathComputeTime = os.clock()
	self.LastComputedTarget = targetPosition

	local groundedTarget = self:ProjectToGround(targetPosition)
	if not groundedTarget then
		self:MarkFailed("NoGroundAtDestination")
		return
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = false,
		AgentCanClimb = false,
	})

	local success = pcall(function()
		path:ComputeAsync(root.Position, groundedTarget)
	end)

	if not success or path.Status == Enum.PathStatus.NoPath then
		-- Fallback: direct MoveTo, but remember the path failure. If the enemy gets
		-- stuck after this, the owner can abandon the unreachable point cleanly.
		self.FailureReason = "NoPath"
		local humanoid = self:GetHumanoid()
		if humanoid then
			self:ConfigureHumanoid(humanoid)
			if self:IssueGroundedMoveTo(groundedTarget) then
				-- Track the fallback position as a single waypoint so UpdateMoveTo
				-- does not immediately declare the destination reached when
				-- PathfindingWaypoints is empty. Without this, the enemy stops
				-- on the next tick because HasReachedPathfindingWaypoint() sees
				-- no waypoints and returns true.
				self.PathfindingWaypoints = { { Position = self.Destination } }
				self.PathfindingIndex = 1
			else
				self.PathfindingWaypoints = {}
				self.PathfindingIndex = 1
			end
		end
		return
	end

	self.PathfindingWaypoints = {}
	local rawWaypoints = path:GetWaypoints()
	for i = 1, #rawWaypoints do
		local grounded = self:ProjectToGround(rawWaypoints[i].Position)
		if grounded then
			table.insert(self.PathfindingWaypoints, { Position = grounded })
		end
	end
	self.PathfindingIndex = 1

	self:IssuePathfindingMoveTo()
end

----------------------------------------------------------------------------
-- Internal: waypoint progression
----------------------------------------------------------------------------

-- Check if the enemy has reached the current patrol waypoint
function Movement:HasReachedPatrolWaypoint()
	local myPos = self:GetPosition()
	if not myPos then return true end
	local wp = self.Waypoints[self.WaypointIndex]
	if not wp or not wp.Parent then return true end
	return flatVector(myPos - wp.Position).Magnitude <= WAYPOINT_REACH_THRESHOLD
end

-- Check if the enemy has reached the current pathfinding waypoint
function Movement:HasReachedPathfindingWaypoint()
	local myPos = self:GetPosition()
	if not myPos then return true end
	local wp = self.PathfindingWaypoints[self.PathfindingIndex]
	if not wp then return true end
	return flatVector(myPos - wp.Position).Magnitude <= (self.MoveToReachThreshold or WAYPOINT_REACH_THRESHOLD)
end

-- Advance to the next patrol waypoint, handling reverse and wait logic
function Movement:AdvancePatrolWaypoint()
	local count = #self.Waypoints

	if self.PathDirection == 1 then
		-- Moving forward
		if self.WaypointIndex < count then
			self.WaypointIndex += 1
		else
			-- Reached end of path
			if self.ReverseAtEnd then
				self.PathDirection = -1
				if count > 1 then
					self.WaypointIndex = count - 1
				end
			else
				-- Wait then restart from beginning
				if self.EndWaitTime > 0 then
					self.IsWaiting = true
					self.WaitTimer = self.EndWaitTime
				else
					self.WaypointIndex = 1
				end
			end
		end
	else
		-- Moving in reverse
		if self.WaypointIndex > 1 then
			self.WaypointIndex -= 1
		else
			-- Reached start of path (in reverse)
			if self.EndWaitTime > 0 then
				self.IsWaiting = true
				self.WaitTimer = self.EndWaitTime
			else
				self.PathDirection = 1
				if count > 1 then
					self.WaypointIndex = 2
				end
			end
		end
	end
end

-- Advance to the next pathfinding waypoint. Returns true if final destination reached.
function Movement:AdvancePathfindingWaypoint()
	self.PathfindingIndex += 1

	if self.PathfindingIndex > #self.PathfindingWaypoints then
		-- Reached the final destination
		self.Mode = "Idle"
		self.Moving = false
		self.Destination = nil
		self.PathfindingWaypoints = {}
		self.PathfindingIndex = 1
		return true
	end

	return false
end

----------------------------------------------------------------------------
-- Internal: stuck detection
----------------------------------------------------------------------------

function Movement:UpdateStuckDetection(DeltaTime)
	local myPos = self:GetPosition()
	if not myPos then return end

	if self.LastPosition then
		local moved = flatVector(myPos - self.LastPosition).Magnitude
		if moved < STUCK_MIN_DISTANCE then
			self.StuckTimer += DeltaTime
		else
			self.StuckTimer = 0
			self.LastPosition = myPos
		end
	else
		self.LastPosition = myPos
	end
end

function Movement:IsStuck()
	return self.StuckTimer >= STUCK_TIMEOUT
end

----------------------------------------------------------------------------
-- Main update — called each AI tick (20 Hz)
----------------------------------------------------------------------------

function Movement:Update(DeltaTime)
	if self.IsPaused or self.Mode == "Idle" then return end

	local humanoid = self:GetHumanoid()
	if not humanoid or humanoid.Health <= 0 then return end
	self:ConfigureHumanoid(humanoid)

	local root = self:GetRootPart()
	if root and root.AssemblyLinearVelocity.Y > 2 then
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end

	self:UpdateStuckDetection(DeltaTime)

	if self.Mode == "Patrol" then
		self:UpdatePatrol(DeltaTime)
	elseif self.Mode == "MoveTo" then
		self:UpdateMoveTo(DeltaTime)
	elseif self.Mode == "Pursuit" then
		self:UpdatePursuit(DeltaTime)
	end
end

-- Update patrol movement
function Movement:UpdatePatrol(DeltaTime)
	-- Handle waiting at end of path
	if self.IsWaiting then
		self.WaitTimer -= DeltaTime
		if self.WaitTimer <= 0 then
			self.IsWaiting = false
			self.WaitTimer = 0
			-- Restart from the appropriate end
			if self.UsingPrecomputedPath then
				self.PrecomputedSegmentIndex = 1
				self.PrecomputedWaypointIndex = 1
				self:IssuePrecomputedPatrolMoveTo()
			elseif self.PathDirection == 1 then
				self.WaypointIndex = 1
				self:IssuePatrolMoveTo()
			else
				self.PathDirection = 1
				self.WaypointIndex = #self.Waypoints > 1 and 2 or 1
				self:IssuePatrolMoveTo()
			end
		end
		return
	end

	if self.UsingPrecomputedPath then
		if self:HasReachedDestination() then
			local reachedCycleEnd = self:AdvancePrecomputedWaypoint()
			if reachedCycleEnd and not self.UsingPrecomputedPath then
				-- Reverse patrol paths fall back to the raw node list because cached
				-- segments are generated forward at map load.
				self.WaypointIndex = self:FindNearestWaypoint()
				self:IssuePatrolMoveTo()
			elseif not self.IsWaiting then
				self:IssuePrecomputedPatrolMoveTo()
			end
			return
		end

		if self:IsStuck() then
			self.StuckTimer = 0
			self.StuckRecoveries += 1
			if self.StuckRecoveries > MAX_STUCK_RECOVERIES then
				self:MarkFailed("StuckOnPrecomputedPatrol")
				return
			end
			self:IssuePrecomputedPatrolMoveTo()
		end
		return
	end

	-- Check if we've reached the current waypoint
	if self:HasReachedPatrolWaypoint() then
		self:AdvancePatrolWaypoint()
		if not self.IsWaiting then
			self:IssuePatrolMoveTo()
		end
		return
	end

	-- Stuck recovery — re-issue MoveTo, then fail gracefully if repeated recovery does not help.
	if self:IsStuck() then
		self.StuckTimer = 0
		self.StuckRecoveries += 1
		if self.StuckRecoveries > MAX_STUCK_RECOVERIES then
			self:MarkFailed("StuckOnPatrol")
			return
		end
		self:IssuePatrolMoveTo()
	end
end

-- Update MoveTo movement
function Movement:UpdateMoveTo(DeltaTime)
	-- Check if we've reached the current pathfinding waypoint
	if self:HasReachedPathfindingWaypoint() then
		local reachedFinal = self:AdvancePathfindingWaypoint()
		if reachedFinal then return end
		self:IssuePathfindingMoveTo()
		return
	end

	-- Stuck recovery — recompute path, then fail gracefully if repeated recovery does not help.
	if self:IsStuck() then
		self.StuckTimer = 0
		self.StuckRecoveries += 1
		if self.StuckRecoveries > MAX_STUCK_RECOVERIES then
			self:MarkFailed("StuckMovingToDestination")
			return
		end
		if self.MoveToTarget then
			self:ComputePathfinding(self.MoveToTarget)
		else
			self:MarkFailed("MissingMoveToTarget")
		end
	end
end

-- Update direct pursuit movement. The owner usually re-issues MoveToDirect toward
-- the live target, but this catches edge cases where a chase command hits geometry
-- and then stops progressing before the next state change.
function Movement:UpdatePursuit(DeltaTime)
	if self:HasReachedDestination() then
		-- A live pursuit target is often re-issued on the next combat/pursuit tick.
		-- Keep the movement state active so the enemy does not briefly look idle when
		-- they reach an old target position while the player is still running.
		self.StuckTimer = 0
		return
	end

	if self:IsStuck() then
		self.StuckTimer = 0
		self.StuckRecoveries += 1
		if self.StuckRecoveries > MAX_STUCK_RECOVERIES then
			self:MarkFailed("StuckDuringPursuit")
			return
		end
		if self.MoveToTarget then
			self:ComputePathfinding(self.MoveToTarget)
		else
			self:MarkFailed("MissingPursuitTarget")
		end
	end
end

----------------------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------------------

function Movement:Destroy()
	self:Stop()
	self.LastPathComputeTime = 0
	self.LastComputedTarget = nil
	self.Enemy = nil
	self.Waypoints = {}
	self.PathfindingWaypoints = {}
	self.Path = nil
end

return Movement