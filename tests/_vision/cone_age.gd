extends RefCounted
## Test helper (not a test): how old the cone the view shows is (`docs/player-vision.md` V1: a
## published cone is the fresh cone of the pose the viewer had when its job started). It keeps the
## pose the viewer had in every frame, and in each frame says how many frames ago the viewer stood
## at the pose the published cone is of (the cone's age; 0 when it stands there now), the largest
## age seen, the frames the pose is one the viewer never stood at, and the cone of every publish:
## the cones the memory may paint.

## The viewer's pose in each frame so far, `[eye, facing]`.
var history: Array = []
## The largest age (frames) the published cone had in a frame.
var max_age := 0
## Frames whose published pose is one the viewer stood at in no frame since the checker began.
var foreign := 0
## The cone of each publish.
var real_cones: Array[PackedVector2Array] = []
## The age in the last frame (-1: a pose the viewer never stood at).
var age := 0


## One frame: the viewer stands at `at` facing `looking`; the view's published pose is `pose`
## (`PlayerView.published_pose()`), its cone `cone`, and whether it `published` in this frame.
func frame(
	at: Vector2, looking: Vector2, pose: Dictionary, cone: PackedVector2Array, published: bool
) -> void:
	history.append([at, looking])
	if published:
		real_cones.append(cone.duplicate())
	age = _age_of(pose)
	if age < 0:
		foreign += 1
	else:
		max_age = maxi(max_age, age)


## Frames since the viewer last stood at `pose`; -1 when it never did.
func _age_of(pose: Dictionary) -> int:
	for back in history.size():
		var then: Array = history[history.size() - 1 - back]
		if then[0] == pose["eye"] and then[1] == pose["facing"]:
			return back
	return -1
