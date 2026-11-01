---
name: domain-physics
description: Use when editing scenes/physics/ or working on HitInfo, knockback, deformation, debris, hit particles, the ragdoll solver, an explosion's look, or Physics tuning. Blood is `blood.md`.
---

# Physics System domain (`scenes/physics/`)

A leaf of stateless helpers and reusable Node components. Objects, the character and a vehicle *compose* them. Physics imports
only General's infrastructure (`Despawner`, `PhysicsLayers`, `DrawLayers`, `FillBatch`). Interfaces: 3 (`HitInfo`), 4 (Objects /
Character / Vehicles → Physics), 5 (`Knockback` and the pushable bodies), 11 (`PhysicsLayers` in `PhysicsConfig.wall_mask`;
`DrawLayers` for blood and scorch `BLOOD` and `ExplosionFx.Z_INDEX` = `EFFECTS`; `FillBatch`), 13 (the switches `physics.debris`,
`physics.hit_particles`, and blood's). Tests: `tests/physics/`. Blood (`scenes/physics/blood/`, its `Blood*Config` holders) is
`blood.md`; the core keeps only its entry points, `Physics.spawn_debris` and `Physics.bleed_out`.

## Files

| File | Role |
|---|---|
| `physics.gd` (`Physics`) | The entry points `impact_impulse`, `spawn_debris`, `bleed_out`, `spawn_explosion`. |
| `hit_info.gd` (`HitInfo`) | The one packet a striker fills in. |
| `knockback.gd` (`Knockback`) | RigidBody2D adapter for furniture. |
| `deformable.gd`, `deformation.gd`, `dent_limits.gd`, `shape_look.gd`, `wall_look.gd` | Dents: records, polygon math and drawing. |
| `debris_spawner.gd`, `debris.gd`, `debris_layer.gd`, `debris_visuals.gd`, `chunked_layer.gd` | Chips and the batched decal store. |
| `hit_particles.gd` (`HitParticles`) | Entry, exit and impact bursts. |
| `ragdoll.gd`, `hinge_limits.gd` | The generic 3D ragdoll solver. |
| `explosion_fx.gd`, `scorch_decals.gd` | A grenade burst's look. |
| `physics_config.gd`, `physics_impact_config.gd`, `physics_deform_config.gd`, `physics_deform_look_config.gd`, `physics_ragdoll_config.gd`, `physics_explosion_config.gd` | Tuning. `PhysicsConfig`: `debris_enabled`, `hit_particles_enabled`, `hit_particles_scale`, `hit_particles_max`, `wall_mask` (the layer the ragdoll sweep and blood queries treat as blocking). `PhysicsImpactConfig`: a hit's shove and the furniture body's damping; `PhysicsDeformConfig`: the dents' shape; `PhysicsDeformLookConfig`: how they are drawn; `PhysicsRagdollConfig`: the solver; `PhysicsExplosionConfig`: a burst's look. |

## HitInfo, Knockback

- `HitInfo.height` is the 0..100 height the striker flew at (a bullet's one height, which picks a character's hit zone); −1 is
  none (the default, and a frag's blast: the whole body). `spray_direction()` (the normal, or back along the shot when degenerate)
  is what debris, hit particles and `BloodWound` spray along.
- `Knockback` configures its parent furniture body (no gravity, mass, `PhysicsImpactConfig.body_*` damping, origin-pinned centre
  of mass, contact reporting) and feeds it impulses; off the centre the body pivots under its own torque. The engine does the
  sweeping and settling; the component only hands momentum to a kinematic character on contact (`transfer_scale`).

## Deformation

- `Deformable` records impacts (dents, carved "missing pieces") and emits `changed`; the owner redraws and rebuilds its collider
  from the same deformed polygon. `record(hit, turn)` stores the impact un-turned by `turn`, for a body drawn turned beyond its
  node rotation (a character facing its aim); the owner turns it back when drawing. A vehicle composes one with `allow_chunks` off
  and its own `max_depth` / `max_impacts`, does not listen to `changed` (it leaves its collider alone), has no `Knockback` (it is a
  `RigidBody2D`), and draws its dents with `Deformation.draw_marks`. A house door's leaf composes one the same way (a child of its visuals, so impacts are
  stored in the leaf's frame; `max_depth` `DoorConfig.dent_depth`, `max_impacts` `DoorConfig.dents`), and its debris is `Physics.spawn_debris`.
- `Deformation` owns the impact schema (`new_impact`, `push_impact`); `Deformable.record` and Objects' wall segments both record
  through them. `deform` keeps each ring point inside the outline and at most `NEIGHBOUR_REACH` of the way to either ring
  neighbour, so a corner dented from one face cannot fold the ring (`tests/physics/deformation_outline_suite.gd`).
- Caches: `shape_polygon` and `wall_polygon` keep up to 256 dented silhouettes (cleared when full), keyed by everything they are
  made from; one hit asks three times (collider, shadow, drawing) and every repaint of a wounded character asks again
  (`tests/physics/shape_polygon_cache_test.gd`). `draw_wall` and `draw_shape` skip the triangulation check for an undented
  outline.
- `convex_pieces` cuts a silhouette into convex collider pieces (Hertel-Mehlhorn); `tests/physics/convex_pieces_match_plain_scan_test.gd`
  pins its pruned scan to the plain every-pair scan. `cut_shape` / `cut_wall` are pure (no caches, a circle's unit ring made
  afresh) because Objects' `ColliderCuts` runs them on worker threads; `shapes_of` makes the shapes on the main thread.
- `drawable_polygon` (falls back to the intact ring when dents break the polygon) and `texture_uvs` are shared with the
  character's kept meshes, as is the damage darkening (`PhysicsDeformLookConfig.darken_max` / `darken_full`).
- `draw_marks` batches each mark's discs as one `FillBatch` before its cracks, so a later mark's discs cover an earlier mark's
  cracks. `ShapeLook` (with an optional `texture`; `texture_angle` turns the image within the unturned silhouette; `marks` false
  leaves the marks to the caller's `draw_marks`) and `WallLook` (a repeating `texture` + `tile_length`, UVs in the segment's own
  frame) carry the look.
- A bloody hit (`HitInfo.blood > 0`) stores `"blood"` in the impact; `draw_marks` draws a red blot under the hole
  (`PhysicsDeformLookConfig.blood_mark_color` / `blood_mark_radius`); `hit_marks()` on an `EnvironmentObject`, `Wall` or vehicle returns the marks.

## Debris

- `Debris` is `debris.gd` with no `class_name` (preloaded); its static `toss(node, dir, distance, time, spin)` is the chip's
  throw, which the Projectile's casing uses too (interface 4).
- A chip is a node only while it flies (`Despawner`-tracked); on landing it hands its place, turn, colour, size and shape to the
  parent's `DebrisLayer` and frees itself, so a thousand chips cost a few draw calls and no nodes. A chunk holds chips in pages
  of `PAGE` (32), each a canvas item (`DebrisPage`) drawn as one `FillBatch`; a landing repaints only the last page, a drop only
  the first. The flying chip (`debris_visuals.gd`) draws the same `DebrisLayer.tri`, so a chip lands looking as it flew.
  `DebrisLayer.paged` off draws each chunk in one batch (for tests); `chips_drawn` counts chips painted. The layer keeps at most
  `Despawner.max_scene_objects` chips.
- A page is lit as its own item: where more than 15 lights reach a chunk (`docs/lighting.md` L4) a page can keep a light the whole
  chunk's draw dropped.
- Tests: `debris_rests_in_a_layer_test.gd`, `debris_pages_repaint_one_page_test.gd`, and, windowed, `debris_pages_match_one_batch_test.gd`.
- `chunked_layer.gd` (no `class_name`; `DebrisLayer`, `ScorchDecals` and the blood's `BloodDecals` extend it by path) is the
  batched decal store: marks as plain data in one node under a world node, in 128 px chunks (`CHUNK`), a capped FIFO (`_add`).
  A layer names its recipe, cap and chunk draw (`_make_chunk`), and may override `_mark_added` / `_mark_dropped` (default: redraw
  that chunk alone; `DebrisLayer` repaints a page). Its typed `layer(parent)` wraps `_get_or_make`; `find(parent)` only looks up.

## Hit particles

`HitParticles.spawn` bursts a one-shot `CPUParticles2D` (`Despawner`-tracked, no gravity: top-down) styled by `surface.material`
from its `STYLES`. A round that passes through (`has_exit`) gets a strong `Kind.EXIT` and a weak `Kind.ENTRY`; a hit that stays
(blocked, ricochet, no exit found) gets one `Kind.IMPACT` at exit strength, back along the normal. `Physics.spawn_debris` (which
every `take_hit` calls) fires them and the chips; a blood-carrying hit adds red droplets and `flesh` chips.

## Ragdoll (`ragdoll.gd`, `class_name Ragdoll`, `RefCounted`)

Generic: it knows nothing of the body; the owner (the Character domain's humanoid) builds and steps it. Space is the owner's
local floor plane (x, y) plus z = height; gravity pulls to z = 0.

- Position-based dynamics in `PhysicsRagdollConfig.substeps`: predict, then `iterations` passes of bones, limits and the floor,
  sweep each point's x/y move against layer 1 with `cast_motion`, derive velocities. Limits correct `LIMIT_STIFFNESS` of the
  error per pass, turning a bone at most `LIMIT_MAX_TURN`. The constraint solve can add no more than `max_push` to a point's
  speed (never past `max_speed`), so constraints fighting the floor cannot fling the body. The first step pulls a point that
  starts inside a wall back toward the origin.
- `add_hinge` takes `HingeLimits` (`hinge_limits.gd`): a one-way hinge, its bend side carried onto the live parent bone.
- It sleeps once every point stays under `sleep_speed` for `sleep_time`, or after `max_time`. `wake()` clears `asleep` and both
  clocks (`_time`, `_still`); without that, a body that slept through `max_time` goes straight back to sleep after one step of an
  explosion's push. `CharacterRagdoll.blast` calls it (`tests/physics/frag_blast_pushes_test.gd`).

## Explosion look

`Physics.spawn_explosion(world, at, kind)` (`&"frag"` / `&"stun"`; Projectile's `Explosion` calls it) spawns up to three
colliderless, `Despawner`-tracked nodes animated in `_process`: `ExplosionFlash` and `ExplosionFireball` (frag only) and
`ExplosionSmoke`. A stun's row has `flash_radius` 0: its white flash is the Lighting domain's flash light (`docs/lighting.md`
L9). All is stepped-pixel (`PhysicsExplosionConfig.pixel`, `ExplosionFx.disc_rows`), like the debris and the blood. A frag
also burns a mark into `ScorchDecals` (`ScorchDecals.layer(world).burn(at, radius)`) at `DrawLayers.BLOOD`, kept up to
`Despawner.max_scene_objects`; a stun leaves none. Tuning: `PhysicsExplosionConfig.looks` (a row per kind), `pixel`,
`scorch_color`; `fx_enabled` is the master switch. Test: `tests/physics/explosion_fx_test.gd`.
