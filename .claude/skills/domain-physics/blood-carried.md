# Physics blood: carried blood (`scenes/physics/blood/`)

The rest of `blood.md` (spray, splats, the bleed-out pool, draw order) is its entry point; this holds what a walker or a body carries from blood it meets.

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
  dashes; at rest it tapers. It steps only while its body is awake (`sleeping_state_changed` wakes and stops it; a frozen body never moves), since a district holds hundreds of resting pieces (`physics/object_smear_sleeps_at_rest`).
  - *Blending into the puddle:* a ribbon is see-through where the floor is wet (`absorb_lo..hi`), eases in over `fade_in` px
    and rises at most `alpha_rise` per sample, so a streak has no start line.
  - *Pulled out of a pool:* a finger carrying >= `smear_trail_min` within `smear_trail_reach` px of a pool calls
    `BloodPool.drag_out`, adding trail cells (`BloodFlow.add_trail`) (3x3, max-merged, capped at `pool_trail_max`, tapering to 0 at
    `pool_trail_length` px: how far a pool can be dragged; `fill(c)` = max(flood, trail)). The pool's own visuals draw the
    tongue; `BloodField.pool_near(pos, radius)` finds the pool.
