# Physics blood (`scenes/physics/blood/`)

Wound spray and drips, splats, a dead body's bleed-out pool and its floor-steered flow, and carried blood (wetness, footprints,
smears). Separate from debris and deformation: the rest of `physics/` reaches it only through
`Physics.spawn_debris` (a hit with `HitInfo.blood`; the bloody mark on an object is the core's `PhysicsDeformLookConfig.blood_mark_*`) and
`Physics.bleed_out`; every other domain meets it through interface 4's classes. It imports only General: `Despawner` and `SeenArea`. Tests: `tests/physics/` (`blood_*`, `footprints_*`, `object_smear*`,
`smear_ribbon_shape`, `wound_*`, `death_*`). 3D: `meshes.md`.

## Files and tuning

| File | Role |
|---|---|
| `blood_wound.gd` (`BloodWound`) | Node the character composes like `Knockback`; its `take_hit` calls `record(hit)`. Spray and drips. |
| `blood_spawner.gd`, `blood_throw.gd` | Spawns each splat and pool with a readable name (`BloodSplat`, `BloodSplat2`, …, `BloodPool`); `BloodThrow` carries a splat's throw (and the `surface` it lands on). |
| `blood_splat.gd`, `blood_pool.gd`, `blood_pool_field.gd`, `blood_flow.gd`, `blood_surface.gd` | A splat (outlines and wet highlight as data); a bleed-out pool, its fill field (`BloodPoolField`: the blurred bytes the 3D pool shows), its flood-fill and the floor that steers it. |
| `blood_field.gd`, `blood_decals.gd`, `blood_footprints.gd`, `footfall.gd`, `blood_smear.gd` | Wetness queries, the batched print layer, a walker's prints, a body's smear. |
| `BloodConfig` plus `Blood{Drip,Spray,Splat,Pool,Surface,Print,Smear,SmearLook,Trail}Config` | Tuning. `BloodConfig` holds the master switch, colours, the decal layer's cap and drying. |

Master switches: `BloodConfig.enabled` (off: `BloodWound.record` spawns nothing and `Physics.bleed_out` returns null), and
under it `BloodPrintConfig.footprints_enabled`, `BloodSmearConfig.enabled`, `BloodSurfaceConfig.flow` (Testing's `physics.blood`,
`physics.footprints`, `physics.smear`). A splat's clipping rays and a pool's flow queries read the twin 3D space on `PhysicsConfig.twin_mask`, laid on the floor (`BloodLanding.on_floor`: a 1 px slab from 0.5 px up): what stands on the floor blocks, a table's top or a lintel over it does not, and a world with no twin space blocks nothing. A bleeding body's `exclude` is its twin's RID.

## Spray, drips, splats

