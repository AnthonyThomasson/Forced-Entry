# Physics blood (`scenes/physics/blood/`)

Wound spray and drips, splats, a dead body's bleed-out pool and its floor-steered flow, and carried blood (wetness, footprints,
smears). Separate from debris and deformation: the rest of `physics/` reaches it only through
`Physics.spawn_debris` (a hit with `HitInfo.blood`; the bloody mark on an object is the core's `Deformation.draw_marks`) and
`Physics.bleed_out`; every other domain meets it through interface 4's classes. It imports only General: `Despawner`, `DrawLayers`,
`FillBatch` and `SeenArea`. Tests: `tests/physics/` (`blood_*`, `footprints_*`, `object_smear*`,
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
  walker's drops land ahead. `stop()` on death ends them. A body keeps at most `max_splats_per_body` splats (oldest freed) in an
  advancing-head FIFO, so eviction and removal of an externally freed oldest splat do not shift the whole list
  (`blood_wound_evicts_oldest_splat_test.gd` holds it to a plain capped array).
- A splat is built once in `setup` and then static: one conservative whole-extent shape query (a circle of `BloodSplat.clear_radius(core radius)`) first skips every clipping ray when
  no `wall_mask` collider can reach any possible core, spike, tail or satellite; near geometry the exact centre-to-feature rays remain
  (`blood_splat_open_matches_rays_test.gd` pins identical outlines and RNG draws, with a wall just beyond and just inside the radius). Shapes are merged into opaque outlines so overlaps
  do not darken (`Geometry2D.merge_polygons`, skipped for outlines whose boxes are
  apart; `blood_splat_merge_fast_path_test.gd`), drawn as one `FillBatch`. About 1 splat in 100,000 unions into a polygon the
  engine cannot triangulate; `BloodSplat.drawable` swaps it for its convex hull (or drops it) instead of logging an error
  (`blood_splat_shapes_valid_test.gd`). It dries to `dried_color` over `BloodSplatConfig.dry_time`.

## Bleed-out and the floor

- `Physics.bleed_out(parent, source, exclude)` (`BloodSpawner.bleed`) starts a `BloodPool` where the dead body's blood leaves it
  (`blood_origin()`: the trunk's middle once fallen). A `BloodFlow` flood-fill claims `bleed_out_cells` grid cells up front
  (a batch per frame), cheapest-first with noisy cost. Its frontier heap orders by (cost, first insertion sequence), leaving stale
  entries on a cost decrease, so claims match the old linear dictionary scan even on ties; one square and query-parameter object are
  reused for blocked-cell tests (`blood_flow_heap_matches_scan_test.gd`). Cells overlapping a `wall_mask` collider never fill, so the
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

Wetness, footprints, smears and a pool dragged out: `blood-carried.md`.

## Draw order

All blood lies at `DrawLayers.BLOOD` (interface 11), through `BloodConfig.z_index` (splats, and the `BloodPool` node, set by
`BloodSpawner._new_pool`) and `print_z_index` (prints, smears, scorch): over the floor and rugs, under what lies there (a dead
body, casings, a dropped item) and under a vehicle driving over it.

## In the player's view (`docs/player-vision.md` V11)

A pool the player's view does not show is not redrawn (`BloodPool`). `_physics_process` (and `drag_out`) only mark the pool stale; its
`_process`, which runs after every physics tick of the frame, redraws a stale pool when `SeenArea.reaches_rect` (General, interface 11)
says the box its cells cover (`BloodFlow.extent()`, plus the blur's `PAD`) reaches what the view shows, on the frame's own area, so a pool
the cone sweeps onto is drawn that very frame; with no view it is drawn each frame as before. The box, not the circle round it: a long
pool's circle reaches the viewer's 48 px bubble when the pool does not. The flood and soak keep running unseen: `BloodField` reads the
fill, never the drawing. Settled blood stays on `ViewLayers.WORLD`, so the view remembers it; the blood spray in flight is Physics'
`HitParticles` / `DebrisSpawner` on `MOVING`. Tests: `vision/unseen_not_repainted` (a pool outside the cone is never redrawn; redrawn the
frame the cone reaches it), `vision/moving_never_remembered`. Measured by A/B: 0.13 to 0.5 ms a frame, 12 to 25 % of the pools' draw time, the whole frame's change within noise.
