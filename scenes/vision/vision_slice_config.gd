class_name VisionSliceConfig
## The Vision domain's tuning for a sliced cone rebuild (`ViewCone.begin` / `step`; the vision
## skill's `cone-job.md`). A `class_name` holder of `static var`s, read as
## `VisionSliceConfig.<name>`; there is no instance and no autoload. The cone's engine work is
## counted in units, each priced here; `ViewCone` is cut only between rays, so what a job builds
## does not depend on its slice or prices.

## What a piece of engine work costs, in units: a ray cast, a region shape query (the corners'),
## and a far-face probe (a point query) after a ray that met a blocker.
static var cost_cast: int = 1
static var cost_shape: int = 1
static var cost_probe: int = 1
## The units one `step` runs: about 3.5 ms of a physics frame.
static var slice_units: int = 450
## How many times a job in flight may be thrown away for a change of the world (a restart) before
## the next restart builds the cone whole in one frame (`ViewPipeline`); a publish resets the count.
static var restart_cap: int = 2
## An eye farther than this (px) from the pose of the cone published or in flight is a jump (a
## teleport, a vehicle): the cone is built whole in that frame, so it is never that far behind.
static var jump_px: float = 48.0
