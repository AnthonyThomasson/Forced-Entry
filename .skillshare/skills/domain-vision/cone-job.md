# Vision · the cone as a job (`scenes/vision/view_cone.gd`)

A rebuild of the cone is a job stepped by work units: `ViewCone.begin` / `step`.

`begin(space, eye, facing, exclude, sight)` takes the inputs and drops any job in flight (a restart: the readers keep the last
finished job's polygons until the new one completes); `step(units)` runs it on until `units` of engine work are spent and says
whether it is done; `running()` says whether one is in flight; `work_units()` is the work the job has spent. `rebuild` is
`begin` plus `step` to the end, so it is the whole rebuild every existing cone test and `PlayerView` use.

**Units.** A unit is a price in `VisionSliceConfig` (`cost_cast` and `cost_probe` 1, `cost_shape` 450): a ray cast
(`SightRay.cast`), a region shape query (`ViewShapes.queries`, re-asks included), a far-face probe (`far_exit`).
**The corners are priced at a slice** (`cost_shape` 450): the query, its polygons, the dedupe and the lows' leave-out cost about 1.95 ms,
372 to 374 units at 5.4 to 5.5 µs (`perf/cone_corner_cost` measures it; p25 168, p75 627 by eye), so `begin` and the first step do the corners and cast no ray
(`vision/cone_corners_priced`), and the rays begin the next tick. Priced as one unit they made a start tick the corners plus 449 units of
rays, about 6 to 7 ms. A job is the corners' tick plus ceil(rays / slice) ticks, and its cone is at most 2 (ticks - 1) frames old: 3 ticks (rays
at most two slices) is 2 to 4, 4 ticks 6, the longest district job (6 ticks) 10 (`vision/pose_lag_bounds` pins 3 and 6 ticks; the user accepted it, 2026-11-12), and a test that cuts `slice_units` cuts `cost_shape` to it. `vision/cone_slice_units` holds `work_units()` to casts, queries and probes counted by subclasses, at every step size and at
other prices (which change the count, never the polygon).

**Stages**, in order: the corners (one piece), the even fan by ray, which corners the eye sees by corner, the sort of the ray
lists (atomic, no engine work), the bubble's rays, the cone's rays (a fan ray takes its end from the fan's casts, no work). A
step cuts only between those items, so it may spend a little over its units, always does at least one item, and the polygon does
not depend on the slice (`vision/cone_sliced_matches_whole`: 1, 7, 64 and the default `slice_units` equal `rebuild` exactly).

**State.** What every ray reads is a member of `ViewCone` (`_space`, `_from`, `_reach`, `_near`, `_fov`, `_fan_hide`: a member is
the cheapest read, and the stage loops are the cone's cost); the stage, next item, work, facing, exclude list and coverage are
in `_job` (`ViewConeJob`); the data of the job is in `_build` (`ViewConeBuffer`). **Double-buffered:** the job builds in
`_build` and `_finish` swaps `cone`, `bubble`, `eye`, `corner_rays`, `corners_read` in together, so a reader never sees half a
job. Keep the stage loops free of per-item calls and property reads of other objects: the sliced cone costs under 2 % more than
the one-piece cone it replaced, and that was got by hoisting them.

**Use.** The job holds the world's direct space state and the `exclude` array; step it in the physics tick. A world change between
steps is the caller's to detect (`ViewWatch`) and answer with a new `begin`. `slice_units` (450) is about 3.5 ms: 6 µs a unit in
houses, 8 to 9 in a match's view. `restart_cap` (2) and `jump_px` (48) are `ViewPipeline`'s.

## The pipeline (`view_pipeline.gd`, `ViewPipeline`; ADR 0012, V1)

`PlayerView._physics_process` calls `ViewPipeline.tick(space, eye, facing, exclude, sight)` once a tick (priority 100); it says
whether a cone was published in it, and then the view writes `SeenArea`.
- **Idle:** `ViewWatch.stale` (any input changed, the pose too) starts a job from the live pose (`look`, `ViewCone.begin`,
  `ViewWatch.built`) and steps it. A job of 3 ticks started in tick f publishes in f+2; the next starts in f+3: 2 to 4 frames old (a job of k ticks: at most 2 (k - 1)).
- **In flight:** an eye farther than `jump_px` from the published pose builds whole at once; else `ViewWatch.world_changed(sight)`
  (the sight and cone tuning, the dirty flag, a blocking character, the `_moved_then` flush quirk, a blocker moved in reach of the
  job's pose: not the eye or facing) restarts the job from the live pose; else one slice. Restart number `restart_cap` + 1 in a row
  (reset by a publish) builds whole. The first cone and a jump from idle build whole.
- **Counts:** `started` (every begin: a start, a restart, a whole build), `published`, the pose the cone shown is of (`pose_eye`,
  `pose_facing`): `PlayerView.starts()`, `rebuilds()`, `published_pose()`. `drop()` (a lift, a disabled view) aborts the job and
  makes the next ask a rebuild.
- The sector `ViewWatch` measures "within reach" by stays the job's pose during a job (a blocker moving near the live eye only is
  not a change to the job), and is set again at each begin. A blocker moved after a job began is seen at the next tick's
  `world_changed`, before its slice, so a slice never reads a world the check has seen change.
- A standing character anywhere in the tree whose coverage is above the viewer's `see_over` makes every tick a restart (a whole build
  every 4th frame): `_blocking_now` is not limited to reach. The default sight (60) never triggers it.
- **Tests:** a job is a few frames only when the slice is small: a test that needs a lag, a restart or a cap sets
  `VisionSliceConfig.slice_units` and `cost_shape` (140 for both makes the test houses' jobs three frames, `vision/pose_lag_bounds`,
  `vision/cone_restarts_on_world_change`, `vision/cone_skip_exact_sliced`, `vision/half_job_dropped`), and one that reads the cone of a pose waits for it
  (`Probe.place` waits for the published pose; `tests/_vision/cone_checker.gd` compares each published cone to the reference cone
  of `published_pose()`).
