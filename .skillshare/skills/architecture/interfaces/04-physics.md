4. **Objects/Character/Vehicles → Physics** (they compose it; Physics is a leaf domain but for Art's mesh kit, 3D only)
   - `Knockback` (Node child): RigidBody2D adapter. Configures its parent body, owns `apply_impulse(v, at_world)`; `mass` is set by the
	 owner from the catalogue `weight` before `_ready`.
   - `Deformable` (Node child): `record(hit, turn = 0.0)` (`turn`: the body's drawn turn beyond its node rotation; the character
	 passes its facing), `impacts`, `damage_total`, signal `changed`, and three per-body knobs its owner sets: `max_depth` (deepest
	 dent, px; default `PhysicsDeformConfig.max_depth`), `allow_chunks` (a hard hit carves a missing piece), `max_impacts` (dents
	 remembered), each defaulting to `PhysicsDeformConfig`'s (the character sets softer flesh values from `CharacterHitConfig`). A vehicle composes one with chunks off,
	 no `Knockback` (it is its own `RigidBody2D`), and does not rebuild its collider from the dents.
   - `Deformation` (static): silhouette/collider polygons and the damage darkening (`darken(damage_total)`).
	 - Polygons: `base_ring(shape, size)`, `shape_polygon(shape, size, impacts)` (cached), `wall_polygon(a, b, thickness, impacts)`,
	   `is_valid_polygon(poly)` (skip a self-touching one that frame), `convex_pieces(polygon)`, `shapes_of(pieces)` (their
	   `ConvexPolygonShape2D`s), `cut_shape(shape, size, impacts)` / `cut_wall(a, b, thickness, impacts)` -> `[polygon, pieces]`
	   (uncached and pure: safe on a worker thread).
	 - Impacts: built by `new_impact(pos, inward, damage, blood, dent: DentLimits)` (`physics/dent_limits.gd`: `max_depth`,
	   `allow_chunks`, `rng`: the world's `WorldRng.of`, the dent's seed) and kept by `push_impact(list, impact, max_impacts)` (oldest dropped); `Deformable.record` and Objects' wall (one
	   list per segment) both build through them.
	 - `darken(damage_total) -> float`: `Color.darkened`'s weight for a shape with that damage (a textured shape is white darkened by it),
	   for a caller drawing a textured polygon its own way (the character's kept meshes, `domain-character` (`body.md`)).
   - `Debris.toss(node, dir, distance, time, spin) -> Tween` (`physics/debris.gd`, preloaded as `Debris`, no `class_name`): a thrown chip's
	 toss; the Projectile System's spent casing uses it too.
   - `Physics.impact_impulse(hit) -> Vector2`, `Physics.spawn_debris(world, hit, surface)`: objects, the character and a vehicle. `HitParticles.spawn(hit, surface, kind, strength) -> Dictionary` makes a particle burst as plain data, told to the 3D render (`PhysicsFxHook.burst_made`); nothing is drawn by Physics itself.
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
	 hinge; `physics/hinge_limits.gd`: `rest`, `bend`, `min_angle`, `max_angle`, `slack`); seed with `push(i, v)`; `step(delta, space: PhysicsDirectSpaceState3D,
	 origin)` (the twin 3D space, interface 29: null finds nothing solid) until `asleep`; read `point(i)` / `point_count()` / `frame_basis(f)`; `exclude` lists the 3D colliders its sweeps ignore;
	 `height_scale` is how many real px a unit of a point's z is (the owner's drawing may be taller than the body): each point is a sphere swept at `z * height_scale` through
	 `PhysicsConfig.twin_mask` (walls, floors, furniture, doors, vehicles: not people, not a roof), so a body slumps over what is lower than it is and rests on a top that faces up.
	 `Ragdoll.wake()` restarts a sleeping body's clocks so an explosion's push is simulated (the character's `blast_push`). The Character
	 domain owns the humanoid skeleton built on it.
   - `Physics.spawn_explosion(world, at, kind)` (`kind` `&"frag"` / `&"stun"`; called by `Explosion`): the look of a burst: it tells the 3D render a
	 flash, a fireball (frag only: a stun's white flash is the Lighting domain's flash light, interface 20) and smoke (`PhysicsFxHook.blast_made`), and
	 marks a frag's scorch in the world's `ScorchDecals` layer (capped by `Despawner.max_scene_objects`). Looks and timings:
	 `PhysicsExplosionConfig.looks`; `PhysicsExplosionConfig.fx_enabled` off does none of it.
   - Tuning read across the boundary: `PhysicsDeformConfig` (`depth_per_damage`, `max_depth`, `chunk_damage`, `max_impacts`,
	 `update_collider`; Objects reads it when recording damage; `circle_points`, the round silhouette's ring size; holders: `tuning-holders.md`).

   Physics imports nothing from other domains but General's infrastructure: `Despawner` (debris, the mark layers),
   `PhysicsLayers` (`PhysicsConfig.wall_mask`), `ViewLayers`, `SeenArea`; and, for the 3D render (27), Art's mesh kit (12).
   - `PhysicsMeshes.install(mirror: WorldMirror, ground := Callable()) -> FxLayer` (Main's `View3D`, once, before the match makes anything): the 3D look of everything above
     (`domain-physics/meshes.md`). The spawners tell it through `PhysicsFxHook` (static, a no-op when none is installed); `spawn_debris` sets `PhysicsFxHook.hit_height`.
     `ground` is `func(at: Vector2) -> float`, the height offset (px, 0 on the pavement, a kerb lower on the road) of the ground under a world point: Main builds it
     from the street (Objects' `StreetGround.offset_at`) so Physics imports nothing of Objects; every mark, chip, bit and blast lies on it; none is a flat ground.
     The sink is process-wide (`PhysicsFxHook.sink`): one 3D view at a time, the last installed wins.
