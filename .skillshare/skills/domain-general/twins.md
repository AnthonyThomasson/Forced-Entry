# General: the twin 3D space (`scenes/general/`)

Side file of `domain-general`; the contract is architecture interface 29, the why is `docs/adr/0014-twin-staging-and-plan-space.md`.

`TwinSpace` (`twin_space.gd`, a `Node3D` named `Twins`, built by `MatchBuilder.stage` under the match's world) holds a 3D twin of each solid 2D body in the 3D physics space (Jolt) of the main window's
`World3D`, the counterpart of the 2D space the sim runs in. It is the staging of #194's move to a 3D simulation: nothing in gameplay reads it yet; the real-cover jobs cast rays into it
(`TwinSpace.space_of(node)`, `owner_of(collider)` back to the 2D body for `get_surface()`), then the bodies flip to 3D one class at a time and the twin direction reverses (ADR 0014).

- **Why that world.** The picture's `SubViewport` has a world of its own and a headless test world has no picture: tying the twins to the picture would make "the twin space exists" false in every test, and phase 2 reads it headless. The main window's world is
  where the 2D bodies live; when the bodies become 3D the picture's viewport drops `own_world_3d` and shares it.
- **The hook.** `builders: Array[Callable]`, `Callable(node: Node2D) -> Node3D`, first node wins, null passes. Each domain registers its own (`ObjectTwins.register(space)`, `VehicleTwins.register`, `CharacterTwin.register`, called by `MatchBuilder._twin_space`).
  The node is a `CollisionObject3D` in the frame of the 2D body's origin, shapes built in code (`TwinShapes`), on a `PhysicsLayers.TWIN_*` layer, mask 0; any `CollisionObject3D` is written when its body moves (Objects' are `StaticBody3D`s; a vehicle's and a character's `AnimatableBody3D`s with `sync_to_physics` off: a write is in the space at once, which a ray reads).
  A node with `twin_update(body)` gets it each frame it follows. A floor has no physics body: `track_group(&"floors", Floor)` (called by `ObjectTwins.register`; the kind script keeps `node_added` from queueing every `Node2D`).
- **The update rule** mirrors `WorldMirror`'s: read `global_transform`, write only when changed, park a sleeping `RigidBody2D` (once more as it falls asleep; a slow look, `PARK_SPREAD` frames round, catches a script that moves it asleep), write a never-moving body once (a body frozen at twin time is never followed, even if unfrozen: revisit in the furniture-3D job), retire a freed one (`tree_exiting` frees its twin and takes it off its layer at once). It runs before every body's script
  (`PRIORITY` -100): a reader finds a rigid body exactly where the step left it, a door or a character (a script moves them) a frame behind. A twin is on its layer only while its body's `collision_layer` is not 0.
- **Cost.** The spike: 600 twins, 0.13 to 0.16 ms a frame with the dirty check (0.32 without). Keep per-frame work to the followed bodies (`followed`, `written` read it); never loop all twins each frame.
- **Not followed yet.** A dent that reshapes a 2D collider (a wall segment, a piece, a vehicle) leaves its twin as built; a vehicle's twin stops at the belt (no glass or roof); a non-solid piece has none.
- **Tests:** `tests/general/twin_space_world_test.gd` (a test world: Jolt, a twin per body, the owner both ways, a still world writes nothing, a freed body frees its twin), `twin_space_in_match_test.gd`; helper `tests/_general/twin_probe.gd` (rays by plan point and height). The domains' own are in their skills.
