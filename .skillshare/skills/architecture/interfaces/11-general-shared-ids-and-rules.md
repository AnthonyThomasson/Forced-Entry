11. **General → every domain: shared ids, `PhysicsLayers.SOLID`, `GameClock` and the shared rules**
    - `PhysicsLayers` (`general/physics_layers.gd`, static holder): `SOLID` is the physics layer bit (1) "walls + solid furniture" live on.
	  Every raycast, sweep, collision mask or layer for it reads this one constant: Interaction's reach query, AI sight and line-of-fire
	  rays (`agent_vision.gd`; the vision overlay asks the controller's `debug_sight_end`), the character's hand
	  queries, leg sweeps and clearing check (`use.keep_clear_of`), a dropped item's glance, a thrown grenade's flight, the bullet's
	  `collision_mask`, the blast's lines, `PhysicsConfig.wall_mask`, and a vehicle's body layer, mask, door checks and pile queries.
    - `GameClock` (`general/game_clock.gd`, an autoload, `PROCESS_MODE_PAUSABLE`): counts physics frames in `_physics_process`, so it stands
	  still while the tree is paused. `GameClock.msec() -> int` (frames × 1000 / `Engine.physics_ticks_per_second`: deterministic under
	  `--fixed-fps`, however far a headless run outpaces the wall clock), `GameClock.seconds() -> float`, `GameClock.frame() -> int`. Every
	  AI ttl, timer and age reads it (`docs/leadership.md` LD1), so a pause of any length expires nothing; only what measures real time
	  stays on `Time` (the Von launcher's boot timeout and the planner's per-level `ms`, Von's latency). A per-frame key that measures
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
    - `SightRay` (`general/sight_ray.gd`, `RefCounted`): the one sight rule. `SightRay.hit(space, from, to, exclude, see_over) ->
	  Dictionary` is the first thing on the line (`PhysicsLayers.SOLID`) too tall to see over (`intersect_ray`'s dictionary), {} when
	  the line reaches `to`; a collider at or below `see_over` is looked over, `exclude` is left as given.
	  `SightRay.coverage_of(collider) -> float` reads `get_surface()`: `transparent` (a glass-panel door) reads 0, looked through
	  however tall; no `coverage` reads 100. An instance (`looks_over`, `rated`, `leave_out(rids)`, `cast(...)`) serves a caller of
	  many rays (Vision's cone). AI perception's sight line and Vision's cone both cast through it.
    - `SeenArea` (`general/seen_area.gd`, static holder): what the view shows live. Vision writes `set_area(polygons: Array,
	  bounds: Rect2)` per rebuild and `clear()` on a lift; `reaches(center, radius)` (a disc)
	  says whether any of it is shown, true while no area is set (`active()`; `version()` counts changes). Art's mirror and Projectile's casings hold back the unseen. `contains(polygon, point)` is the one even-odd point test.
