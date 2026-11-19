# Physics in the 3D render (`scenes/physics/mesh/`)

The sim stays 2D; in the 3D render (interface 27) Physics' effects are shown by one layer, `FxLayer` (a `Node3D` under the
`WorldMirror`), that Main's `View3D.begin()` installs: `PhysicsMeshes.install(mirror, ground := Callable()) -> FxLayer` (interfaces 4, 12). The 2D spawners
call static hooks on `PhysicsFxHook` as they make a thing (`chip_flew`, `chip_landed`, `burst_made`, `splat_made`, `print_made`,
`ribbon_begun`, `ribbon_grew`, `scorch_burned`, `pool_made`, `pool_changed`, `blast_made`); with no layer installed (2D, a test world)
each is one `is_instance_valid(sink)` check. The 2D nodes are still made (hidden in 3D), and their configs are read again, not copied:
same colours, sizes, counts, lifetimes and caps. Imports: General and Art's mesh kit (`MeshNodes`, `MeshKit`, `MeshCache`, `MeshPool`).

## Files

| File | Role |
|---|---|
| `fx_world.gd` | What the effects share: `ground_at(point)` (the `ground` Callable Main gave, 0 when none) and `rng`, a private `RandomNumberGenerator` (the 3D look never draws from global `randf`, so a seeded 2D sim is the same in either mode). |
| `physics_meshes.gd`, `physics_fx_hook.gd`, `fx_layer.gd` | The install, the hooks, the layer: it runs `_process` only while a chip flies, bits move, a pool soaks or a blast burns; at rest nothing runs or is written. |
| `fx_batch.gd`, `fx_piece.gd`, `piece_queue.gd` | A `MeshNodes.batch` with a colour per part (`colored`, `batch_color`), a free list of preallocated pieces (no allocation in play), a FIFO. |
| `debris_fx.gd` | Chips: a flying chip follows its node (place, turn and `Debris.altitude()`: it flies in the twin 3D space), lands where its node rests, at the altitude it rests at (the floor, or a piece's top); lying chips capped by `Despawner.max_scene_objects`. |
| `burst_fx.gd` | Hit particles: bits and sparks (glowing, `MeshNodes.glow`, no light) from the burst dict `HitParticles.spawn` makes (amount, cone, speeds, damping, sizes, life, colour); gravity, floor, shrink out. |
| `ink_fx.gd`, `ink_chunk.gd`, `ink_mark.gd` | Flat marks on the floor in 128 px chunks, one `ArrayMesh` per chunk rebuilt once a frame when dirty: splats, prints, smear ribbons, scorch. |
| `pool_ink.gd` | A bleed-out pool: a decal of `BloodPoolField.field_bytes` (one shared unit quad, scaled to its box), bilinear-upscaled, in rim / deep / soaked tones. At most one stale pool is built a frame, in turn, each at most every `pool_interval`. |
| `blast_fx.gd`, `blast_rig.gd` | An explosion: `PhysicsBlastMeshConfig.rigs` reusable rigs: flash discs, shock ring, a flattened fireball dome (`fire_squash`, `fire_body`, alpha capped at `fire_opacity` so it dithers early; it hides a character no more than the 2D disc), smoke puffs resting on the ground, each a flat disc (`smoke_squash` as tall as it is wide) wearing the 2D puff (a round body and a lighter patch, painted once per smoke colour, `BlastRig._puff_texture`, cut out), at most `smoke_alpha` whole by the dither (the 2D's translucency) and thinning over the last `SMOKE_THIN` of its life. |
| `physics_mesh_config.gd`, `physics_ink_config.gd`, `physics_blast_config.gd` | Tuning only the 3D has: heights, lifts, capacities, steps, rigs. |

## Rules

- **Stepped tones, no blending.** Blood and scorch are opaque flat triangles (a faint print or the scorch's rim is its alpha, rounded to
  `alpha_steps`, laid over `ground_tone`); blood dries in `dry_steps` tone steps; the fireball cools in `fire_steps`; a fade is
  `MeshNodes.fade`'s dither in `fade_levels` steps. A part is written only when its step changes.
- **Heights** (px over the ground): chips and bits rest at `rest_height` 2.1; blood and scorch take the shared decal layer rule
  (`MeshNodes.decal`, `decal_layer_step`): pool 5, splat 5.8, print 6.6, scorch 7.4 (`PhysicsInkConfig`, over Objects' wear, whose top
  is under layer 5, and over a rug; `InkFx.lift_of(layer)`); a hit's height is real px (`height_scale` 1); a flash 6, its ring 4.
- **Bounds.** Chips `cap + flying_room`, bits `bit_capacity`, sparks `spark_capacity`, prints `BloodConfig.print_max`, scorch and splats
  `Despawner.max_scene_objects`; a full pool shows what fits. A splat lives as long as its node.
- A glowing part has base colour black: the toon shader's highlight term adds `(1 - ALBEDO)`, so it shows as lighter patches.

## Tests

`tests/physics/`: `debris_mesh_test`, `hit_particles_mesh_test`, `blood_mesh_test`, `blood_pool_mesh_test`, `explosion_mesh_test`
(headless: place, height, life, expiry, bounds, nothing written at rest), `fx_ground_mesh_test` (the road a kerb lower), `blood_pools_turns_mesh_test`
(one pool a frame), `blood_ribbon_mesh_test`, `fx_own_random_test`; `physics_mesh_windowed_test` (windowed; `PHYSICS_SHOTS=<dir>` saves a firefight,
a road firefight and blast, bleeding and a blast at zoom 3 and 1).

## Known limits

Smears lose their feathered edge; pool soak tufts are one tone. A chip
lags its 2D node by a frame, and one past `flying_room` is shown from where it lands. Debris and bits are 2D-sized, so sub-pixel at zoom 1.
Object dents and the bloody mark under a hole are Objects' and Vehicles' meshes. The shock ring is 3D only.
