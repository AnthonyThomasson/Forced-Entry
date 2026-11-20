11. **General → every domain: shared ids, `PhysicsLayers.SOLID`, `GameClock`, `BodyHeights`, `PlanSpace`, shared rules**
    - `PhysicsLayers` (`general/physics_layers.gd`, static holder): `SOLID` is the physics layer bit (1) solid furniture lives on (2D; walls, doors and vehicles are plan handles with no layer); `TWIN_WORLD` (1), `TWIN_VEHICLE` (2), `TWIN_CHARACTER` (4), `TWIN_ROOF` (8, out of `TWIN_ALL`) and `TWIN_ALL` are the twin 3D space's layers (29).
	  `SOLID` is read by what still asks the 2D space (the AI's plan fallback with no twin space, the player's cone, a dropped item's glance, the blast's
	  lines, a vehicle's body layer). What asks the 3D space reads the twin layers (29): Interaction's reach,
	  `use.keep_clear_of`, a vehicle's door checks, the hand and leg queries, AI sight and line of fire, a grenade's flight, the bullet.
    - `GameClock` (`general/game_clock.gd`, an autoload, `PROCESS_MODE_PAUSABLE`): counts physics frames in `_physics_process`, so it stands
	  still while the tree is paused. `GameClock.msec() -> int` (frames × 1000 / `Engine.physics_ticks_per_second`: deterministic under
	  `--fixed-fps`), `GameClock.seconds() -> float`, `GameClock.frame() -> int`. Every
	  AI ttl, timer and age reads it (`docs/leadership.md` LD1), so a pause expires nothing; only what measures real time
	  stays on `Time` (the Von launcher's boot timeout, the planner's per-level `ms`). A per-frame key that measures
	  no age may read `Engine.get_physics_frames()`.
    - `WorldRng` (`general/world_rng.gd`, statics): a world's chance, order and frames; the AI keys on it, not on an instance id.
	  `register(root, match_seed)` (Main's stage), `of(node) -> RandomNumberGenerator`, `enrol(node) -> int` (a character's place,
	  from 0), `order_of(id) -> int`, `before(a, b) -> bool` (spawned first), `frame_of(node) -> int` (`GameClock` frames its world
	  has run, still while paused). `domain-general`.
    - `WeightedPick` (`general/weighted_pick.gd`, static holder): the one weighted roll, one `rng.randf()` over the total of the weights,
	  each entry in order taking the next stretch. `WeightedPick.pick(rng, rows, key_index := 0, weight_index := 1, strict := false)` (the
	  drawn row's `key_index` value), `key(rng, weights: Dictionary, strict := false)` (a key by its weight), `index(rng, rows,
	  weight_index := 1, strict := false) -> int`. `strict` is the caller's edge rule (false: a roll on a stretch's end takes that entry,
	  one past them all the last; true: the next entry, one past them all the first). World-Gen, Objects, Lighting and the Character's
	  style draw through it (`domain-general`).
    - `MatchVerdict` (`general/match_verdict.gd`, static holder): the one rule for who has won. `MatchVerdict.decide(combatants) ->
	  Dictionary`: `{}` while every side (faction) still has someone alive; once a side is wiped out `{ winner (the faction left standing,
	  null for a draw: nobody, or more than one side, left), survivors (the living combatants), sides (faction -> how many it fields) }`.
	  It reads `faction` and `is_dead`; a freed combatant is left out. The UI's `MatchHUD`
	  and the command server's `match` verb (`verdict_of`) both decide by it.
    - `ViewLayers` (`general/view_layers.gd`, static holder): the visibility bits (`visibility_layer`) the player's view sorts the
	  world by. `WORLD` 1 (Godot's default: the house, what has come to rest) and `MOVING` 2 (what moves: Art's mirror hides its mesh outside the cone).
	  `set_moving(item, moving)` (written only on change; Character, Items, Projectile, Physics, Vehicles call it) and
	  `overlay(item)` (AI debug overlays, Navigation, the UI: hands `item` to `GroundLayer.adopt`, which lays it flat on the ground over the 3D view, 27; no z or bit).
    - `SightRay` (`general/sight_ray.gd`, `RefCounted`): the one sight rule, real heights (#194 D9). **The eye ray**, in the twin space (29):
	  `SightRay.hit(space3d, from: Vector3, to: Vector3, exclude := []) -> Dictionary` is the first blocker (`TWIN_WORLD`, `TWIN_VEHICLE`, never a
	  character; a `transparent` surface and the rids in `exclude` are looked through), {} when clear.
	  `sees(space3d, eye: Vector3, to: Vector2, heights, exclude := []) -> bool` (first clear point ends the ask), `visible_heights(...)`,
	  `eye_point(viewer)`, `target_heights(target)` (a character's `BodyHeights.sight_points` at its posture), `exclude_of(target)`.
	  `visible_parts(viewer, target) -> PackedFloat32Array` (heights of its points the eye sees), `visible_centre(viewer, target) -> float` (their mean, -1 for none), `aim_height(viewer, target) -> float` (that, else the torso); `parts_at` / `aim_at(viewer, eye, target, at)`: from an eye, target at `at`. **The plan cast** (the player's cone):
	  `SightRay.plan_hit(space2d, from, to, exclude, see_over) -> Dictionary` is the first `SOLID` collider taller than `see_over` (the
	  eye, px); `top_of(collider) -> float` its twin's top (0 for a `transparent` surface or a character, `INF` with no twin). An instance (`looks_over`, `rated`, `leave_out(rids)`, `cast(...)`) serves Vision's cone.
    - `SeenArea` (`general/seen_area.gd`, static holder): what the view shows live. Vision writes `set_area(polygons: Array,
	  bounds: Rect2)` per rebuild and `clear()` on a lift; `reaches(center, radius)` (a disc)
	  says whether any of it is shown, true while no area is set (`active()`; `version()` counts changes). `set_viewer(character)` (Vision, each publish) names whose eye the view is:
	  `hides(body) -> bool` is true for a living character, not the viewer, of which no body point (`SightRay`) is clear from that eye, though the cone covers its ground (a ducked enemy
	  behind a sofa); Art's mirror hides such a mover. Art's mirror and Projectile's casings hold back the unseen. `contains(polygon, point)` is the one even-odd point test.
    - `BodyHeights` (`general/body_heights.gd`, static holder): a body's real proportions, the one scale between metres and the sim's px (1 3D unit = 1 px,
	  a 1.75 m person = 74 px, so `px_per_metre() = 42.3`; `px(metres)`, `metres(px)`). Per posture (`BodyHeights.STAND`, `DUCK` (head top about 0.85 m / 36 px:
	  hidden by a piece at least that tall), `FIRE_OVER` (the pose a ducked body rises to behind 0.9 m cover: bore 1.02 m); `postures_ids()`) heights in px above the floor: `head_top(posture)`, `eye(posture)`, `muzzle(posture)` (the bore line a bullet starts on),
	  `shoulder(posture)`, the hit-zone bands `zones(posture) -> [[zone, from, to], ...]` (`feet`, `legs`, `torso`, `head`, touching, feet up) and
	  `zone_at(posture, height) -> StringName` (where a hit at that height falls), `sight_points(posture) -> PackedFloat32Array` (the heights sight looks at on a body: head at the eye,
	  chest, hips; `SightRay`). The values are `BodyHeights.postures` (metres, tunable, `set_static`); the research is
	  `docs/research/3d-cover-heights.md`. `height_share(posture)`: head top over the standing one's (the drawn scale). A bullet reads `movement.body_posture()`'s muzzle (`weapon.rise`), the aim at a torso band and a hit's `zone_at`; sight the eye and `sight_points`; `BodyHeights.person_px` is
	  its standing head top. Test: `tests/general/body_heights_test.gd`.
    - `PlanSpace` (`general/plan_space.gd`, static holder): the plan-space helper. A `Vector2` in the AI, world generation, navigation and most tests means plan space, the floor
	  plan `(x, y)` = `(x, z)` on the 3D ground; `PlanSpace.lift(plan, height := 0.0) -> Vector3` is `(x, height, y) * RenderConfig.unit`, `plan_of(point) -> Vector2` and
	  `height_of(point) -> float` undo it; `lift_transform(xf: Transform2D, height := 0.0) -> Transform3D` lifts a body's 2D transform (a turn of `a` is a turn of `-a` about up; a local `(x, y)` is the local `(x, 0, y)`) and
	  `plan_transform(xf3) -> Transform2D` undoes it. It is the mapping of the mirror, the camera rig and the twin space (`MeshKinds.lift`, `CameraRig`, `TwinSpace`, 29), written once. Test: `tests/general/plan_space_test.gd`.
