# Enemy AI Modules

A collection of scripts used to create the collective enemy ai used in "CONTRACTS".
These scripts were mainly stored within their own folder within the ServerScriptService.

This was developed alongside a minorly modified version of the Endorsed Weapons Kit.

Below is the documentation I created and hosted within the logic folder whilst working on this project.
--[[

======================================================================
1. DESIGN GOAL
======================================================================

The enemy AI exists to support this gameplay loop:

    STEALTH  ->  SUSPICION / INVESTIGATION  ->  COMBAT  ->  SEARCH / RESET

It should feel readable, responsive, and fun. It should NOT become a full
social-stealth simulator. The goal is simple stealth openings and exciting
third-person firefights.

Core priorities:

    1. Simple behaviour players can understand.
    2. Server-authoritative gameplay decisions.
    3. Good performance with many enemies.
    4. Reuse existing systems instead of duplicating logic.
    5. Clear fallback behaviour when something goes wrong.


======================================================================
2. IMPORTANT PLAYER DEATH RULE
======================================================================

This game does not use normal Roblox death for the player during contracts.

    Player downed / dead state = Humanoid.Health == 1

Enemy combat must NEVER reduce player health below 1.

When the player reaches Health == 1:

    - EnemyService.OnPlayerDown() is called.
    - Enemy AI is deactivated for the failed contract state.
    - Enemies clear visible targets, last known positions, combat, search,
      and investigation state.
    - Enemies should not keep shooting or chasing the player.
    - The client moves the player to DisclaimerPart and shows the death UI.


======================================================================
3. MAIN SERVER MODULES
======================================================================

Enemy - Handler (Server)
    Location:
        ServerScriptService.GameplayScripts.Enemies.Enemy - Handler (Server)

    Responsibility:
        - Starts EnemyService, VisualFeedback, Encounter, and debug services.
        - Registers enemy and target models when maps load.
        - Watches Workspace.World and Workspace.Safehouse for spawned enemies.
        - Ignores non-gameplay reference models such as Workspace.Marine.


EnemyService
    Location:
        ServerScriptService.GameplayScripts.Enemies.Logic.EnemyService

    Responsibility:
        - Owns the active enemy list.
        - Runs the AI scheduler.
        - Handles contract active/inactive state.
        - Clears AI when the player is downed.
        - Destroys all enemies during map unload/retry/end.
        - Routes player gunshot events to nearby enemies.

    Notes:
        - AI does not update when ContractActive is false.
        - Updates are staggered/round-robin for performance.
        - Combat/search/investigate enemies update more often than idle/far enemies.


Enemy
    Location:
        ServerScriptService.GameplayScripts.Enemies.Logic.Enemy

    Responsibility:
        - Represents one NPC.
        - Creates Perception, Movement, Combat, EnemyAnimator, and EnemyAudio.
        - Owns the state machine.
        - Handles cleanup and death.

    Current states:
        - Dead
        - Combat
        - TargetFlee
        - TargetSurrender
        - Investigate
        - Search
        - Patrol
        - Idle

    State priority matters. Combat and death override normal behaviour.


StateController
    Location:
        ServerScriptService.GameplayScripts.Enemies.Logic.StateController

    Responsibility:
        - Simple priority-based state machine.
        - Each state has CanRun, Enter, Update, and Exit callbacks.


======================================================================
4. PERCEPTION
======================================================================

Perception
    Location:
        ServerScriptService.GameplayScripts.Enemies.Logic.Perception

Responsibilities:

    Vision:
        - Range check.
        - Field-of-view cone.
        - Close range detection.
        - Line-of-sight raycast.
        - Ignores players with Health <= 1.

    Hearing / shot reaction:
        - Player weapon fire is sent through EnemyService.HandlePlayerShot().
        - Weapon-specific ShotAudibleDistance is clamped to a max of 55 studs.
        - Enemies only hear shots on roughly the same floor; large vertical separation blocks hearing.
        - Walls/floors occlude sound and heavily reduce the effective radius.
        - If an enemy is directly hit, it reacts even outside audible range.
        - If the hit enemy can see the shooter, it enters combat.
        - If it cannot see the shooter, it investigates/searches instead.

Investigation feedback:

    ? above head:
        Enemy heard or noticed something and is investigating.

    ! above head:
        Enemy confirmed the player and is entering combat.

Sniper behaviour:

    If the player shoots from far away and is not visible:
        - The enemy reacts to being hit.
        - The enemy does not magically know the player location.
        - The enemy investigates/searches based on shot information.


======================================================================
5. MOVEMENT AND PATHS
======================================================================

Movement
    Location:
        ServerScriptService.GameplayScripts.Enemies.Logic.Movement

Responsibilities:

    Patrol:
        - Follows the AssignedPath ObjectValue placed on the enemy model.
        - Uses precomputed patrol path segments when available.
        - Falls back to raw path nodes if precomputed data is missing.

    MoveTo:
        - Used for combat movement, investigation, search, and fleeing.
        - Uses PathfindingService dynamically because these destinations change.

    Stuck handling:
        - Tracks lack of progress.
        - Reissues movement a few times.
        - Fails cleanly if still stuck.
        - Enemy then abandons unreachable search/investigation targets.


Map-load patrol precomputation:

    Location:
        ServerScriptService.GameplayScripts.MapLoader (Server)

    During contract map loading:
        - Each folder in Workspace.World.Enemies.Paths is scanned once.
        - BasePart nodes are sorted by number/name.
        - PathfindingService computes node-to-node segments once.
        - Results are stored under:

            PathFolder
                PrecomputedPathSegments
                    Segment_001
                        Waypoint_001 : Vector3Value
                        Waypoint_002 : Vector3Value
                    Segment_002
                        ...

    Why:
        - Multiple enemies can share one path without recomputing the same path.
        - Patrol is efficient.
        - Combat/investigation can still use dynamic pathfinding when needed.


======================================================================
6. COMBAT
======================================================================

Combat
    Location:
        ServerScriptService.GameplayScripts.Enemies.Logic.Combat

Responsibilities:

    - Equips a weapon from ReplicatedStorage.Weapons.
    - Reads weapon Configuration values:
        HitDamage, ShotCooldown, AmmoCapacity, MaxSpread, ReloadTime.
    - Uses server-side raycasts to shoot the player.
    - Applies armour reduction.
    - Clamps player health to minimum 1.
    - Plays weapon fire/reload/equip sounds where available.
    - Plays aim/reload animations from WeaponsSystem assets.

Combat movement:

    - Faces the player using Marine-inspired AlignOrientation.
    - Keeps enemies upright by facing on the flat Y plane.
    - Chases if too far.
    - Backs away if too close.
    - Strafes and repositions at medium range.
    - Uses predictive aim based on target velocity.
    - Can fire short bursts at closer range.

Important:

    Do not directly pitch the whole enemy model up/down to aim.
    The enemy should stay upright during combat.


======================================================================
7. TARGET BEHAVIOUR
======================================================================

TargetBehaviour
    Location:
        ServerScriptService.GameplayScripts.Enemies.Logic.TargetBehaviour

Targets are registered into the same enemy system as guards, but their behaviour
is controlled by configuration.

Supported target behaviours:

    Fighter
        - Equips a weapon.
        - Uses normal Combat behaviour.

    Flee
        - Runs toward configured escape points if available.
        - Falls back to running away from the threat.

    Surrender
        - Stops moving.
        - Unequips tools.
        - Sets TargetSurrendered attribute.
        - Shows a SURRENDERED marker.
        - Uses SurrenderAnimation if provided.
        - Only surrenders to a visible threat:
            * player is visible,
            * target behaviour is Surrender,
            * player has a weapon equipped and is facing/aiming at the target,
              OR the target was shot and can see the player.
        - Hearing a gunshot or investigating a noise alone does NOT cause surrender.

Surrender animation placeholder:

    ReplicatedStorage.Animations.SurrenderAnimation

    Fill in AnimationId when the animation is ready.
    If AnimationId is empty, the system falls back to the old manual surrender pose.


======================================================================
8. ANIMATION
======================================================================

EnemyAnimator
    Location:
        ServerScriptService.GameplayScripts.Enemies.Logic.EnemyAnimator

Responsibilities:

    - Server-side animation for NPCs.
    - Disables cloned LocalScript Animate on NPCs.
    - Handles idle, walk, run, jump, fall, sit, and surrender.
    - Combat aim/reload animations are handled by Combat.

Current base animation IDs:

    Idle:
        rbxassetid://10848551631

    Walk:
        rbxassetid://913402848

    Run:
        rbxassetid://913376220

    Surrender:
        ReplicatedStorage.Animations.SurrenderAnimation if filled in.
        Otherwise fallback idle/manual pose.


======================================================================
9. AUDIO
======================================================================

EnemyAudio
    Location:
        ServerScriptService.GameplayScripts.Enemies.Logic.EnemyAudio

Responsibilities:

    - Enemy barks.
    - Hurt sound.
    - Death sound.
    - Reloading bark.
    - Combat/investigate bark.
    - Footstep sounds.
    - Weapon equip/reload sounds from the equipped weapon when present.

Bark placeholders:

    SoundService.SoundEffects.Barks.Enemy.Alert
    SoundService.SoundEffects.Barks.Enemy.Investigate
    SoundService.SoundEffects.Barks.Enemy.Combat
    SoundService.SoundEffects.Barks.Enemy.Reloading
    SoundService.SoundEffects.Barks.Enemy.Hurt
    SoundService.SoundEffects.Barks.Enemy.Death
    SoundService.SoundEffects.Barks.Enemy.Footstep

Fill in SoundId values as needed.


======================================================================
10. ENCOUNTERS AND ALERT PROPAGATION
======================================================================

Encounter
    Location:
        ServerScriptService.GameplayScripts.Enemies.Logic.Encounter

Responsibilities:

    - Groups nearby enemies into encounter groups.
    - When one enemy spots the player, relevant nearby enemies are alerted.
    - Prevents the whole map from instantly knowing about the player.

EventsService
    Location:
        ServerScriptService.GameplayScripts.Events.EventsService

Responsibilities:

    - Broadcasts gameplay events like PlayerSpotted and BodyDiscovered.
    - Maintains a small recent-event buffer for debugging.


======================================================================
11. MAP / CONTRACT LIFECYCLE
======================================================================

MapLoader
    Location:
        ServerScriptService.GameplayScripts.MapLoader (Server)

Responsibilities:

    Contract map load:
        - Clears old enemies.
        - Rebuilds Workspace.World content.
        - Copies enemy spawn/path config.
        - Precomputes patrol path segments.
        - Fires MapLoaded bindables/events.

    Contract map unload:
        - Destroys registered enemies.
        - Clears Workspace.World contract folders.
        - Fires MapUnloaded bindables/events.

    Safehouse load:
        - Ensures exactly one Workspace.Safehouse exists.
        - Repairs stale SafehouseLoaded state if needed.
        - Clears active contract world/enemies.
        - Fires SafehouseLoaded and MapLoaded events.

Client return-to-safehouse:

    Location:
        StarterPlayer.StarterPlayerScripts.GameplayScripts.Contract - Handler

    Notes:
        - Waits for Workspace.Safehouse and SpawnLocation with timeouts.
        - Avoids assuming replication is complete immediately after MapLoaded.


======================================================================
12. PERFORMANCE RULES
======================================================================

Do:

    - Use EnemyService scheduler.
    - Cache pathfinding for patrol routes at map load.
    - Use dynamic pathfinding only for changing destinations.
    - Keep perception checks simple.
    - Keep visual feedback mostly client-side.
    - Clean up enemies immediately on map unload/retry.

Do NOT:

    - Update every enemy every frame.
    - Recompute identical patrol paths per enemy.
    - Give enemies perfect knowledge of the player.
    - Make the AI overly tactical or simulation-heavy.
    - Let enemies attack players with Health <= 1.


======================================================================
13. DEBUGGING CHECKLIST
======================================================================

Enemy does not move:
    - Does it have AssignedPath?
    - Does AssignedPath.Value still exist?
    - Does the path folder contain BasePart nodes?
    - Did Movement mark a failure reason?

Enemy does not see player:
    - Is ContractActive true?
    - Is player Health > 1?
    - Is player inside DetectionRange/FOV?
    - Is line of sight blocked?

Enemy keeps attacking after death screen:
    - Check EnemyService.OnPlayerDown fired.
    - Check player Health is exactly 1.
    - Check ContractActive is false.

Safehouse missing after contract:
    - Check Workspace.Safehouse exists.
    - Check MapLoader SafehouseLoaded state.
    - Check client waited for SpawnLocation replication.

Target does not surrender animation:
    - Check ReplicatedStorage.Animations.SurrenderAnimation exists.
    - Check AnimationId is filled in.
    - Check target TargetBehaviour is Surrender.


======================================================================
14. GUIDING PRINCIPLE
======================================================================

The AI should create this feeling:

    "I was sneaking through the compound."
        -> "They heard something."
        -> "They saw me."
        -> "Now I need to fight or escape."

Readable behaviour beats complex behaviour.
Performance beats simulation.
Fun beats realism.

]]--
