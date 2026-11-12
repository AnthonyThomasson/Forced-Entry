# Vision · the cone as a job (`scenes/vision/view_cone.gd`)

A rebuild of the cone is a job stepped by work units: `ViewCone.begin` / `step`.

`begin(space, eye, facing, exclude, sight)` takes the inputs and drops any job in flight (a restart: the readers keep the last
finished job's polygons until the new one completes); `step(units)` runs it on until `units` of engine work are spent and says
whether it is done; `running()` says whether one is in flight; `work_units()` is the work the job has spent. `rebuild` is
`begin` plus `step` to the end, so it is the whole rebuild every existing cone test and `PlayerView` use.

**Units.** A unit is a price in `VisionSliceConfig` (`cost_cast`, `cost_shape`, `cost_probe`, 1 each): a ray cast
(`SightRay.cast`), a region shape query (`ViewShapes.queries`, re-asks included), a far-face probe (`far_exit`).
`vision/cone_slice_units` holds `work_units()` to casts, queries and probes counted by subclasses, at every step size and at
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
houses, 8 to 9 in a match's view. `restart_cap` (2) is for `PlayerView`'s pipeline and read by nothing yet.
