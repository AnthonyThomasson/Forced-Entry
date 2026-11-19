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

**What a twin is not yet.** A twin is built once from the shapes its body had: a dent that reshapes a wall's, a piece's or a vehicle's 2D
collider does not reshape its twin (a dent is a few px); a vehicle's twin is its body to the belt, not the glass and roof above it; a
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
- **Two plays of one world can differ.** Jolt orders touching bodies by allocation, so a test that plays one scenario twice in a process
  sees the second play settle a pile in a different order; a Von test whose wording depends on it is `own_process` (as the 2D engine's
  slot order already made `combat_frag_take_cover`), and each twin space twins only the bodies of its own viewport (a nested
  `SubViewport` world owns its twins), so a replay's world does not meet another's.

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

## Consequences

- Every match and test world has a `TwinSpace` child named `Twins` (the stage's handle's `twins`, `TestWorld.twin_space()`); the main window's 3D
  physics space holds the twins of every world that stands in it, as its 2D space holds their bodies.
- The 3D step costs a little a frame at rest (Jolt's idle step and the sync, about 0.5 ms with the district's ~600 twins); the perf guards
  stand at their standard.
- A later job that reads a twin maps its collider back to the 2D body with `TwinSpace.owner_of` and calls that body's `get_surface()`; a job
  that flips a class to a 3D body replaces that class's builder and keeps a footprint twin for the readers still in 2D.
- Until the 2D space is gone, a reader that holds only the 2D direct space the sim casts in (the NPCs' sight, `AgentVision`) finds the 3D space
  beside it with `TwinSpace.space_for(space2d)`, a registry keyed by the 2D direct state's instance id (#194 sight3d). A world with no twin space
  (a hand-built test world) answers null and the caller treats nothing as blocking; two worlds in one window share one 3D space.
