extends RefCounted
## Vision domain: how far a `ViewCone` job (`begin` to done) has got, and what of it is not hot: the
## stage, the next item of it, the engine work spent, the facing it is of (a zero facing: no cone,
## the bubble only), the rids it leaves out and the coverage it looks over. The world, the eye and
## the distances it reads for every ray are members of `ViewCone`. Private to it.

## The stages of a job, in order; `DONE` when none is in flight.
enum Stage {
	CORNERS,
	FAN,
	VISIBLE,
	BUBBLE,
	CONE,
	DONE,
}

## The stage the job is in, and the next item of it (a fan ray, a corner, a ray of a sweep).
var stage := Stage.DONE
var index := 0
## The engine work (units: `VisionSliceConfig`) spent so far.
var work := 0
var facing := Vector2.ZERO
var exclude: Array = []
var see_over := 0.0


## Take the job's inputs and start at its first stage.
func start(toward: Vector2, leave_out: Array, looks_over: float) -> void:
	facing = toward
	exclude = leave_out
	see_over = looks_over
	index = 0
	work = 0
	stage = Stage.CORNERS
