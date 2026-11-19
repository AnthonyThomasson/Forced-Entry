---
name: domain-physics
description: Use when editing scenes/physics/ or working on HitInfo, knockback, deformation, debris, hit particles, the ragdoll solver, an explosion's look, or Physics tuning. Blood: `blood.md`; 3D: `meshes.md`.
---

# Physics System domain (`scenes/physics/`)

A leaf of stateless helpers and reusable Node components. Objects, the character and a vehicle *compose* them. Physics imports
only General's infrastructure (`Despawner`, `PhysicsLayers`, `ViewLayers`, `SeenArea`), and, for the 3D render only, Art's mesh kit (`scenes/physics/mesh/`: `meshes.md`). Interfaces: 3 (`HitInfo`), 4 (Objects /
Character / Vehicles → Physics; `PhysicsMeshes`), 12 and 27 (the 3D meshes), 5 (`Knockback` and the pushable bodies), 11 (`PhysicsLayers` in `PhysicsConfig.wall_mask`), 13 (the switches `physics.debris`,
`physics.hit_particles`, and blood's). Tests: `tests/physics/`. Blood (`scenes/physics/blood/`, its `Blood*Config` holders) is
`blood.md`; the core keeps only its entry points, `Physics.spawn_debris` and `Physics.bleed_out`.

## Files

| File | Role |
|---|---|
| `physics.gd` (`Physics`) | The entry points `impact_impulse`, `spawn_debris`, `bleed_out`, `spawn_explosion`. |
| `hit_info.gd` (`HitInfo`) | The one packet a striker fills in. |
| `knockback.gd` (`Knockback`) | RigidBody2D adapter for furniture; the static `Knockback.push(body, impulse, at, height)` is the one way a pusher shoves a pushable (5): through the free 3D body that leads a piece (`TwinSpace.leader_of`, interface 29) at its real height, else `apply_impulse`. |
| `deformable.gd`, `deformation.gd`, `dent_limits.gd` | Dents: records, polygon math and the damage darkening. |
| `debris_spawner.gd`, `debris.gd`, `debris_layer.gd`, `mark_layer.gd` | Chips (a flying one is a plain node, a landed one a record) and the capped mark store. |
| `hit_particles.gd` (`HitParticles`) | Entry, exit and impact bursts, made as plain data. |
| `ragdoll.gd`, `hinge_limits.gd` | The generic 3D ragdoll solver. |
| `explosion_fx.gd`, `scorch_decals.gd` | A grenade burst's look: the blast told to the 3D render and the scorch mark. |
| `mesh/` (`PhysicsMeshes`, `FxLayer`, `PhysicsFxHook`, `*_fx.gd`) | The 3D render of the chips, hit particles, blood and explosions: `meshes.md`. |
| `physics_config.gd`, `physics_impact_config.gd`, `physics_deform_config.gd`, `physics_deform_look_config.gd`, `physics_ragdoll_config.gd`, `physics_explosion_config.gd` | Tuning. `PhysicsConfig`: `debris_enabled`, `hit_particles_enabled`, `hit_particles_scale`, `hit_particles_max`, `wall_mask` (the layer the ragdoll sweep and blood queries treat as blocking). `PhysicsImpactConfig`: a hit's shove and the furniture body's damping; `PhysicsDeformConfig`: the dents' shape; `PhysicsDeformLookConfig`: how they are drawn; `PhysicsRagdollConfig`: the solver; `PhysicsExplosionConfig`: a burst's look. |

## HitInfo, Knockback

- `HitInfo.height` is how high the striker met the object, px above the floor (a bullet's height at the contact, which picks a character's hit zone by `BodyHeights.zones`); −1 is
  none (the default, and a frag's blast: the whole body). `spray_direction()` (the normal, or back along the shot when degenerate)
  is what debris, hit particles and `BloodWound` spray along.
- `Knockback` configures its parent furniture body (no gravity, mass, `PhysicsImpactConfig.body_*` damping, origin-pinned centre
  of mass, contact reporting) and feeds it impulses; off the centre the body pivots under its own torque. The engine does the
  sweeping and settling; the component only hands momentum to a kinematic character on contact (`transfer_scale`).

## Deformation

- `Deformable` records impacts (dents, carved "missing pieces") and emits `changed`; the owner shows it and rebuilds its collider
  from the same deformed polygon. `record(hit, turn)` stores the impact un-turned by `turn`, for a body shown turned beyond its
  node rotation (a character facing its aim); the owner turns it back when reading it. A vehicle composes one with `allow_chunks` off
  and its own `max_depth` / `max_impacts`, does not listen to `changed` (it leaves its collider alone), has no `Knockback` (it is a
  `RigidBody2D`), and its meshes read the dents (`hit_marks()`). A house door's leaf composes one the same way (a child of the door, so impacts are
  stored in the leaf's frame; `max_depth` `DoorConfig.dent_depth`, `max_impacts` `DoorConfig.dents`), and its debris is `Physics.spawn_debris`.
- `Deformation` owns the impact schema (`new_impact`, `push_impact`); `Deformable.record` and Objects' wall segments both record
  through them. `deform` keeps each ring point inside the outline and at most `NEIGHBOUR_REACH` of the way to either ring
  neighbour, so a corner dented from one face cannot fold the ring (`tests/physics/deformation_outline_suite.gd`).
- Caches: `shape_polygon` and `wall_polygon` keep up to 256 dented silhouettes (cleared when full), keyed by everything they are
  made from; one hit asks three times (collider, shadow, mesh) and a wounded character's mesh asks again
  (`tests/physics/shape_polygon_cache_test.gd`).
- `convex_pieces` cuts a silhouette into convex collider pieces (Hertel-Mehlhorn); `tests/physics/convex_pieces_match_plain_scan_test.gd`
  pins its pruned scan to the plain every-pair scan. `cut_shape` / `cut_wall` are pure (no caches, a circle's unit ring made
  afresh) because Objects' `ColliderCuts` runs them on worker threads; `shapes_of` makes the shapes on the main thread.
- The damage darkening (`Deformation.darken`, `PhysicsDeformLookConfig.darken_max` / `darken_full`) is read by the furniture
  rig and the character's meshes. A bloody hit (`HitInfo.blood > 0`) stores `"blood"` in the impact; the red blot a mesh shows
  under the hole is `PhysicsDeformLookConfig.blood_mark_color`; `hit_marks()` on an `EnvironmentObject`,
  `Wall` or vehicle returns the marks.

## Debris

- `Debris` is `debris.gd` with no `class_name` (preloaded); its static `toss(node, dir, distance, time, spin)` is the chip's
  throw, which the Projectile's casing uses too (interface 4).
- A chip is a node only while it flies (`Despawner`-tracked, no drawing: the 3D render follows it, `PhysicsFxHook.chip_flew`); on
  landing it hands its place, turn, colour, size and shape to the parent's `DebrisLayer` and frees itself, so a thousand chips cost
  no nodes. The layer keeps at most `Despawner.max_scene_objects` chips.
- Tests: `debris_rests_in_a_layer_test.gd`.
- `mark_layer.gd` (no `class_name`; `DebrisLayer`, `ScorchDecals` and the blood's `BloodDecals` extend it by path) is the capped mark
  store: marks as plain data in one node under a world node, a global oldest-first FIFO (`_add`; the oldest is flagged `dead`). It draws
  nothing. Its advancing-head FIFO makes capped eviction amortized O(1); `items()` returns a copy that is the caller's own
  (`mark_layer_evicts_oldest_test.gd`). Its typed `layer(parent)` wraps `_get_or_make`; `find(parent)` only looks up.

## Hit particles

`HitParticles.spawn(hit, surface, kind, strength)` makes a burst as a plain dict (`at`, `direction`, `amount`, `spread`, speeds, damping,
sizes, `life`, `color`, `spark`, `height`: see the function), styled by `surface.material` from its `STYLES`, and tells the 3D render
(`PhysicsFxHook.burst_made`); no node. A round that passes through (`has_exit`) gets a strong `Kind.EXIT` and a weak `Kind.ENTRY`; a
hit that stays (blocked, ricochet, no exit found) gets one `Kind.IMPACT` at exit strength, back along the normal. `Physics.spawn_debris`
(which every `take_hit` calls) fires them and the chips; a blood-carrying hit adds red droplets and `flesh` chips. Tests read the
bursts through `tests/_physics/fx_tap.gd`.

## Ragdoll (`ragdoll.gd`, `class_name Ragdoll`, `RefCounted`)

Generic: it knows nothing of the body; the owner (the Character domain's humanoid) builds and steps it. Space is the owner's
local floor plane (x, y) plus z = height; gravity pulls to z = 0.

- Position-based dynamics in `PhysicsRagdollConfig.substeps`: predict, then `iterations` passes of bones, limits and the floor, then one
  rectangle broadphase over every point's start, predicted end and radius skips all per-point wall sweeps when clear; otherwise each
  point's x/y move still uses `cast_motion`. The retained `StepScratch` owns the predict/free arrays, query and shape reuse
  (`ragdoll_sweep_gate_matches_plain_test.gd` pins real humanoid falls). Limits correct `LIMIT_STIFFNESS` of the
  error per pass, turning a bone at most `LIMIT_MAX_TURN`. The constraint solve can add no more than `max_push` to a point's
  speed (never past `max_speed`), so constraints fighting the floor cannot fling the body. The first step pulls a point that
  starts inside a wall back toward the origin.
- `add_hinge` takes `HingeLimits` (`hinge_limits.gd`): a one-way hinge, its bend side carried onto the live parent bone.
- It sleeps once every point stays under `sleep_speed` for `sleep_time`, or after `max_time`. `wake()` clears `asleep` and both
  clocks (`_time`, `_still`); without that, a body that slept through `max_time` goes straight back to sleep after one step of an
  explosion's push. `CharacterRagdoll.blast` calls it (`tests/physics/frag_blast_pushes_test.gd`).
- `Ragdoll.steps_total` counts the steps run (a sleeping body's not), a running total a perf probe reads for the worst-frames report.

## Explosion look

`Physics.spawn_explosion(world, at, kind)` (`&"frag"` / `&"stun"`; Projectile's `Explosion` calls it) tells the 3D render the blast
(`PhysicsFxHook.blast_made(at, look)`: a flash, a fireball puff and drifting smoke for a frag, thin smoke for a stun: its white flash is the
Lighting domain's flash light, `docs/lighting.md` L9). A frag also burns a mark into `ScorchDecals`
(`ScorchDecals.layer(world).burn(at, radius)`), kept up to `Despawner.max_scene_objects`; a stun leaves none. Tuning:
`PhysicsExplosionConfig.looks` (a row per kind), `pixel`, the fireball's `fire_*` colours and `lobes`, `scorch_color`; `fx_enabled` is the
master switch. Test: `tests/physics/explosion_fx_test.gd`.
