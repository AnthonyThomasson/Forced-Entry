11. **General → every domain: shared ids, `PhysicsLayers.SOLID`, `DrawLayers`, `GameClock` and the shared rules**
    - `PhysicsLayers` (`general/physics_layers.gd`, static holder): `SOLID` is the physics layer bit (1) "walls + solid furniture" live on.
	  Every raycast, sweep, collision mask or layer for it reads this one constant: Interaction's reach query, AI sight and line-of-fire
	  rays (`agent_vision.gd`; the vision overlay asks the controller's `debug_sight_end` instead of casting), the character's hand
	  queries, leg sweeps and clearing check (`use.keep_clear_of`), a dropped item's glance, a thrown grenade's flight, the bullet's
	  `collision_mask`, the blast's lines, `PhysicsConfig.wall_mask`, and a vehicle's body layer, mask, door checks and pile queries.
    - `LightMasks` (`general/light_masks.gd`, static holder): the masks every domain builds shadows and light layers on, so who shadows
	  whom is decided in one place (`docs/lighting.md` L6). Occluder bits `WALL` 1, `FURNITURE` 2, `EMITTER` 4 (a solid piece that gives
	  light: it shadows only the flashes), `CHARACTER` 8, `TALL` 16 (a solid piece with no light of its own at `TALL_COVERAGE` 75
	  `coverage` or more, above a standing person). Shadow masks Lighting gives its lights by height: `OVERHEAD_SHADOWS` (walls),
	  `LOW_SHADOWS` (walls + tall pieces), `ALL_SHADOWS` (a flash). Item light layers `HOUSE` 1 (Godot's default) and `STREET` 2 (the
	  street, lit only by the street lamps, flashes and its own sky). `shadows` (whether occluders are built; off with Testing's
	  `lighting.enabled`) and `occluder(polygon, bit) -> LightOccluder2D` (null while `shadows` is off; wound and culled so the shape
	  itself stays lit). Read by Objects (walls, solid pieces, street floors), Character (the living body) and Lighting (interface 20).
    - `DrawLayers` (`general/draw_layers.gd`, static holder): the world's draw-order ladder, one rung per kind of thing, so floor,
	  vehicle and fliers keep one order across domains. `FLOOR` −5 (Objects' `Floor`, `ObjectArtLayerConfig.floor_z_index`) < `RUG`
	  −4 (`ObjectArtLayerConfig.rug_z_index`) < `BLOOD` −3 (Physics: splats, pools, prints, smears, scorch; `BloodConfig.z_index` /
	  `print_z_index`) < `LYING` −2 (a dead body, `CharacterArtConfig.ragdoll_z_index`; a spent casing; a `DroppedItem` and a grenade
	  at rest) < `UNDER_VEHICLE` −1 (a vehicle's `Chassis`) < `STANDING` 0 (the living, a vehicle's occupants, furniture, walls) <
	  `ABOVE` 1 (a vehicle's `Roof`, a grenade in flight) < `OVERHEAD` 2 (a piece's `Overhang`,
	  `ObjectArtLayerConfig.overhang_z_index`, a streetlight's arm and head; a room's ceiling fixture, Lighting) < `EFFECTS` 4
	  (Physics' `ExplosionFx`) < `VISION` 5 (Vision's composite, absolute) < `OVERLAY` 6 (the debug overlays and markers over the
	  view, absolute: the AI's `DebugOverlay`s, `NavDebug`, the UI's `StackMarkers`, `OrderMarkers`, `ContactMarkers`,
	  `LeaderOverlay`). A domain's own z knob is initialised from its rung, never a bare number; within a rung the scene tree
	  decides. `docs/vehicles.md` V3 / V6: a body struck down lies under the vehicle.
    - `GameClock` (`general/game_clock.gd`, an autoload, `PROCESS_MODE_PAUSABLE`): counts physics frames in `_physics_process`, so it stands
	  still while the tree is paused. `GameClock.msec() -> int` (frames × 1000 / `Engine.physics_ticks_per_second`: deterministic under
	  `--fixed-fps`, however far a headless run outpaces the wall clock), `GameClock.seconds() -> float`, `GameClock.frame() -> int`. Every
	  AI ttl, timer and age reads it (`docs/leadership.md` LD1), so a pause of any length expires nothing; only what measures real time
	  stays on `Time` (the Von launcher's boot timeout and the planner's per-level `ms`, Von's latency). A per-frame key that measures no
	  age (`DecisionBudget`'s claim, the learn and sight offsets) may read `Engine.get_physics_frames()`.
    - `FillBatch` (`general/fill_batch.gd`, `RefCounted`): plain-coloured shapes drawn as one triangle array instead of a command each,
	  the same triangles and pixels as the engine's own (`draw_circle`'s 64-gon included). `FillBatch.new(canvas, base := IDENTITY)`,
	  `fill(poly, color, xform)`, `fill_convex(...)`, `circle(center, radius, color, xform)`, `flush()`; statics `FillBatch.unit_circle()`
	  (that 64-gon's corners round the unit circle) and `FillBatch.fan(base, n)` (a fan's triangle indices over `n` corners), which the
	  Character's `BodyMeshes.Solid` builds meshes from; `FillBatch.batching` is false under the headless display (it renders nothing),
	  where each shape is drawn by its own command. Used where many shapes draw each frame: the Character's limbs and shadow, Physics'
	  blood splats, chip and print chunks and wound marks.
    - `WorldRng` (`general/world_rng.gd`, statics): a world's random stream, `WorldRng.of(node)`, and its characters' spawn order,
	  `WorldRng.order_of(id)`; the AI keys on it, not on an instance id. `domain-general`.
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
	  and the command server's `match` verb (`verdict_of`) both decide by it, each wording it its own way.
    - `ViewLayers` (`general/view_layers.gd`, static holder): the visibility bits (`visibility_layer`) the player's view sorts the
	  world by. `WORLD` 1 (Godot's default: the house, what has come to rest), `MOVING` 2 (what moves: drawn only inside the cone),
	  `OVERLAY` 4 (overlays, markers, the view's composite). Vision's capture leaves `MOVING` and `OVERLAY` out of its cull mask.
	  `set_moving(item, moving)` (written only on change; Character, Items, Projectile, Physics, Vehicles call it) and
	  `overlay(item)` (`z_index` `DrawLayers.OVERLAY`, absolute, bit `OVERLAY`; the AI's debug overlays, Navigation, the UI).
    - `SightRay` (`general/sight_ray.gd`, `RefCounted`): the one sight rule. `SightRay.hit(space, from, to, exclude, see_over) ->
	  Dictionary` is the first thing on the line (`PhysicsLayers.SOLID`) too tall to see over (`intersect_ray`'s dictionary), {} when
	  the line reaches `to`; a collider at or below `see_over` is looked over, `exclude` is left as given.
	  `SightRay.coverage_of(collider) -> float` reads `get_surface()`: `transparent` (a glass-panel door) reads 0, looked through
	  however tall; no `coverage` reads 100. An instance (`looks_over`, `rated`, `leave_out(rids)`, `cast(...)`) serves a caller of
	  many rays (Vision's cone). AI perception's sight line and Vision's cone both cast through it.
    - `SeenArea` (`general/seen_area.gd`, static holder): what the view shows live. Vision writes `set_area(polygons: Array,
	  bounds: Rect2)` per rebuild and `clear()` on a lift; `reaches(center, radius)` (a disc) and `reaches_rect(rect)` (a long box)
	  say whether any of it is shown, true while no area is set. Character's visuals (60 px) and Physics' blood pools (their box)
	  skip a repaint on false. `contains(polygon, point)` is the one even-odd point test (the engine's `is_point_in_polygon` errs on
	  the cone).
