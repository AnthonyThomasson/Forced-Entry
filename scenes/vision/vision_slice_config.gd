class_name VisionSliceConfig
## The Vision domain's tuning for a sliced cone rebuild (`ViewCone.begin` / `step`; the vision
## skill's `cone-job.md`). A `class_name` holder of `static var`s, read as
## `VisionSliceConfig.<name>`; there is no instance and no autoload. The cone's engine work is
## counted in units, each priced here; `ViewCone` is cut only between rays, so what a job builds
## does not depend on its slice or prices.

## What a piece of engine work costs, in units: a ray cast, a region shape query (the corners'),
## and a far-face probe (a point query) after a ray that met a blocker.
static var cost_cast: int = 1
## The corners (the region shape query, its polygons, the dedupe) cost about 200 to 225 units
## (`perf/cone_corner_cost`, the 3D shape query of the twin space): the query is priced `cost_shape`
## (a third of that: 0.8 of the 2.2 ms) and its polygons and dedupe `cost_hits` a chunk, below. A
## job whose query is asked again (a crowded region) is priced for each ask.
static var cost_shape: int = 80
static var cost_probe: int = 1
## The polygons and the dedupe of the corners are priced apart from the query: `hit_chunk` hits a
## piece of work of `cost_hits` units, so a start tick holds the query and a few chunks, not all
## of the corners.
static var cost_hits: int = 18
static var hit_chunk: int = 32
## The units one `step` runs: about 3.5 ms of a physics frame.
static var slice_units: int = 450
## How many times a job in flight may be thrown away for a change of the world (a restart) before
## the next restart builds the cone whole in one frame (`ViewPipeline`); a publish resets the count.
static var restart_cap: int = 2
## An eye farther than this (px) from the pose of the cone published is a jump (a teleport, a
## vehicle), checked every tick, a job in flight or not: the cone is built whole in that frame, so
## the cone shown is never more than this behind the eye.
static var jump_px: float = 48.0
## How far (px) a blocker may have moved from where a job saw it for the job that follows the
## restart cap to go on (`ViewPipeline`: a settling job, instead of a whole build in one frame): a
## piece settling or sliding slowly. The cone it publishes differs from the world by what the piece
## moved while it was built, and the next job starts at once. 0 builds whole at the cap, as before.
static var settle_px: float = 1.0
