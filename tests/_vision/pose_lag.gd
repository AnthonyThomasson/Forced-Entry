extends RefCounted
## Test helper (not a test): what `tests/_vision/cone_checker.gd` knows of the view's pose lag
## (`docs/player-vision.md` V1). It remembers the pose the viewer had when the view last rebuilt,
## which is the pose the view's cone is of; counts the frames rebuilt right after a rebuilt frame;
## counts the frames the view held a cone while the viewer was past the lag's bounds from that
## pose; and keeps the cone of every rebuild, the cones the memory may paint.

## The spec's bounds of the lag: the eye (px) and the facing (degrees) may differ this much from
## the last rebuild's in a frame the view does not rebuild, with a little slack for the float.
const EYE := 5.0
const FACING := 1.0
const SLACK := 0.001

## The pose of the last rebuild.
var eye := Vector2.ZERO
var facing := Vector2.ZERO
## Frames rebuilt right after a frame that was rebuilt too.
var back_to_back := 0
## Frames the view did not rebuild whose viewer lay past the bounds from the last rebuild's pose.
var past_bounds := 0
## The cone of each rebuild.
var real_cones: Array[PackedVector2Array] = []
var _was_rebuilt := false


## One frame: the viewer stands at `at` facing `looking`, the view's cone is `cone`, and whether it
## `rebuilt` in this frame. `first` for the checker's first frame (the pose it starts from).
func frame(
	at: Vector2, looking: Vector2, cone: PackedVector2Array, rebuilt: bool, first: bool
) -> void:
	if rebuilt and _was_rebuilt:
		back_to_back += 1
	_was_rebuilt = rebuilt
	if rebuilt or first:
		eye = at
		facing = looking
		real_cones.append(cone.duplicate())
	elif _past_bounds(at, looking):
		past_bounds += 1


## Whether a viewer at `at` facing `looking` lies past the bounds from the last rebuild's pose.
func _past_bounds(at: Vector2, looking: Vector2) -> bool:
	if at.distance_to(eye) > EYE + SLACK:
		return true
	if looking == facing:
		return false
	if looking == Vector2.ZERO or facing == Vector2.ZERO:
		return true
	return absf(rad_to_deg(looking.angle_to(facing))) > FACING + SLACK
