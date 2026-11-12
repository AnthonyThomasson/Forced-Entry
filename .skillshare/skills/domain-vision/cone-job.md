# Vision · the cone as a job (`scenes/vision/view_cone.gd`)

A rebuild of the cone is a job stepped by work units: `ViewCone.begin` / `step`.

`begin(space, eye, facing, exclude, sight)` takes the inputs and drops any job in flight; `step(units)` runs it on until `units` of engine work are spent and says whether it is done;
`rebuild` is `begin` plus `step` to the end, so it is the whole rebuild every existing cone test and `PlayerView` use. A unit
is a price in `VisionSliceConfig` (default 1 each): a ray cast, a region shape query (counted by `ViewShapes.queries`), a
far-face probe (the ray's `far_exit`). Stages in order, the job's place in `_job` (`ViewConeJob`: stage, next item, work, the
inputs; the cone's width and the fan's hide table stay on the cone, read for every corner) and its data in `_build` (`ViewConeBuffer`): corners (one piece), the even fan by ray, which corners the eye sees by
corner (the angle lists are then sorted, atomic, no engine work), the bubble's rays, the cone's rays (a fan ray takes its end
from the fan's casts, no work). A step cuts only between those items, so a step may spend a little over its units, always does
at least one item, and the polygon does not depend on the slice (`vision/cone_sliced_matches_whole`: 1, 7, 64 and the default
`slice_units` units equal `rebuild` exactly, with a reader's `cone`, `bubble`, `eye`, `corner_rays`, `corners_read` unchanged
until the job completes). **Double-buffered:** the job builds in `_build` and `_finish` swaps those readers in together, so
a reader never sees half a job (the old code wrote `eye` first and the polygons last). The job holds the world's direct space
state and a reference to `exclude`; step it in the physics tick, and a world change between steps is the caller's to
detect (`ViewWatch`) and answer with a new `begin` (restart). `slice_units` (450) is sized to about 3.5 ms: 6 µs a unit in
houses, 8 to 9 in a match's view; `restart_cap` (2) is for `PlayerView`'s pipeline. `work_units` and `steps_taken` are the last job's.
