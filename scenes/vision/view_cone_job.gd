extends RefCounted
## Vision domain: what a `ViewCone` job (`begin` to done) is for and how far it has got: the world
## it casts in, the eye, facing and what the eye sees by, and the stage, the next item of it and the
## engine work spent. Private to `ViewCone`.

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
## The world the job casts in, the rids it leaves out and the eye and facing it is of (a zero
## facing: no cone, the bubble only).
var space: PhysicsDirectSpaceState2D
var exclude: Array = []
var eye := Vector2.ZERO
var facing := Vector2.ZERO
## What the eye sees by (`Character.sight()`): the view distance, the bubble's radius and the
## coverage it looks over (the cone's width is `ViewCone`'s own).
var reach := 0.0
var near := 0.0
var see_over := 0.0


## Take the job's inputs and start at its first stage.
func start(
	in_space: PhysicsDirectSpaceState2D,
	from: Vector2,
	toward: Vector2,
	leave_out: Array,
	sight: Dictionary,
) -> void:
	space = in_space
	eye = from
	facing = toward
	exclude = leave_out
	reach = float(sight["view_distance"])
	near = float(sight["awareness_radius"])
	see_over = float(sight["see_over_coverage"])
	index = 0
	work = 0
	stage = Stage.CORNERS
