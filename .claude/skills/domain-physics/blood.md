# Physics blood (`scenes/physics/blood/`)

Wound spray and drips, splats, a dead body's bleed-out pool and its floor-steered flow, and carried blood (wetness, footprints,
smears). Separate from debris and deformation: the rest of `physics/` reaches it only through
`Physics.spawn_debris` (a hit with `HitInfo.blood`; the bloody mark on an object is the core's `Deformation.draw_marks`) and
`Physics.bleed_out`; every other domain meets it through interface 4's classes. It imports only `Despawner`, `DrawLayers` and
`FillBatch` (General). Tests: `tests/physics/` (`blood_*`, `footprints_*`, `object_smear*`,
`smear_ribbon_shape`, `wound_*`, `death_*`).

## Files and tuning

| File | Role |
|---|---|
| `blood_wound.gd` (`BloodWound`) | Node the character composes like `Knockback`; its `take_hit` calls `record(hit)`. Spray and drips. |
| `blood_spawner.gd`, `blood_throw.gd` | Spawns each splat and pool with a readable name (`BloodSplat`, `BloodSplat2`, …, `BloodPool`); `BloodThrow` carries a splat's throw. |
| `blood_splat.gd`, `blood_pool.gd`, `blood_pool_visuals.gd`, `blood_flow.gd`, `blood_surface.gd` | A splat; a bleed-out pool, its flood-fill and the floor that steers it. |
| `blood_field.gd`, `blood_decals.gd`, `blood_footprints.gd`, `footfall.gd`, `blood_smear.gd` | Wetness queries, the batched print layer, a walker's prints, a body's smear. |
| `BloodConfig` plus `Blood{Drip,Spray,Splat,Pool,Surface,Print,Smear,SmearLook,Trail}Config` | Tuning. `BloodConfig` holds the master switch, colours, draw layers, the decal layer's cap and drying. |

Master switches: `BloodConfig.enabled` (off: `BloodWound.record` spawns nothing and `Physics.bleed_out` returns null), and
under it `BloodPrintConfig.footprints_enabled`, `BloodSmearConfig.enabled`, `BloodSurfaceConfig.flow` (Testing's `physics.blood`,
`physics.footprints`, `physics.smear`). `PhysicsConfig.wall_mask` is the layer splat clipping and flow queries treat as blocking.

## Spray, drips, splats

- `BloodWound.record(hit)` throws `ceil(damage / hit_splat_damage)` splats (max `hit_splat_max`) out the exit side at once, one
  more out an exit wound. A splat is begun as thrown (`BloodSplat.begin`: random shapes and wall
  rays on the main thread, in `setup`'s order; the outline merge, `_fold`, on a worker thread) and `record` returns without
  waiting; `BloodSplat.defer_finish` finishes them in one deferred call later in the frame, before drawing (`finish`: waits for
  the merge, registers with `BloodField` aged from the frame it was begun on, draws). Nothing sees a splat half-built:
  `BloodField.wetness_at` first runs `BloodSplat.finish_pending`, and a splat freed early waits for its task as it leaves the
  tree. Pinned by `blood_spray_side_by_side_matches_whole_test.gd` and `blood_spray_does_not_wait_test.gd`;
  `spray_side_by_side` off builds each whole. A drip is built whole.
- Drips: damage adds `ceil(damage * drips_per_damage)` to a budget (cap `max_pending_drips`); while it lasts, one drop falls every
  `BloodDripConfig.interval_min..max` s from the host's `blood_origin()` keeping the host's `velocity` for `fall_time`, so a
  walker's drops land ahead. `stop()` on death ends them. A body keeps at most `max_splats_per_body` splats (oldest freed).
- A splat is built once in `setup` and then static: shapes clipped by walls (a ray from the centre against `wall_mask`) and
  merged into opaque outlines so overlaps do not darken (`Geometry2D.merge_polygons`, skipped for outlines whose boxes are
  apart; `blood_splat_merge_fast_path_test.gd`), drawn as one `FillBatch`. About 1 splat in 100,000 unions into a polygon the
  engine cannot triangulate; `BloodSplat.drawable` swaps it for its convex hull (or drops it) instead of logging an error
  (`blood_splat_shapes_valid_test.gd`). It dries to `dried_color` over `BloodSplatConfig.dry_time`.

## Bleed-out and the floor

- `Physics.bleed_out(parent, source, exclude)` (`BloodSpawner.bleed`) starts a `BloodPool` where the dead body's blood leaves it
  (`blood_origin()`: the trunk's middle once fallen). A `BloodFlow` flood-fill claims `bleed_out_cells` grid cells up front
  (a batch per frame), cheapest-first with noisy cost; cells overlapping a `wall_mask` collider never fill, so the
  puddle wraps walls and furniture. A front sweeps through flow-cost over `bleed_out_duration`.
  Drawn by blurring the fill field and thresholding it in a shader (`blood_pool_blur_matches_plain_test.gd` pins the blur).
- `BloodSurface.resistance(world_pos)` multiplies each cell's step cost: Objects' floors register a world rect and a `groove`
  Callable, so blood runs cheaply along grooves, slowly across smooth floor, slowest over porous (carpet, rugs); outdoors 1.
  The newest registration wins on overlap, except any porous surface at a point counts.
- **Soaking:** once the flood has mostly reached a porous cell (>= 0.5), `BloodFlow.tick(delta)` (from `BloodPool`, which keeps
  processing while `soaking()`) takes its soak 0 → 1 over `soak_time`. Soaking never changes `fill(c)` or the outline; the blood
  turns translucent (`soak_opacity`) so the carpet shows through. `wetness(c)` = `fill * (1 - soak)` is what `BloodField` reads,
  so soaked blood leaves no prints or smears. Dragged trail cells do not soak.
- Porous floor also slows and shortens the pool: `porous_spread_slowdown` stretches the sweep by the share of porous cells, and
  each costs `porous_cell_weight` of the budget. The pool texture is RG8 (red = fill, green = soak, written only when
  `has_porous()`); the shader splits it into `soak_tuft_size` px tufts, each with its own soak rate and shade.

## Carried blood

A carrier soaks up a *load* (0..1) of wet blood and deposits it as the load fades, so trails taper.

- `BloodField` (static): `wetness_at(world_pos)` 0..1. Splats and pools (`BloodPool.seed_bleed_out`) register themselves
  (entries drop on `tree_exited`). A splat is a thin film (`splat_wetness`) drying to 0 over `dry_time`; a pool is its flow
  fill, wet for `pool_wet_time`. Ages count physics frames.
- `BloodDecals` (`layer(parent)` / `find(parent)`, extends `chunked_layer.gd`, see `SKILL.md`): batches prints and smear ribbons at
  `BloodConfig.print_z_index`; chunks redraw only on a new mark or a growing ribbon, and at 2 Hz while drying
  (`print_dry_time`); its cap is `print_max`, not the Despawner's. `ribbon_begin` / `ribbon_extend` (width 0 tapers to a point); `print_at` drops polygons the engine cannot triangulate.
- `BloodFootprints` (a walker's child; `step(foot, fall: Footfall)` per footfall, from the character's
  `character_footsteps.gd`): per foot id, soak `max(load, wetness * pickup_gain)`, stamp a mirrored sole with alpha from the
  load unless already in thick blood (`thick_blood`, which gates footprints only), then lose `decay`.
- `BloodSmear` (a RigidBody2D's child): `set_footprint(local polygon)` lays a grid of "fingers" fixed to the body; above
  `BloodSmearConfig.min_speed` each finger soaks blood under it and extends its ribbon every `segment_length` px, width
  `BloodSmearLookConfig.width` × spacing × sqrt(load). Load falls by `decay_per_px`; below `break_load` the ribbon breaks into
  dashes; at rest it tapers.
  - *Blending into the puddle:* a ribbon is see-through where the floor is wet (`absorb_lo..hi`), eases in over `fade_in` px
    and rises at most `alpha_rise` per sample, so a streak has no start line.
  - *Pulled out of a pool:* a finger carrying >= `smear_trail_min` within `smear_trail_reach` px of a pool calls
    `BloodPool.drag_out`, adding `BloodFlow.trail` cells (3x3, max-merged, capped at `pool_trail_max`, tapering to 0 at
    `pool_trail_length` px: how far a pool can be dragged; `fill(c)` = max(flood, trail)). The pool's own visuals draw the
    tongue; `BloodField.pool_near(pos, radius)` finds the pool.

## Draw order

All blood lies at `DrawLayers.BLOOD` (interface 11), through `BloodConfig.z_index` (splats, and the `BloodPool` node, set by
`BloodSpawner._new_pool`) and `print_z_index` (prints, smears, scorch): over the floor and rugs, under what lies there (a dead
body, casings, a dropped item) and under a vehicle driving over it.
