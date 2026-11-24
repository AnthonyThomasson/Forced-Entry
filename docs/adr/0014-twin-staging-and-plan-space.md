# The 3D simulation is staged through twins, and plan space stays 2D

Issue #194 moves the simulation from 2D to 3D so height matters in gameplay. It is the largest change in the project (about 80k lines,
~4,000 `Vector2` uses, 843 test files), so it is not done in one cut: the 2D simulation stays the truth while a **twin 3D space**
(`TwinSpace`, interface 29) grows beside it, gameplay reads move onto the twins rule by rule, the bodies themselves then flip to 3D one
class at a time, and the 2D space and its mirror (ADR 0013) are deleted last. Every step ends playable with the suite green. This ADR
records the two decisions that make that possible (D3 staging, D4 plan space) and how the direction reverses.

## The twin space (D3)

A **twin** is a 3D body that stands for one solid 2D body: a wall, a floor slab, a piece of furniture (a box per part of
`PieceHeights`: a sofa's seat, arms and back), a door's leaf, a vehicle's body, a character's upright cylinder whose height follows its posture
(`BodyHeights`: standing the stature, crouched the duck). Each domain builds the twin of its own bodies behind a hook, as it builds their
meshes (`TwinSpace.builders`: `ObjectTwins`, `VehicleTwins`, `CharacterTwin`), from the same 2D shapes lifted with `TwinShapes` and
`PlanSpace` and the same real heights as the meshes, in code in `_ready`'s spirit (shapes built at twin time, never in a scene). Main's
`MatchBuilder.stage` builds one space per world, so a match and a test world both have one, and it stays out of every other domain's
way. **Nothing in gameplay reads a twin yet:** this job is the staging, and a test proves each twin lines up with its body.

**Where it lives.** Its twins join the 3D world of the viewport it stands in: the main window's `World3D`, the counterpart of the 2D
space the sim already runs in. The alternatives were a `SubViewport` of its own, and the 3D view's own world. A world of its own costs
a viewport node, an update mode to keep off and a second world to join the view's when the bodies flip. The 3D view's world would
tie the twins to the picture, and a headless test world has none (it has no rig, interface 27) while phase 2 gameplay reads the twins
headless: a rule that the picture exists would be false in every test. The main window's world has neither problem, exists in 2D
render, headless and windowed alike, and is what the picture's `SubViewport` shares once it stops owning a world: when the bodies are 3D
(the last flip job) the meshes attach to them, `View3D`'s viewport drops `own_world_3d`, and the twin direction **reverses** with
nothing moved: the 3D bodies become the truth, the 2D bodies become the footprint twins of the classes not flipped yet (each flipped
class keeps a 2D twin for the not-flipped readers, characters last), and when the last class is flipped the 2D space, those footprints and
`WorldMirror` are deleted (`WorldMirror` went in del2d-b3c: ADR 0015). `TwinSpace.space_of(node)` reads a sim node's viewport's 3D world, so a reader finds the twin space without
knowing where it was built.

**Synced like the mirror, once a frame.** `TwinSpace` reuses the mirror's update rule (ADR 0013): a followed body's `global_transform` is
read and the twin written **only when it changed**, a sleeping `RigidBody2D` is read once more as it falls asleep and then parked until it wakes (a slow look, a few frames round, catches a script that
moves it asleep), a body that never moves is written once (one frozen at twin time is parked and looked at slowly, so a later unfreeze is followed), a body that leaves the tree frees its twin. The spike measured it: 600 twins cost 0.13 to 0.16 ms a
frame with the dirty check, 0.32 without; the whole frame rises by 0.15 ms. The sync runs before every body's own `_physics_process`
(priority -100), after the engine's step has flushed the bodies it moves, so a bullet or a sight line in the frame's scripts finds
a rigid body's twin exactly where the 2D space has it; a character, which a script moves, is a frame behind where that script puts it (a door is led from 3D: below)
(1/60 s). A write is pushed to Jolt at once (`force_update_transform` on the twin: a `Node3D` would push its transform only at the frame's end, and a ray in the frame of the write would still meet the pose before it, #194 sight3d), kinematic or static alike; Objects' twins are static bodies
written when their body moves, so Jolt's step carries no always-active body for each of a district's hundreds of pieces and doors.

**Jolt.** The engine is Jolt (`physics/3d/physics_engine`, chosen at the phase-1 gate): it settles a tipped furniture pile (all asleep
in 6.7 s against 30 of 40 awake after 8 s) and casts rays in about half the time, at about 0.3 ms a frame more at rest.

**What a twin is not yet.** A twin is built once from the shapes its body had: a dent that reshapes a piece's or a vehicle's 2D
collider does not reshape its twin (a dent is a few px; a wall's twin is cut again, see below); a vehicle's body is the outline to the belt plus the cabin to the roof (its tapered glass is a box); a
non-solid piece (a rug) has none. A seated character's cylinder is off, a dead one's is on no layer (a knocked-down door is a free body, D18: `DoorSlab`, #194 doors3d, on the world layer, or on `TWIN_WALKOVER` once it lies flat within a step over: D19, no walker or vehicle meets it, a line and what lands on it do)
(`PhysicsLayers.TWIN_*`: world, vehicle, character), as their 2D bodies' are. The jobs that read the twins decide what they need of these.

## Furniture flips first: the direction reverses for a free piece (D13, D14, #194 furn3d)

The reversal this ADR planned for the last job happens for furniture first, as the first mover of phase 3. A piece that is free (not
anchored, standing on the floor) is a **`PieceBody`** (Objects, a `RigidBody3D` under Jolt): its truth. It is shaped from its real parts
(`PieceHeights`, so a bookshelf is a tall box, a stool a cylinder), has its mass from the catalogue (`Knockback.mass_of`) and its centre
of mass at the height of its shapes' middle, and slides, spins and tips as physics decides. Its 2D `RigidBody2D` stays in the tree as the
**footprint twin**, frozen and written from the 3D pose each frame (`TwinSpace._follow_lead`; a script that moves the footprint
anyway, a test or a teleport, is adopted: the 3D body is put where the script put it). Everything that still reads 2D (the nav holes,
the avoid maps, interaction finding, the 2D renderer, the vehicle's solver) keeps working on the footprint unchanged. `TwinSpace.leader_of(body)`
names the 3D body a footprint follows; an anchored piece, a wall-mounted one and every other class keep the 2D-led twin above. A frozen body
unfrozen later, a note this ADR left for furniture, is followed (the row is re-listed when it moves).

- **Shoves land at a real point and height** (`Knockback.push(body, impulse, at, height)`, interface 5): a bullet at the height it struck,
  a blast from its burst height, a punch or a kick at the fist's or foot's. Impulses above and below the centre of mass tip a piece in
  opposite ways, and a tall thin piece struck high tips where a low heavy one slides. A shove that is *carried* (walking into a chair,
  pressing a sofa) is clamped to the centre of mass: it slides and turns the piece about up and never flips it.
- **A tipped piece's geometry follows** (D14): its 3D shapes are the real ones, so a ray, a sight line, a grenade or a fragment meets the
  piece lying on its side at its new height. Its footprint collider is the hull of its shapes' corners projected onto the floor
  (`PieceBody.twin_update`, a collider dent is cut again once it is upright: `EnvironmentObject.set_tipped_collider` /
  `restore_collider`), and `footprint_stamp` tells the nav to re-bake around it. A piece whose up axis leans more than
  `PieceBodyConfig.tipped_degrees` (25) is *tipped*: `sit` and `lie` (every `move_to` action) are refused on it. Flipping a table on
  purpose, for cover, is out of scope.
- **Sleep:** a piece at rest sleeps (Jolt `can_sleep`; a plan-space drag that emulates the 2D damping is skipped under
  `PieceBodyConfig.drag_floor` so it can), the footprint is read once more as it falls asleep and then parked.
- **Jolt at px scale.** The unit is a pixel, which Jolt's metre-sized defaults do not suit: `project.godot` sets
  `speculative_contact_distance` 1.5, `penetration_slop` 0.3, `sleep_velocity_threshold` 1.5, `bounce_velocity_threshold` 40 and `max_linear_velocity` 5000 (the default 500 is a speed limit of 500 px/s, which a shoved chair meets). Jolt's
  penetration correction is about 0.2 px a step and cannot be raised, so a piece (or a character) spawned overlapping a wall or another
  piece is moved clear explicitly when it is twinned (`PieceBody.settle_out`, a zero-motion `body_test_motion`).
- **A twin space is a physics space of its own (amends "Where it lives").** Jolt solves touching bodies in the order of the slots they
  hold and reuses a freed body's slot, so worlds that shared the main window's space gave results that depended on what the process had
  run before (the same scene, the same hash only in a fresh process: a Von replay missed at the last float bit). `TwinSpace` is
  therefore a never-drawn `SubViewport` with `own_world_3d` (`UPDATE_DISABLED`), a fresh space for each staged world and each match;
  `TwinSpace.space_of(node)` finds a node's twin space through the `World2D` it stands in (`space_in`), the viewport's own 3D world where
  none stands beside it. Each twin space twins only the bodies of its own viewport (a nested `SubViewport` world owns its twins). When the
  bodies flip for good and the picture shares the twins' world (the last flip job), that world is this one.
- **The picture draws the twins' world (del2d-b, amends the line above and "Where it lives").** `View3D.mirror_world(world)` finds the
  world's `TwinSpace` (`TwinSpace.of_world`) and sets its picture's viewport to that `World3D` (`viewport.world_3d`; the view begins in a world
  of its own, never the window's, which views side by side would share, and gives it up for the twins' at that call, holding it until
  the swap is done, since the engine frees its scenario under the swap; a world with no twin space leaves the view its own). The rig, the lights, the environment, the outline and the mirror's meshes stand in the world the
  twins are in, which a mesh attached to a twin needs. Two staged worlds are two worlds and a view draws one: a test's second world is
  never drawn through the first's camera. The picture is unchanged, pixel for pixel
  (`general/view_world_picture_windowed`: the view's picture in the twins' world against a world of its own, lights held still (deleted in del2d-b3c: the meshes ride the twins, which a world of the view's own does not hold); `general/twin_carried_picture_windowed`: those meshes carried by their twins against the same meshes placed by hand (`tests/_art/art_followed_baseline.gd`, in del2d-b3c; the mirror's own followed arm before); `general/twin_moving_picture_windowed`: the same for a tipped piece, an open door and a fallen slab, whose twins are bodies that move; `general/twin_vehicle_character_picture_windowed`: a car and walking, crouched and fallen characters; `perf/mirror_carry_cost`: carried costs the mirror's own update no more than followed, at most 10 % and 0.02 ms over it, measured 15 to 21 % less for pieces; `perf/mirror_carry_fleet_cost` the same for a fleet of cars and characters, about 2.5 % less). That is the mirror's own update: the whole frame measured cost-neutral to +1.5 % with carry, as moving a mesh's transform's propagation to the twin side costs what the mirror saved (perf3d owns a whole-frame A/B). A car's mesh stands at its `VehicleBody`'s node pose, the one the engine synced at the start of the physics frame, and the twin space writes the car's handle from that same pose in that frame (priority -100), and the rider is placed from the handle: in a render frame (the camera, the view's ground, `WallFade`, the carrier) the handle, the seat and the drawn mesh are one place (del2d-c5c: `general/camera_follows_drawn_car`, `vision/view_eye_is_drawn_seat`, `art/twin_carries_vehicles_and_characters` with no slack). Only a read that awaits `physics_frame` (a test) sees the handle a step behind (`v / 60` px: 8 px at 500 px/s, 21 px at 1269): it stands between Jolt's sync and the twin space's write. The camera's lead term was always 0 at render and is deleted. A rider's own 3D twin (a `CharacterTwin`) follows the placed handle at the next write, so its pose stands one step behind the car's twin (8.4 px at 500 px/s), but **nothing reads it while seated**: its cylinder is disabled while `use.is_riding()` (no ray, sweep or shape query meets it), its mesh is hidden, and the sight reads the 2D handles. A driver is struck through the car's own twin. The drawn things with no body (floor stencils, lying items) are followed by Art's small `MeshFollower`, and the effects' and shots' layers (`FxLayer`, `ShotLayer`) are children of the view's viewport: neither goes through the mirror (`general/view_shares_the_twins_world`, `perf/mesh_follower_cost`: the follower's update is about half the mirror's tracking of the same nodes).
- **No gameplay code reads Jolt's contact events.** They are collected on worker threads and arrive in a different count and order run to
  run even when the simulation is identical (40 boxes dropped: the final poses hash alike in every run, `body_entered` fires 40 to 72
  times in any order), so a sliding piece's momentum is handed to the character or vehicle it strikes by a shape query of its shapes
  against those layers in `PieceBody.twin_update`, in a fixed order (by where the struck body stands), once a touch, from the velocity it
  carried before the step that met it. The 3D step itself is deterministic.
- **`max_linear_velocity` 5000 px/s is a cap on every Jolt dynamic body** (118 m/s: lower than the engine's default 500 m/s). It serves
  furniture; the jobs that put vehicles (vehicles3d) and ragdolls (ragdoll3d) into Jolt must raise it or hold them under it.

## Walls, floors and the street are static 3D bodies; a shared wall is built once (D3, #194 walls3d)

A static has no direction to reverse, nothing writes it each frame: its 3D body is built once, and the 2D one beside it never moves. What the flip
settles for walls is that the 3D wall is the truth for the 3D reads (bullets, fragments, lobs, sight), and that each wall exists once. The dent state
(`_seg_impacts`, the cut polygons) still lives in the 2D `Wall` until del2d deletes the 2D space, where the cut moves to the 3D wall; until then a dent
is cut in 2D first and `WallTwin` follows it. A wall is a **`WallTwin`** (Objects, a `StaticBody3D`)
built from its segments, and a dent that re-cuts a segment's outlines (`Wall.segment_rebuilt`) cuts its 3D shapes from the same dents, so a ray, a
fragment or a lob meets the outline the footprint has; the `Wall` handle holds the cut outlines as data (`segment_shapes()`) and no 2D collider exists any more (the nav bake
reads the twin since del2d-c, and every other reader the 3D space). Floors, roofs and the street have no 2D body at all (a floor is a node, its slab
and its roof are 3D only), so they were 3D truths already.

A wall two rooms share (Kitchen's south and Hall's north) used to be built twice, two coincident colliders in 2D and in 3D, so a bullet's tie in the seam
followed the engine's allocation order. World generation now says which stretches an earlier room's wall already stands on (`WallFactory.seams_for`:
the rects of the walls built so far; a house's rooms, a district shell and its partitions, a test layout), and the later room's `Wall` keeps the stretch as
a segment, so its doorways stay cut where they were, but builds no collider and no lintel there. The room built first owns the seam; a segment is split where a shared stretch begins or ends, and
is not lengthened by half a thickness at that end (the owner stands there). A room's wear marks on a stretch it does not own are laid on the owner's segments
(`Wall.neighbour_wear`).

## Doors: a standing door is a 3D leader, a door knocked down is a free body (D18, #194 doors3d)

A house door stands in its doorway as a **`DoorBody`**, an `AnimatableBody3D` locked upright, its leaf 84 px high under the lintel. The swing,
kick and step-degrees rule run in 3D (the swing asks the twin space for the angle one step on, a shape query of the leaf), and the `DoorBody`
writes the 2D `Door` each step (`TwinSpace`'s driven-leader branch), so the 2D body is the follower: the nav carve at the open stop and the
swing that nudges a character clear read it unchanged (interface 24, 7). A door **knocked down** is a free **`DoorSlab`** (a `PieceBody`,
`TwinSpace.retwin` swaps the twin when the door falls): torn off its hinges it falls and lies as physics decides, with the blow's impulse at its
real point (a blast from its burst height, a kick at the lock), plus the hinges' wrench across its face (`DoorFallConfig.fall_nudge`) so a freed
upright slab always topples the way the blow came. Bullets, sight, cover, grenades and fragments meet it at its lying height; it can be shoved like
a piece; its footprint (polygon data on the door, no 2D shape) is walk-over when flat (top within `DoorFallConfig.step_over`) and a solid obstacle and a nav hole when leaning
(`NavLeaves.fallen_hole`). The 2D follower of a door, like a footprint twin, is deleted with the 2D space; what survives is the 3D leader and slab.

## Plan space (D4)

The AI (about 26k lines), world generation, `NavBuilder`'s API and most tests think in the floor plan. They keep a `Vector2` that means
**plan space**, `(x, y)` in 2D and `(x, z)` on the 3D ground; `PlanSpace` (General) lifts a plan point and a height to a `Vector3`
`(x, height, y) * RenderConfig.unit` and back, and a 2D transform to its 3D one (`lift_transform`: a turn clockwise on the y-down screen is a
turn of `-angle` about up). Height enters only where it matters: an eye, a muzzle, a top, a grenade's altitude, from `BodyHeights` and
`PieceHeights`. This keeps the ~4,000 `Vector2` uses and most of the 843 tests as they are while the simulation gains a third axis;
the alternative, a global `Vector2` to `Vector3` sweep, would have touched every file of the project at once with nothing to run against.

## Considered options

- **Move everything in one cut.** Rejected: nothing would run for the duration and no test could say which of the 80k lines changed behaviour.
- **Twins built by one registry that knows every domain.** Rejected for the reason ADR 0013 rejected it for meshes: it spreads the
  2D-to-3D mapping and each body's shape knowledge over a domain that should not own it. General holds the mapping, the update rule and the
  hook; each domain builds the twin of what it owns.
- **A world per mode.** Rejected above (the twin space is the same in every mode).

## Characters lead (#194 chars3d-a, D13)

A character is the second class flipped. Its twin is a `CharacterBody3D` (`CharacterTwin`) that the walk moves with `move_and_slide` in
the twin space and the character's plain `Node2D` plan handle (del2d-c5: no 2D body, shape or layer) is its footprint, written from it each frame, as a free piece's is from its `PieceBody`. Decided
simply:

- **Locked upright on the floor.** The body's mode is floating and its `y` is held at 0: there is no gravity to simulate for a body that is
  never off the floor, and a piece is an obstacle, not a step to climb (its feet stand 0.5 px up, over a slab and a kerb). A straight
  cylinder, not a capsule: a round meets the body square at any height, as the 2D circle, and a head shot's damage does not turn down by a slant.
- **A 2D move is adopted.** A door's nudge, a vehicle's strike, a ride or a script still move the 2D body (those classes are 2D-led until their
  own jobs): its transform no longer being the one the twin wrote puts the 3D body there, velocity zero.
- **A stance change resizes the cylinder; it does not pop through anything.** A taller pose (a stand-up, a rise) is refused where a
  slightly narrower cylinder of that height would overlap a solid of the world or a vehicle; a lower one always fits.
- **Deterministic.** The walk reads the slide's own motion queries (not Jolt's contact events or lists, which vary run to run), keeps the
  pushables it slid into (a wall or a door is no push), one per body, and orders them by where they stand, so a Von replay stays bit for bit.
- **Where the 2D side costs.** The 2D follower stays in the 2D space for the readers not flipped yet (the nav's avoid maps and holes, the
  interaction finding, the AI's 2D queries) and goes with `del2d`; its cost is not optimised in this job.

- **What still asks the 2D space after chars3d-b (for del2d).** The interaction's reach, the clearing check (`use.keep_clear_of`), a vehicle door's
  swing and the AI's plan lines (`AgentVision.raycast`, `blocked`, `wall_hit`: 3D rays at an ankle's and an eye's height) ask the twin space.
  Left: (1) the 2D plan-line fallback of `AgentVision` for a world with no twin space (`raycast`, `wall_hit`, `_plan_piece`, `_plan_stop`);
  (2) the `space: PhysicsDirectSpaceState2D` parameter threaded through the AI (perception, entry, tactics, throw, door views, about a hundred
  signatures) that is only the handle `TwinSpace.space_for` turns into the 3D space: it becomes the 3D space itself; (3) every
  `get_world_2d().navigation_map` read (the locomotion, the stacks, the entry geometry: nav3d); (4) the ragdoll's wall sweeps
  (`CharacterAnatomy.ragdoll.step`: ragdoll3d); (5) `VehicleContacts._pile` / `_pressed_by`, which find a pile of characters through their 2D
  footprints; (6) the character's 2D `move_and_slide` for a body with no twin space and the zero-length `test_move` that folds a new body into
  the 2D space; (7) outside these domains, the player's cone (`Vision`, `SightRay.plan_hit`), `Explosion`'s 2D coverage, a door's nudge and
  the blood's queries. One rule for a world with no twin space (a hand-built one: every match and every staged test world has twins, so none
  of the game's own worlds is such): the moved readers answer it with their neutral answer (the reach finds nothing, the overlap check says no
  overlap, a door's swing is clear) and only `AgentVision` keeps a 2D plan fallback; those branches go with the 2D space. The plan lines are
  cast at an ankle's height, and every piece in the way blocks, as in 2D: the users that ask whether a point can be seen through them
  (`watch.gd`, `search_coverage.gd` through `has_line_to`) treat a low piece as opaque while the sight rays look over it: a follow-up for the
  AI, with `BodySweep` (about 0.8 ms a frame in a 10v10, which survives del2d) a candidate for perf3d. A seated or dead character is off the
  plan lines as it was (its 2D circle disabled, its layer 0, its twin off). The reach to a piece is to its real 3D body, as wide as its
  2D footprint was (a chair's 28 px square): a body exactly at the reach's rim (46 px) is no longer in it (the 2D engine counted shapes that
  touch, Jolt does not), which moved one premise by 6 px (`space_picks_nearest_to_mouse`). Measured (`tools/perf_ab.sh 389c3eb5 HEAD --different-fights`, 6 rounds, a busy machine): `match_5v5_stress` +0.7%,
  `grenade_match_stress` +1.8%, `match_10v10_stress` +1.8%, `match_npc_vision` -1.2% of the base's average frame.
- **After del2d-a (nothing reads the 2D space).** Of the list above, (1), (2) and, of (7), the player's cone, `Explosion`'s coverage, a door's nudge, (5) and (6) are
  done: a pile is found by 3D queries in the twin space, a door's nudge is the walker's `shift`, a character with no twin does not walk and nothing folds
  a body into the 2D space; the AI's `space` is the twin space itself (`space_of`, `space_in`), `AgentVision` and `Explosion`
  answer a world with no twin space with their neutral answer, and the player's cone is a level 3D ray at the viewer's eye height
  (`SightRay.plan_hit`) with its corners read by a 3D shape query over the column above the eye (`ViewShapes`), so a body with no twin blocks nothing.
  The AI and the view hold no physics RID (the AI's `exclude` is twin rids, `SightRay.exclude_of`; a plan hit's `rid` is its twin's; `ViewWatch` leaves the viewer out by
  instance id; a scan holds `scenes/ai` and `scenes/vision` to it), and the ragdoll's and the blood's queries are 3D (blood lies on the floor: a 1 px slab over it, so
  a piece hung above the floor is flowed under). With the 2D physics engine set to Dummy the run is red only where a test's own premise is a 2D body leading the
  simulation, and a bare `AnimatableBody2D` has `sync_to_physics` on, so a transform set by hand goes through the 2D server: `vision/cone_skip_exact`
  and `cone_skip_exact_sliced` (a mover moved by hand), `vision/cone_restarts_on_world_change` (a wardrobe), `art/mirror_hides_unseen_movers` (a car moved by hand; `art/mirror_follows_bodies` went with the mirror, del2d-b3c) and `general/twin_unfrozen_body_is_followed` (now `twin_static_piece_moved_by_script_is_followed`) (an unfrozen `RigidBody2D` the 2D step moves). They are 17c's: no 2D body leads. Four are fixed (del2d-c): the bare `AnimatableBody2D`s the vision tests move by hand have `sync_to_physics` off, as a door and a vehicle have, and the unfrozen post is moved by a script, so none needs the 2D step; the two `art/mirror_*` go with `WorldMirror` (del2d-b3c).
  Done in del2d-c3: a `Door` and a `Vehicle` are plain `Node2D` plan handles (groups `doors` / `vehicles`, `TwinSpace.BODIES`, `HARD`), with no 2D shape or layer. A fallen door's footprint is polygon data (`DoorFootprint`: the slab's hull, and whether the leaf lies flat) and `PhysicsLayers.LYING` is gone; a vehicle's twin is its `outline()` lifted to the belt; the collision exception a boarding or just-out character, or a corpse, had with a vehicle is a list on the vehicle's contacts (`share_space`). `ViewWatch` watches the handles of `BODIES` as it does colliders (a layer of `SOLID`, or a marker for a fallen door lying flat; an extent measured from the twin). The car-lead term of `CameraController.follow_point` was deleted in del2d-c5c: it was 0 at render (the handle and the drawn mesh are one pose there).
  Done in del2d-c5 (first part): a character is a plain `Node2D` plan handle (groups `BODIES` and `characters`; its `velocity` is `movement.velocity`, no 2D shape, layer or collision exception: the twin's layer follows `is_dead`, its cylinder is off while `use.is_riding()`, the mesh carrier hides a riding body by `use`); `TwinSpace.watch` twins characters and pieces in tree order (the same fight as before in all four perf guards, `perf_ab` same-fight mode). All of that was done in del2d-c5b to c5d (the last section), except `TwinSpace`'s `find_world_2d` key, which stays until nav3d.
  Done in del2d-c4: the furniture piece is a plain `Node2D` plan handle (groups `BODIES` and `PIECES`, no 2D body or shape); `Knockback`'s 2D adapter, a dent's re-cut collider and `ViewWatch`'s blind spot for a piece's reshaping (its signal `reshaped`) are gone. Closed in del2d-c5b to c5d (the last section): `ViewWatch` off 2D bodies, `PhysicsLayers.SOLID`, the 2D type checks, the bare test stand-ins and `raw_twins`, the allocation pad's 2D server. Stays until nav3d: the `get_world_2d().navigation_map` reads (locomotion, stacks, entry geometry) and `TwinSpace`'s `find_world_2d()` registry key and `space_in(World2D)`.

## Consequences

- Every match and test world has a `TwinSpace` child named `Twins` (the stage's handle's `twins`, `TestWorld.twin_space()`) with a 3D physics
  space of its own (a later amendment, below); the main window's 2D space holds the bodies of every world that stands in it.
- The 3D step costs a little a frame at rest (Jolt's idle step and the sync, about 0.5 ms with the district's ~600 twins); the perf guards
  stand at their standard.
- A later job that reads a twin maps its collider back to the 2D body with `TwinSpace.owner_of` and calls that body's `get_surface()`; a job
  that flips a class to a 3D body replaces that class's builder and keeps a footprint twin for the readers still in 2D.
- A reader that holds the `World2D` the sim stands in and no node finds the 3D space beside it with `TwinSpace.space_in(world)`, a registry keyed
  by the world's instance id (#194 sight3d, del2d-a). A world with no twin space (a hand-built test world) answers null and the caller treats
  nothing as blocking; two worlds in one window share one 3D space.

## The nav bake reads the twins (del2d-c, first slice)

The bake's source moved off the 2D colliders. `NavSource.walls_of` takes the plan polygon each shape of a wall's twin stands on
(`NavTwins.footprints`, which is `TwinShapes.footprint_of` at the twin's pose) instead of the engine's parse of the static bodies, and
`NavHoles` / `NavPieces` cut a piece's or a character's hole from the hull of its twin's footprints, grown by the obstacle margin (corners
mitred), instead of its `CollisionShape2D`s. The bake projects at the plan and never by an agent's height: a wall's lintel over a doorway (84 to
96 px, in the wall's twin) is left out (`grounded`: a shape whose underside is over the floor), so a doorway stays open. The twin space is made
before the bake (`MatchBuilder.stage`). `NavigationServer2D` stays until nav3d; a house with no twin space bakes no walls and no holes.

It is not the same outline, and the new bake was measured against the old one read from the 2D colliders (a district, seed 7, and a house). The old test and its 2D reference went with the colliders in del2d-c2; what they measured is recorded (`tests/_navigation/bake_baseline.gd`, taken at b2777f4b) and `navigation/bake_matches_recorded_colliders` (+ `_house`) reproduces it from the twins, and checks the walls against each `Wall`'s own outlines (the same outlines, the navmesh's clearance from them, every doorway open). The walls are the same outlines (341 holes and as
many walls in the district, each wall within a pixel). A round piece or character is the bake's own 10-sided polygon (`NavHoles.CIRCLE_SEGMENTS`),
not the twin's 16-sided disc: the 10-gon is the old geometry, so a round hole changes nothing (the 16-sided one moved 24 ambush posts of 210). What moves: a piece hung on a
wall (a menu board, a mirror, a towel rail) carves the depth its twin has, about half its 2D collider's; and a dent no longer changes a hole (a
twin keeps the outline it was built with, so a shot-up piece's hole is its full footprint, as it stood; `ai/combat/defend_room_stays_inside`, whose
fight shoots furniture, was re-recorded on the Von server). Measured on the district: the holes' area -0.9 %, the navmesh 889 polygons against
888 with +0.1 % area; on a house 112 against 111, +0.06 % area; of 90 routes between rooms' centres, none lost and none over 3 %. A character's
hole reads its twin, which follows a body a script moves within a frame (a character at rest has a twin too). Tests that moved a footprint by hand now
wait for its twin (`TwinSpace.PARK_SPREAD`) or move the twin. Still 2D in the bake, for 17c's later jobs: finding the pieces by engine type (done in del2d-c4: the group `TwinSpace.PIECES`; the walls by the group `walls`, del2d-c2); a character's
`collision_layer`.

## No 2D physics is left (del2d 17c, #194 del2d-c5d)

Every sim root is a plain `Node2D` plan handle: a wall, a floor, a piece, a door, a vehicle and a character. None is a physics body or holds a 2D
shape, layer or area. The twin space is the only physics space; `ViewWatch` and `TwinSpace` read handles only (no `CollisionObject2D`,
`PhysicsLayers.SOLID` is gone, so are `TwinShapes.lift_body` and `WallMesh.follows_shapes`); the 2D allocation pad is gone from the padding switch.
**What stays of 2D is `World2D` and `NavigationServer2D`**, until nav3d (done in nav3d-b: the nav is `NavigationServer3D`'s on the twin world's map, `World2D` is only the key that finds it): the AI passes `World2D` / `navigation_map` and `TwinSpace` keys its registry by
the `World2D` (`find_world_2d`, `space_in`). The AI's reads of `navigation_map` (locomotion, stacks, entry geometry) are nav3d's.

It is proven, not asserted: (1) `general/no_2d_space_reads_suite` scans every script under `scenes/` for a 2D body, shape, area, ray, query or
server (a comment is not code); (2) `general/no_2d_physics_node_in_a_district_match_test` and `..._a_house_match_test` walk the tree of a built district match and of a house match
and finds no `PhysicsBody2D`, `CollisionObject2D`, `CollisionShape2D`, `CollisionPolygon2D`, `Area2D`, `RayCast2D` or `ShapeCast2D`; (3) the whole suite is green
with the 2D physics engine set to Dummy (`physics/2d/physics_engine`), which any read of a 2D body would break.

A rider's 3D twin follows the car's handle a step late (see "The picture draws the twins' world"), but nothing reads it: its cylinder is off while it
rides and its mesh is hidden.
