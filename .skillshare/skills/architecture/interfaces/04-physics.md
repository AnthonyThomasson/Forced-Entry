4. **Objects/Character/Vehicles → Physics** (they compose it; Physics is a leaf domain)
   - `Knockback` (Node child): RigidBody2D adapter. Configures its parent body, owns `apply_impulse(v, at_world)`; `mass` is set by the
	 owner from the catalogue `weight` before `_ready`.
   - `Deformable` (Node child): `record(hit, turn = 0.0)` (`turn`: the body's drawn turn beyond its node rotation; the character
	 passes its facing), `impacts`, `damage_total`, signal `changed`, and three per-body knobs its owner sets: `max_depth` (deepest
	 dent, px; default `PhysicsDeformConfig.max_depth`), `allow_chunks` (a hard hit carves a missing piece), `max_impacts` (dents
	 remembered), each defaulting to `PhysicsDeformConfig`'s (the character sets softer flesh values from `CharacterHitConfig`). A vehicle composes one with chunks off,
	 no `Knockback` (it is its own `RigidBody2D`), and does not rebuild its collider from the dents.
   - `Deformation` (static): silhouette/collider polygons and drawing.
	 - Draw: `draw_shape(canvas, shape, size, impacts, look: ShapeLook)` and `draw_wall(canvas, a, b, impacts, look: WallLook)`.
	   `ShapeLook` (`physics/shape_look.gd`): `fill`, `outline`, `damage_total`, `crack_color` / `hole_color` / `scorch_color`, `texture`,
	   `texture_angle`, `marks` (false: the caller draws the hit marks later with `draw_marks`). `WallLook` (`physics/wall_look.gd`):
	   `thickness`, `color`, `texture`, `tile_length`. Pixel art is drawn through the dented silhouette. `NO_COLOR` = take the call's
	   default colour.
	 - Polygons: `base_ring(shape, size)`, `shape_polygon(shape, size, impacts)` (cached), `wall_polygon(a, b, thickness, impacts)`,
	   `is_valid_polygon(poly)` (skip a self-touching one that frame), `convex_pieces(polygon)`, `shapes_of(pieces)` (their
	   `ConvexPolygonShape2D`s), `cut_shape(shape, size, impacts)` / `cut_wall(a, b, thickness, impacts)` -> `[polygon, pieces]`
	   (uncached and pure: safe on a worker thread), `drawable_polygon(shape, size, impacts)` (what `draw_shape` draws: the dented
	   silhouette, or the undented ring when the dents pinched it) and `texture_uvs(poly, size, angle)`.
	 - Impacts: built by `new_impact(pos, inward, damage, blood, dent: DentLimits)` (`physics/dent_limits.gd`: `max_depth`,
	   `allow_chunks`, `rng`: the world's `WorldRng.of`, the dent's seed) and kept by `push_impact(list, impact, max_impacts)` (oldest dropped); `Deformable.record` and Objects' wall (one
	   list per segment) both build through them.
	 - `darken(damage_total) -> float`: `Color.darkened`'s weight for a shape with that damage (a textured shape is white darkened by it),
	   for a caller drawing a textured polygon its own way (the character's kept meshes, `domain-character` (`body.md`)).
   - `Debris.toss(node, dir, distance, time, spin) -> Tween` (`physics/debris.gd`, preloaded as `Debris`, no `class_name`): a thrown chip's
	 toss; the Projectile System's spent casing uses it too.
   - `Physics.impact_impulse(hit) -> Vector2`, `Physics.spawn_debris(world, hit, surface)`: objects, the character and a vehicle.
   - Blood (a character on a hit, a dead body, a footfall, a slid puddle):
	 - `BloodWound` (Node child, character): `record(hit)` throws a splatter spray and owes drips (paced by
	   `BloodDripConfig.interval_min..max`); `stop()` on death.
	 - `Physics.bleed_out(parent, source, exclude)`: a dead character, once at rest: one slow, wide pool. A blood source may expose
	   `blood_origin() -> Vector2` (world space); pools emerge there, so a fallen body bleeds from where it lies.
	 - `BloodDecals.layer(parent)`: the batched decal layer under a world node.
	 - `BloodFootprints` (Node child, character): `step(foot, fall: Footfall)` on each footfall prints a sole if the foot carries wet blood
	   (`Footfall`, `physics/blood/footfall.gd`: `at`, `direction`, `length`, `width`, `inner`, `speed`).
	 - `BloodSmear` (Node child, objects): `set_footprint(local_polygon)`, then drags blood out of a puddle as ribbons while the body slides.
	 - `BloodSurface` (static): `register(rect, groove: Callable(world, half_width) -> 0..1, porous) -> id` / `unregister(id)`.
	   Objects' `Floor` registers its room so a bleed-out flow runs along grout/seams; rugs register porous (blood
	   sinks in).
	 - Switches: `BloodConfig.enabled` off → `BloodWound.record` and `bleed_out` spawn nothing (`bleed_out` returns null); footprints and
	   smears need it plus their own (`BloodPrintConfig.footprints_enabled`, `BloodSmearConfig.enabled`); `BloodSurfaceConfig.flow` off
	   ignores floors; `PhysicsConfig.debris_enabled` off → `spawn_debris` throws no chips (its particle bursts follow
	   `PhysicsConfig.hit_particles_enabled`).
   - `Ragdoll` (`RefCounted`, character on death): a generic 3D point-mass body over the floor plane (x/y + height z). Build with
	 `add_point(at, radius, mass)`, `add_bone(a, b)`, `add_rigid(indices)`, `add_frame(origin, up, right, forward_hint)`,
	 `add_swing(frame, joint, child, rest, limits)` (cone limit), `add_hinge(frame, parent, joint, child, limits: HingeLimits)` (one-way
	 hinge; `physics/hinge_limits.gd`: `rest`, `bend`, `min_angle`, `max_angle`, `slack`); seed with `push(i, v)`; `step(delta, space,
	 origin)` until `asleep`; read `point(i)` / `point_count()` / `frame_basis(f)`; `exclude` lists colliders its wall sweep ignores.
	 `Ragdoll.wake()` restarts a sleeping body's clocks so an explosion's push is simulated (the character's `blast_push`). The Character
	 domain owns the humanoid skeleton built on it.
   - `Physics.spawn_explosion(world, at, kind)` (`kind` `&"frag"` / `&"stun"`; called by `Explosion`): the look of a burst — nodes
	 `ExplosionFlash`, `ExplosionFireball` (frag only: a stun's white flash is the Lighting domain's flash light, interface 20) and
	 `ExplosionSmoke`, which free themselves (Despawner-tracked), and a frag's scorch in the world's `ScorchDecals` layer (capped by
	 `Despawner.max_scene_objects`). Looks and timings: `PhysicsExplosionConfig.looks`; `PhysicsExplosionConfig.fx_enabled` off spawns
	 none.
   - Tuning read across the boundary: `PhysicsDeformConfig` (`depth_per_damage`, `max_depth`, `chunk_damage`, `max_impacts`,
	 `update_collider`; Objects reads it when recording damage; `circle_points`, the round silhouette's ring size, which Character's
	 `BodyDrawCache` keys its kept silhouettes and uvs on; holders: `tuning-holders.md`).

   Physics imports nothing from other domains but General's infrastructure: `Despawner` (debris, hit particles, blood, explosion fx),
   `PhysicsLayers` (`PhysicsConfig.wall_mask`), `DrawLayers` (its z knobs), `FillBatch`.
