11. **General → every domain: shared ids, `PhysicsLayers.SOLID`, `DrawLayers`, `GameClock` and the shared rules**
    - `PhysicsLayers` (`general/physics_layers.gd`, a `class_name` static holder) — `SOLID` names
	  the physics layer bit (1) that "walls + solid furniture" live on. Interaction's reach query
	  (`character_interaction.gd`) and AI perception's sight/line-of-fire rays (`agent_vision.gd`; the
	  vision overlay asks the controller's `debug_sight_end` instead of casting) raycast on this one shared constant instead
	  of each redefining the same magic number — the single point of truth for that layer id. The character's
	  hand queries and leg sweeps (`character/body/`), a dropped item's glance (`items/dropped_item.gd`), a thrown grenade's flight (`items/thrown_grenade.gd`), the
	  bullet's `collision_mask` (`projectile/projectile.gd`), the blast's lines (`projectile/explosion.gd`), Physics' `PhysicsConfig.wall_mask` and a vehicle's body layer and mask, door
	  checks and pile queries (`scenes/vehicle/`) and the character's clearing check (`use.keep_clear_of`) read it too.
    - `LightMasks` (`general/light_masks.gd`, a `class_name` static holder) — the light masks every domain builds its shadows and
	  light layers on, so who shadows whom is decided in one place (`docs/lighting.md` L6): the occluder bits `WALL` 1,
	  `FURNITURE` 2, `EMITTER` 4 (a solid piece that gives light: it shadows only the flashes), `CHARACTER` 8, `TALL` 16 (a solid
	  piece with no light of its own as tall as `TALL_COVERAGE` 75 `coverage`, above a standing person); the shadow masks the
	  Lighting domain gives its lights by their height (`OVERHEAD_SHADOWS` walls: an overhead light; `LOW_SHADOWS` walls + tall
	  pieces: a low light; `ALL_SHADOWS` everything: a flash); the item light layers `HOUSE` 1 (Godot's default) and `STREET` 2
	  (the street, lit only by the street lamps, the flashes and its own sky); `shadows` (whether occluders are built: off with
	  the Testing domain's `lighting.enabled`) and `occluder(polygon, bit) -> LightOccluder2D` (null while `shadows` is off; wound
	  and culled so the shape itself stays lit). Read by Objects (walls, solid pieces, the street floors), Character (the living
	  body) and the Lighting domain (interface 20).
    - `DrawLayers` (`general/draw_layers.gd`, a `class_name` static holder) — the world's draw-order ladder, one rung per kind of thing,
	  so what lies on the floor, what a vehicle covers and what flies over it keep one order across domains: `FLOOR` −5 (Objects' `Floor`,
	  via `ObjectArtLayerConfig.floor_z_index`) < `RUG` −4 (rugs and mats, `ObjectArtLayerConfig.rug_z_index`) < `BLOOD` −3 (Physics: splats, a
	  bleed-out pool, prints and smears, the scorch decals; `BloodConfig.z_index` / `print_z_index`) < `LYING` −2 (a dead body,
	  `CharacterArtConfig.ragdoll_z_index`; a spent casing, Projectile; a `DroppedItem` and a grenade at rest, Items) < `UNDER_VEHICLE` −1
	  (a vehicle's `Chassis`) < `STANDING` 0 (Godot's default: the living, a vehicle's occupants, furniture, walls) < `ABOVE` 1 (a
	  vehicle's `Roof`, a grenade in flight, the UI's `StackMarkers`, `OrderMarkers` and `LeaderOverlay`) < `OVERHEAD` 2 (a piece's `Overhang`, Objects:
	  `ObjectArtLayerConfig.overhang_z_index`, a streetlight's arm and head; a room's ceiling fixture, Lighting) < `EFFECTS` 4 (Physics' `ExplosionFx`). A domain's own z knob is initialised from its rung,
	  never a bare number; within a rung the scene tree decides. `docs/vehicles.md` V3 / V6 (a body struck down lies under the vehicle).
    - `GameClock` (`general/game_clock.gd`, an autoload node, `PROCESS_MODE_PAUSABLE`) — the pausable game clock: it counts physics
	  frames in `_physics_process`, so it stands still while the tree is paused. `GameClock.msec() -> int` (frames × 1000 /
	  `Engine.physics_ticks_per_second`: deterministic under `--fixed-fps`, however far a headless run outpaces the wall clock),
	  `GameClock.seconds() -> float` and `GameClock.frame() -> int`. Every AI ttl, timer and age reads it (`docs/leadership.md` LD1: the
	  memory's ages, callout ages, the controller's stamps and force age, the leaf age, burst ages, the grenade replan, the debug overlays'
	  ages and blink), so a pause of any length expires nothing; only what measures real time stays on `Time` (the Von launcher's boot
	  timeout and the planner's per-level `ms`, Von's latency). A per-frame key (`DecisionBudget`'s claim, the learn and sight offsets,
	  a once-a-frame check) may still read `Engine.get_physics_frames()`: it measures no age.
    - `FillBatch` (`general/fill_batch.gd`, a `RefCounted`) — plain-coloured shapes drawn as one triangle array instead of a polygon
	  command each, the same triangles the engine would cut and `draw_circle`'s own 64-gon, in order, so the same pixels:
	  `FillBatch.new(canvas, base := IDENTITY)`, `fill(poly, color, xform := IDENTITY)`, `fill_convex(poly, color, xform := IDENTITY)`,
	  `circle(center, radius, color, xform := IDENTITY)`, `flush()`; the statics `FillBatch.unit_circle()` (that 64-gon's corners round the
	  unit circle) and `FillBatch.fan(base, n)` (a fan's triangle indices over `n` corners from `base`), which the Character's
	  `BodyMeshes.Solid` builds its meshes from; `FillBatch.batching` (false under the headless display, which renders
	  nothing: each shape is then drawn by its own command). Used where many are drawn each frame: the Character's limbs and shadow, the
	  Physics domain's blood splats, chip and print chunks and wound marks.
    - `WeightedPick` (`general/weighted_pick.gd`, a `class_name` static holder) — the one weighted roll: one `rng.randf()` over the total of
	  the weights, each entry in order taking the next stretch. `WeightedPick.pick(rng, rows, key_index := 0, weight_index := 1, strict := false)`
	  (the drawn row's `key_index` value), `key(rng, weights: Dictionary, strict := false)` (a key, by its weight) and
	  `index(rng, rows, weight_index := 1, strict := false) -> int`; `strict` is the caller's edge rule (false: a roll on a stretch's end
	  takes that entry, one past them all the last; true: the next entry, one past them all the first). World-Gen's room dresser,
	  Objects' room wear and street marks, the Lighting domain's rhythms and the Character's style draw through it.
    - `MatchVerdict` (`general/match_verdict.gd`, a `class_name` static holder) — who has won a match, the one rule:
	  `MatchVerdict.decide(combatants) -> Dictionary`, `{}` while every side (faction) still has someone alive; once a side is wiped out
	  `{ winner, survivors, sides }` (`winner` the faction left standing, null for a draw: nobody, or more than one side, left; `survivors`
	  the living combatants; `sides` faction -> how many it fields). It reads the combatants through the Character API (`faction`,
	  `is_dead`; a freed one is left out, its side not counted for it). The UI's `MatchHUD` (its banner) and the dev command server's `match` verb (`verdict_of`,
	  which `tools/match.py` scores by) both decide by it, each wording the result its own way (the HUD names a lone survivor in any match,
	  the `match` verb only in a 1v1).