- `BloodWound.record(hit)` throws `ceil(damage / hit_splat_damage)` splats (max `hit_splat_max`) out the exit side at once, one
  more out an exit wound. A splat is begun as thrown (`BloodSplat.begin`: random shapes and wall
  rays on the main thread, in `setup`'s order; the outline merge, `_fold`, on a worker thread) and `record` returns without
  waiting; `BloodSplat.defer_finish` finishes them in one deferred call later in the frame (`finish`: waits for
  the merge, registers with `BloodField` aged from the frame it was begun on, keeps its outlines and wet highlight as data and tells the 3D
  render, `PhysicsFxHook.splat_made`). Nothing sees a splat half-built:
  `BloodField.wetness_at` first runs `BloodSplat.finish_pending`, and a splat freed early waits for its task as it leaves the
  tree. Pinned by `blood_spray_side_by_side_matches_whole_test.gd` and `blood_spray_does_not_wait_test.gd`;
  `spray_side_by_side` off builds each whole. A drip is built whole.
- Drips: damage adds `ceil(damage * drips_per_damage)` to a budget (cap `max_pending_drips`); while it lasts, one drop falls every
  `BloodDripConfig.interval_min..max` s from the host's `blood_origin()` keeping the host's `velocity` for `fall_time`, so a
  walker's drops land ahead. `stop()` on death ends them. A body keeps at most `max_splats_per_body` splats (oldest freed) in an
  advancing-head FIFO, so eviction and removal of an externally freed oldest splat do not shift the whole list
  (`blood_wound_evicts_oldest_splat_test.gd` holds it to a plain capped array).
- **Where it lands (D12):** a spray or exit splat is traced as a parcel through the twin 3D space and lands on a wall's face or a piece's top at its real height: `blood-landing.md`.
- A splat is built once in `setup` and then static: one conservative whole-extent shape query (a floor disc of `BloodSplat.clear_radius(core radius)`) first skips every clipping ray when
  nothing on `twin_mask` can reach any possible core, spike, tail or satellite; near geometry the exact centre-to-feature rays remain
  (`blood_splat_open_matches_rays_test.gd` pins identical outlines and RNG draws, with a wall just beyond and just inside the radius). Shapes are merged into opaque outlines so overlaps
  do not darken (`Geometry2D.merge_polygons`, skipped for outlines whose boxes are
  apart; `blood_splat_merge_fast_path_test.gd`), shown by the 3D render as one mesh. About 1 splat in 100,000 unions into a polygon the
  engine cannot triangulate; `BloodSplat.drawable` swaps it for its convex hull (or drops it) instead of logging an error
  (`blood_splat_shapes_valid_test.gd`). It dries to `dried_color` over `BloodSplatConfig.dry_time`.

## Bleed-out and the floor

- `Physics.bleed_out(parent, source, exclude)` (`BloodSpawner.bleed`) starts a `BloodPool` where the dead body's blood leaves it
  (`blood_origin()`: the trunk's middle once fallen). A `BloodFlow` flood-fill claims `bleed_out_cells` grid cells up front
  (a batch per frame), cheapest-first with noisy cost. Its frontier heap orders by (cost, first insertion sequence), leaving stale
  entries on a cost decrease, so claims match the old linear dictionary scan even on ties; one square and query-parameter object are
  reused for blocked-cell tests (`blood_flow_heap_matches_scan_test.gd`). Cells a wall or a piece stands on (the twin space, on the floor) never fill, so the
  puddle wraps walls and furniture and runs under a table's top. A front sweeps through flow-cost over `bleed_out_duration`.
  Drawn by blurring the fill field and thresholding it in a shader (`blood_pool_blur_matches_plain_test.gd` pins the blur).
- `BloodSurface.resistance(world_pos)` multiplies each cell's step cost: Objects' floors register a world rect and a `groove`
  Callable, so blood runs cheaply along grooves, slowly across smooth floor, slowest over porous (carpet, rugs); outdoors 1.
  The newest registration wins on overlap, except any porous surface at a point counts.
- **Soaking:** once the flood has mostly reached a porous cell (>= 0.5), `BloodFlow.tick(delta)` (from `BloodPool`, which keeps
  processing while `soaking()`) takes its soak 0 → 1 over `soak_time`. Soaking never changes `fill(c)` or the outline; the blood
  shows only as the 3D pool's soaked tone (`PoolInk`). `wetness(c)` = `fill * (1 - soak)` is what `BloodField` reads,
  so soaked blood leaves no prints or smears. Dragged trail cells do not soak.
- Porous floor also slows and shortens the pool: `porous_spread_slowdown` stretches the sweep by the share of porous cells, and
  each costs `porous_cell_weight` of the budget. The pool texture is RG8 (red = fill, green = soak, written only when
  `has_porous()`).

## Carried blood

Wetness, footprints, smears and a pool dragged out: `blood-carried.md`.

## Where blood lies

Blood is data in the world: splats, the `BloodPool` fill, prints and smear ribbons (`BloodDecals`). Physics draws none of it: the 3D
render lays it on the floor (`mesh/`, `meshes.md`), told through `PhysicsFxHook`; it lies over the floor and rugs and under what
stands on it by the 3D heights.

## In the player's view (`docs/player-vision.md` V11)

Settled blood stays on `ViewLayers.WORLD`, so the view remembers it; the blood spray in flight is Physics' `HitParticles` /
`DebrisSpawner` on `MOVING`. The pool's flood and soak run whether seen or not: `BloodField` reads the fill, never a drawing.
Tests: `vision/moving_never_remembered`.
