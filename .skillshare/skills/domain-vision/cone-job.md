# Vision · the cone as a job (`scenes/vision/view_cone.gd`)

A rebuild of the cone is a job stepped by work units: `ViewCone.begin` / `step`.

`begin(space, eye, facing, exclude, sight)` takes the inputs and drops any job in flight (a restart: the readers keep the last
finished job's polygons until the new one completes); `step(units)` runs it on until `units` of engine work are spent and says
whether it is done; `running()` says whether one is in flight; `work_units()` is the work the job has spent. `rebuild` is
`begin` plus `step` to the end, so it is the whole rebuild every existing cone test and `PlayerView` use.

**Units.** A unit is a price in `VisionSliceConfig` (`cost_cast` and `cost_probe` 1, `cost_shape`
120 a corners query, `cost_hits` 35 a chunk of `hit_chunk` 32 hits): a ray cast (`SightRay.cast`), a
region shape query (`ViewShapes.queries`, re-asks included: a 3D shape query in the twin space over
a slab (`ViewShapes.SLAB`, 2 px: the engine cannot build a thinner hull of the sector) from the
height the plan ray runs at), a far-face probe (`far_exit`).
**The corners are priced at their cost** (`cost_shape` 120 + `cost_hits` 35 a chunk of 32 hits, a
median 3 chunks: 225, the user's price, held by `perf/cone_corner_cost` for the whole, the query and
the chunks each within 2x of their own; the split 120 / 35 is the one `vision/view_on_npc`'s 4-frame bound
holds at, a dearer chunk (100 / 42) makes a crowded region a tick longer): the query (stage `CORNERS`) and then its polygons and the
dedupe (stage `HITS`, a chunk a piece of work, so a slice may end between them) are 225 units
(`perf/cone_corner_cost` measures it: 198 on 2026-11-19, 264 on 2026-11-24, both loaded; p25 104, p75 304; the 2D query was 372 to 374), so `begin` and the first step do the corners and then the first rays up to
the slice (`vision/cone_corners_priced`); a region asked again is priced for each ask and can fill the slice with them, and then no ray is cast. Priced as one unit they made a start tick the corners plus 449 units of
rays, about 6 to 7 ms. A job is ceil((corners + rays) / slice) ticks, and its cone is at most 2 (ticks - 1) frames old: 2 ticks is up to 2, 3 ticks 4, the longest district job in the grid (5 ticks) 8
(`vision/pose_lag_bounds` still holds a job to 6 ticks, 10 frames; the user chose to price the corners at their cost on 2026-11-19, over the slice-sized price of 2026-11-12; the tick figures were measured loaded and perf3d re-measures them quiet), and a test that cuts `slice_units` cuts `cost_shape` to it. `vision/cone_slice_units` holds `work_units()` to casts, queries and probes counted by subclasses, at every step size and at
other prices (which change the count, never the polygon).

**Stages**, in order: the corners (the query, one piece; then its hits a chunk at a time), the even
fan by ray, which corners the eye sees by corner, the sort of the ray
lists (atomic, no engine work), the bubble's rays, the cone's rays (a fan ray takes its end from the fan's casts, no work). A
step cuts only between those items, so it may spend a little over its units, always does at least one item, and the polygon does
not depend on the slice (`vision/cone_sliced_matches_whole`: 1, 7, 64 and the default `slice_units` equal `rebuild` exactly).

**State.** What every ray reads is a member of `ViewCone` (`_space`, `_from`, `_reach`, `_near`, `_fov`, `_fan_hide`: a member is
the cheapest read, and the stage loops are the cone's cost); the stage, next item, work, facing, exclude list and eye height (`see_over`) are
in `_job` (`ViewConeJob`); the data of the job is in `_build` (`ViewConeBuffer`). **Double-buffered:** the job builds in
`_build` and `_finish` swaps `cone`, `bubble`, `eye`, `corner_rays`, `corners_read` in together, so a reader never sees half a
job. Keep the stage loops free of per-item calls and property reads of other objects: the sliced cone costs under 2 % more than
the one-piece cone it replaced, and that was got by hoisting them.

**Use.** The job holds the world's 3D direct space state and the `exclude` array (twin rids); step it in the physics tick. A world change between
steps is the caller's to detect (`ViewWatch`) and answer with a new `begin`. `slice_units` (450) is about 3.5 ms: 6 µs a unit in
houses, 8 to 9 in a match's view. `restart_cap` (2), `jump_px` (48) and `settle_px` (1) are `ViewPipeline`'s (`VisionSliceConfig`).

## The pipeline (`view_pipeline.gd`, `ViewPipeline`; ADR 0012, V1)

`PlayerView._physics_process` calls `ViewPipeline.tick(space, eye, facing, exclude, sight)` once a tick (priority 100); it says
whether a cone was published in it, and then the view writes `SeenArea`.
- **Idle:** `ViewWatch.stale` (any input changed, the pose too) starts a job from the live pose (`look`, `ViewCone.begin`,
  `ViewWatch.built`) and steps it. A job of 3 ticks started in tick f publishes in f+2; the next starts in f+3 (the cone's age: `docs/player-vision.md` V1).
- **In flight:** an eye farther than `jump_px` from the published pose builds whole at once; else `ViewWatch.world_changed(sight)`
  (the sight and cone tuning, the dirty flag, a blocking character, the `_moved_then` flush quirk, a blocker moved in reach of the
  job's pose: not the eye or facing) restarts the job from the live pose; else one slice. Restart number `restart_cap` + 1 in a row
  (reset by a publish) builds whole unless the change is slow moves only (`ViewWatch.settles(sight)`: no signal, no joined blocker, the sight as built, every blocker in reach within `settle_px` of the snapshot): that restart begins a SETTLING job, a job like any other whose blockers within `settle_px` are where they were, published with `PlayerView.settled_publish()`; a settling job restarted builds whole; `settle_px` 0 = off. The first cone and a jump from idle build whole.
- **Counts:** `started` (every begin: a start, a restart, a whole build), `published`, the pose the cone shown is of (`pose_eye`,
  `pose_facing`): `PlayerView.starts()`, `rebuilds()`, `published_pose()`. `causes` (`restarts`, whole builds by cause `first` / `jump` / `cap`, `settled` restarts past the cap, engine `units` stepped), read by a perf probe through `PlayerView.rebuild_causes()` (interface 25). `drop()` (a lift, a disabled view) aborts the job and
  makes the next ask a rebuild.
- The sector `ViewWatch` measures "within reach" by stays the job's pose during a job (a blocker moving near the live eye only is
  not a change to the job), and is set again at each begin. A blocker moved after a job began is seen at the next tick's
  `world_changed`, before its slice, so a slice never reads a world the check has seen change.
- A character never blocks the cone (`SightRay.top_of` is 0), so one moving costs no restart; the viewer ducking or standing changes the eye height and rebuilds the cone.
- **Tests:** a job is a few frames only when the slice is small: a test that needs a lag, a restart or a cap sets
  `VisionSliceConfig.slice_units` and `cost_shape` (140 for both makes the test houses' jobs three frames, `vision/pose_lag_bounds`,
  `vision/cone_restarts_on_world_change`, `vision/cone_skip_exact_sliced`, `vision/half_job_dropped`), and one that reads the cone of a pose waits for it
  (`Probe.place` waits for the published pose; `tests/_vision/cone_checker.gd` compares each published cone to the reference cone
  of `published_pose()`).
