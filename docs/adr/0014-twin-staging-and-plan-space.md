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
`WorldMirror` are deleted. `TwinSpace.space_of(node)` reads a sim node's viewport's 3D world, so a reader finds the twin space without
knowing where it was built.

**Synced like the mirror, once a frame.** `TwinSpace` reuses the mirror's update rule (ADR 0013): a followed body's `global_transform` is
read and the twin written **only when it changed**, a sleeping `RigidBody2D` is read once more as it falls asleep and then parked until it wakes (a slow look, a few frames round, catches a script that
moves it asleep), a body that never moves is written once (one frozen at twin time is parked and looked at slowly, so a later unfreeze is followed), a body that leaves the tree frees its twin. The spike measured it: 600 twins cost 0.13 to 0.16 ms a
frame with the dirty check, 0.32 without; the whole frame rises by 0.15 ms. The sync runs before every body's own `_physics_process`
(priority -100), after the engine's step has flushed the bodies it moves, so a bullet or a sight line in the frame's scripts finds
a rigid body's twin exactly where the 2D space has it; a door or a character, which a script moves, is a frame behind where that script puts it
(1/60 s). A write is pushed to Jolt at once (`force_update_transform` on the twin: a `Node3D` would push its transform only at the frame's end, and a ray in the frame of the write would still meet the pose before it, #194 sight3d), kinematic or static alike; Objects' twins are static bodies
written when their body moves, so Jolt's step carries no always-active body for each of a district's hundreds of pieces and doors.

**Jolt.** The engine is Jolt (`physics/3d/physics_engine`, chosen at the phase-1 gate): it settles a tipped furniture pile (all asleep
in 6.7 s against 30 of 40 awake after 8 s) and casts rays in about half the time, at about 0.3 ms a frame more at rest.

**What a twin is not yet.** A twin is built once from the shapes its body had: a dent that reshapes a piece's or a vehicle's 2D
collider does not reshape its twin (a dent is a few px; a wall's twin is cut again, see below); a vehicle's twin is its body to the belt, not the glass and roof above it; a
non-solid piece (a rug) has none. A seated character's cylinder is off, a dead one's and a knocked-down door's are on no layer
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
  `TwinSpace.space_of(node)` finds a node's twin space through the 2D space it stands in (`space_for`), the viewport's own 3D world where
  none stands beside it. Each twin space twins only the bodies of its own viewport (a nested `SubViewport` world owns its twins). When the
  bodies flip for good and the picture shares the twins' world (the last flip job), that world is this one.
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
built from its segments, and a dent that cuts a segment's 2D collider (`Wall.segment_rebuilt`) cuts its 3D shapes from the same dents, so a ray, a
fragment or a lob meets the outline the footprint has; the 2D colliders stay for what still reads 2D (the nav bake, the avoid maps, the 2D bodies that
collide with a wall, the 2D occluders of the vision cone) until the 2D space is deleted. Floors, roofs and the street have no 2D body at all (a floor is a node, its slab
and its roof are 3D only), so they were 3D truths already.

A wall two rooms share (Kitchen's south and Hall's north) used to be built twice, two coincident colliders in 2D and in 3D, so a bullet's tie in the seam
followed the engine's allocation order. World generation now says which stretches an earlier room's wall already stands on (`WallFactory.seams_for`:
the rects of the walls built so far; a house's rooms, a district shell and its partitions, a test layout), and the later room's `Wall` keeps the stretch as
a segment, so its doorways stay cut where they were, but builds no collider and no lintel there. The room built first owns the seam; a segment is split where a shared stretch begins or ends, and
is not lengthened by half a thickness at that end (the owner stands there). A room's wear marks on a stretch it does not own are laid on the owner's segments
(`Wall.neighbour_wear`).

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
the twin space and the 2D `CharacterBody2D` is its footprint, written from it each frame, as a free piece's is from its `PieceBody`. Decided
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

## Consequences

- Every match and test world has a `TwinSpace` child named `Twins` (the stage's handle's `twins`, `TestWorld.twin_space()`) with a 3D physics
  space of its own (a later amendment, below); the main window's 2D space holds the bodies of every world that stands in it.
- The 3D step costs a little a frame at rest (Jolt's idle step and the sync, about 0.5 ms with the district's ~600 twins); the perf guards
  stand at their standard.
- A later job that reads a twin maps its collider back to the 2D body with `TwinSpace.owner_of` and calls that body's `get_surface()`; a job
  that flips a class to a 3D body replaces that class's builder and keeps a footprint twin for the readers still in 2D.
- Until the 2D space is gone, a reader that holds only the 2D direct space the sim casts in (the NPCs' sight, `AgentVision`) finds the 3D space
  beside it with `TwinSpace.space_for(space2d)`, a registry keyed by the 2D direct state's instance id (#194 sight3d). A world with no twin space
  (a hand-built test world) answers null and the caller treats nothing as blocking; two worlds in one window share one 3D space.
