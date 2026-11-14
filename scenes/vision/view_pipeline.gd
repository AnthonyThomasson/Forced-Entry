extends RefCounted
## Vision domain: how the view gets a new cone, a job stepped a slice a physics tick instead of one
## frame's whole rebuild (`docs/player-vision.md` V1; the vision skill's `cone-job.md`).
##
## A stale view (`ViewWatch.stale`) starts a job from the live eye, facing and sight and steps it
## `VisionSliceConfig.slice_units` each tick until it is done; the swapped-in cone is then the
## exact cone of that one eye in one world state, as old as the job is long
## (`docs/player-vision.md` V1), and what is published (`SeenArea`, the memory's paint) reads cone,
## bubble and eye together. Never extrapolated.
## - A change of the viewer's pose only (eye, facing) lets the job finish on its start pose; the
##   next job starts from the live pose.
## - A change of the world between slices (`ViewWatch.world_changed`) restarts the job from the live
##   pose, so a published cone never mixes two worlds; the `restart_cap`th restart in a row, since
##   the last publish, is built whole in that frame.
## - An eye farther than `jump_px` from the pose of the cone published (a teleport, a vehicle: so
##   the cone shown is never more than that far behind, a job in flight or not) and the first cone
##   are built whole at once.

const Cone := preload("res://scenes/vision/view_cone.gd")
const Watch := preload("res://scenes/vision/view_watch.gd")

## Jobs begun, restarts and whole builds included; cones published.
var started := 0
var published := 0
## A perf probe's read of what the pipeline spent: `restarts` (a job begun again after the world
## changed), the whole builds by cause (`first`: no cone yet, `jump`: the eye moved past `jump_px`,
## `cap`: the restart cap) and `units` (the engine work stepped, `VisionSliceConfig` units). Running
## totals since the view was built; nothing in the pipeline reads them.
var causes := { "restarts": 0, "first": 0, "jump": 0, "cap": 0, "units": 0 }
## The pose the cone in flight is being built for, and the one the published cone is of.
var job_eye := Vector2.ZERO
var job_facing := Vector2.ZERO
var pose_eye := Vector2.ZERO
var pose_facing := Vector2.ZERO
## Restarts since the last publish, and whether the view holds a cone (none after a drop: the next
## is built whole, like the first).
var _restarts := 0
var _has_cone := false
var _cone: Cone
var _watch: Watch


func _init(cone: Cone, watch: Watch) -> void:
	_cone = cone
	_watch = watch


## One physics tick, after the viewer has moved: start, restart or step the job. True when a cone
## was published in it.
func tick(
	space: PhysicsDirectSpaceState2D,
	eye: Vector2,
	facing: Vector2,
	exclude: Array,
	sight: Dictionary,
) -> bool:
	if _cone.running():
		if _jumped(eye, pose_eye):
			causes["jump"] += 1
			return _whole(space, eye, facing, exclude, sight)
		if _watch.world_changed(sight):
			return _restart(space, eye, facing, exclude, sight)
		return _step()
	if not _watch.stale(eye, facing, sight):
		return false
	if not _has_cone or _jumped(eye, pose_eye):
		causes["jump" if _has_cone else "first"] += 1
		return _whole(space, eye, facing, exclude, sight)
	_begin(space, eye, facing, exclude, sight)
	return _step()


## Whether a job is in flight.
func running() -> bool:
	return _cone.running()


## Drop the job in flight (the view was lifted or disabled): the next ask is a rebuild, built whole.
func drop() -> void:
	_cone.abort()
	_watch.forget()
	_has_cone = false
	_restarts = 0


## Whether `eye` is past `jump_px` from `from`.
func _jumped(eye: Vector2, from: Vector2) -> bool:
	return eye.distance_to(from) > VisionSliceConfig.jump_px


## Begin a job from the live pose: the watch takes its inputs as the job's.
func _begin(
	space: PhysicsDirectSpaceState2D,
	eye: Vector2,
	facing: Vector2,
	exclude: Array,
	sight: Dictionary,
) -> void:
	_watch.look(eye, facing, sight)
	_cone.begin(space, eye, facing, exclude, sight)
	_watch.built(eye, facing, sight)
	job_eye = eye
	job_facing = facing
	started += 1


## The world changed under the job: begin again from the live pose, or whole past the cap.
func _restart(
	space: PhysicsDirectSpaceState2D,
	eye: Vector2,
	facing: Vector2,
	exclude: Array,
	sight: Dictionary,
) -> bool:
	_restarts += 1
	if _restarts > VisionSliceConfig.restart_cap:
		causes["cap"] += 1
		return _whole(space, eye, facing, exclude, sight)
	causes["restarts"] += 1
	_begin(space, eye, facing, exclude, sight)
	return _step()


## Build the cone from the live pose in this one frame, and publish it.
func _whole(
	space: PhysicsDirectSpaceState2D,
	eye: Vector2,
	facing: Vector2,
	exclude: Array,
	sight: Dictionary,
) -> bool:
	_begin(space, eye, facing, exclude, sight)
	_cone.step(1 << 60)
	causes["units"] += _cone.work_units()
	return _publish()


## Step the job one slice; true when it is done and published.
func _step() -> bool:
	var before := _cone.work_units()
	var done := _cone.step(VisionSliceConfig.slice_units)
	causes["units"] += _cone.work_units() - before
	return done and _publish()


## The job is done (the cone swapped its result in): the pose it was begun for is the cone's.
func _publish() -> bool:
	published += 1
	_has_cone = true
	_restarts = 0
	pose_eye = job_eye
	pose_facing = job_facing
	return true
