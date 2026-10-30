4. **Objects/Character/Vehicles → Physics** (objects, the character and a vehicle compose physics; Physics is a leaf domain)
   - `Knockback` (Node child): RigidBody2D adapter — configures its parent body and owns
	 `apply_impulse(v, at_world)`; `mass` (the body's mass, which its owner sets from the catalogue `weight` before `_ready`).
   - `Deformable` (Node child): `record(hit, turn = 0.0)`, `impacts`, `damage_total`, `changed`
	 signal (`turn`: the body's drawn turn beyond its node rotation; the character passes its facing), and three per-body knobs its owner
	 sets: `max_depth` (the deepest one dent caves, px), `allow_chunks` (a hard hit carves a missing piece) and `max_impacts` (how many
	 dents it remembers), each defaulting to `PhysicsDeformConfig`'s (the character sets its softer flesh values from `CharacterHitConfig`). A
	 vehicle composes one (no `Knockback`: it is its own `RigidBody2D`) with chunks off and does not rebuild its collider from the dents.
   - `Deformation` (static): silhouette/collider polygons + drawing (`draw_shape(canvas, shape, size, impacts, look: ShapeLook)`
	 and `draw_wall(canvas, a, b, impacts, look: WallLook)` optionally textured — `ShapeLook` (`physics/shape_look.gd`: `fill`,
	 `outline`, `damage_total`, `crack_color` / `hole_color` / `scorch_color`, `texture`, `texture_angle`, `marks`) also turns the
	 texture by `texture_angle`, its hit marks optional (`marks`) for a caller drawing them over later layers with `draw_marks`;
	 `WallLook` (`physics/wall_look.gd`: `thickness`, `color`, `texture`, `tile_length`) — so pixel art is drawn through the
	 dented silhouette). The polygons are `base_ring(shape, size)` (a primitive's undented ring),
	 `shape_polygon(shape, size, impacts)` (a piece's or the character's dented silhouette, cached), `wall_polygon(a, b, thickness, impacts)`
	 (a dented wall segment), `is_valid_polygon(poly)` (callers skip a self-touching one that frame), `convex_pieces(polygon)` (the
	 convex pieces a dented collider is rebuilt from, as their points) and `shapes_of(pieces)` (their `ConvexPolygonShape2D`s); and
	 `cut_shape(shape, size, impacts)` / `cut_wall(a, b, thickness, impacts)` -> `[polygon, pieces]`, a dented silhouette and its pieces
	 computed without the caches: all pure, so they may run on a worker thread). An impact record (the dicts in `impacts`) is built by
	 `new_impact(pos, inward, damage, blood, dent: DentLimits)` (`DentLimits`, `physics/dent_limits.gd`: `max_depth`, `allow_chunks`,
	 `max_depth` defaulting to `PhysicsDeformConfig.max_depth`, `allow_chunks` to true) and kept by `push_impact(list, impact, max_impacts)` (oldest
	 dropped past the cap): `Deformable.record` and Objects' wall, which keeps an impact list per segment, both build through them. `NO_COLOR` is the sentinel a caller passes to take a
	 drawing call's default colour. `darken(damage_total) -> float` is how far `draw_shape` darkens a shape that has taken that
	 damage (`Color.darkened`'s weight; a textured shape is white darkened by it), for a caller that draws a textured shape's polygon its
	 own way (the character's kept meshes, `domain-character-body`) in the same colour.
   - `Physics.impact_impulse(hit) -> Vector2`, `Physics.spawn_debris(world, hit, surface)` (objects, the character and a vehicle)
	 `BloodWound` (Node child, character: `record(hit)` on a hit throws a splatter spray and owes drips, one
	 `BloodSplat` every `BloodDripConfig.interval_min..max` s from the body's blood origin; `stop()` on death)
	 and `Physics.bleed_out(parent, source, exclude)`
	 (a dead character, once its body comes to rest: one slow, wide pool). A blood source may expose
	 `blood_origin() -> Vector2` (where its blood leaves it, in world space); pools emerge there instead
	 of at its position, so a fallen body bleeds from where it lies. Master switches:
	 `BloodConfig.enabled` off → `BloodWound.record` / `bleed_out` spawn nothing (`bleed_out` returns null);
	 `PhysicsConfig.debris_enabled` off → `spawn_debris` spawns nothing. Splatters and bleed-out
	 pools are added with readable names (`BloodSplat`, `BloodSplat2`, … / `BloodPool`, …).
   - `BloodField` (static registry, Physics-internal: `BloodSplat`/`BloodPool` register themselves) /
	 `BloodDecals` (a batched layer under a world node, `BloodDecals.layer(parent)`) /
	 `BloodFootprints` (Node child, character: `step(foot, fall: Footfall)` (`Footfall`,
	 `physics/blood/footfall.gd`: `at`, `direction`, `length`, `width`, `inner`, `speed`) on each footfall prints a sole if the foot is carrying wet blood) / `BloodSmear` (Node child, objects:
	 `set_footprint(local_polygon)`, then drags blood out of a puddle as feathered, wandering ribbons while the body slides).
	 Both need `BloodConfig.enabled` and their own switch (`BloodPrintConfig.footprints_enabled` / `BloodSmearConfig.enabled`).
   - `BloodSurface` (static registry): `register(rect, groove: Callable(world, half_width) -> 0..1, porous) -> id` /
	 `unregister(id)` — Objects' `Floor` registers its room so a bleed-out flow runs along grout/seams, and rugs register as porous
	 (blood sinks into carpet and rugs, `is_porous(pos)`)
	 (`resistance(pos)` is read only by Physics' `BloodFlow`; `BloodSurfaceConfig.flow` off ignores floors).
   - `Ragdoll` (`RefCounted`, character on death): a generic 3D point-mass body over the floor plane
	 (x/y + height z). Built with `add_point(at, radius, mass)`, `add_bone(a, b)` / `add_rigid(indices)`,
	 `add_frame(origin, up, right, forward_hint)`, `add_swing(frame, joint, child, rest, limits)`
	 (cone limit) and `add_hinge(frame, parent, joint, child, limits: HingeLimits)` (one-way
	 hinge; `HingeLimits`, `physics/hinge_limits.gd`: `rest`, `bend`, `min_angle`, `max_angle`, `slack`), seeded with `push(i, v)`, stepped with `step(delta, space, origin)` until `asleep`; read
	 with `point(i)` / `point_count()` / `frame_basis(f)`; `exclude` lists colliders its wall sweep
	 ignores. The Character domain owns the humanoid skeleton built on it.
   - `Physics.spawn_explosion(world, at, kind)` (`kind` `&"frag"` / `&"stun"`; called by the Projectile System's `Explosion`): the look of a
     grenade's burst, `ExplosionFx` nodes `ExplosionFlash` and `ExplosionFireball` (frag only: a stun's white flash is the Lighting domain's flash
     light, interface 20) and `ExplosionSmoke`, which draw themselves in stepped
     pixel rows and free themselves (Despawner-tracked), and a frag's scorch mark in the world's `ScorchDecals` layer (batched like `BloodDecals`,
     capped by `Despawner.max_scene_objects`). Looks and timings are `PhysicsExplosionConfig.looks`; `PhysicsExplosionConfig.fx_enabled` off
     spawns none of it. `Ragdoll.wake()` restarts a sleeping body's clocks so an explosion's push is simulated (the character's `blast_push`).
   - `PhysicsDeformConfig` (`class_name` static holder, `tuning-holders.md`) — the deformation tuning
	 (`depth_per_damage`, `max_depth`, `chunk_damage`, `max_impacts`, `update_collider`) that Objects reads
	 directly when recording damage; `PhysicsRagdollConfig` (static holder) — the ragdoll solver's tuning
	 (read only by `Ragdoll` itself).
   Physics imports nothing from other domains but General's infrastructure (`Despawner` for debris, hit particles, blood and
   the explosion effects, `PhysicsLayers` for `PhysicsConfig.wall_mask`, `DrawLayers` for its z knobs, `FillBatch` for its many
   plain-coloured shapes).
