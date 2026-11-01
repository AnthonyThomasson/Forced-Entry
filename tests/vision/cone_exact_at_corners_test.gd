extends GameTest
## V1 (`docs/player-vision.md`): the cone is exact at corners. Eyes stand near the corners of the
## two rooms and the doorway's ends, facing along and across the walls; points sampled on rings
## round each eye and behind each nearby corner, along the eye's line past it, are checked against
## the sight rule cast directly: not one point behind a corner is inside the polygon (the cone does
## not see round it), and every point the eye sees, clear of a corner by a margin, is inside it. A
## wall that is seen shows its top: its near face is in the polygon, and the room beyond is not.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView` of the world: `sees(point)`.

const Probe := preload("res://tests/_vision/vision_probe.gd")
## How far from a corner the eyes stand, px, and in which of 8 directions.
const EYE_OFFSET := 40.0
## Samples on rings round the eye: this many angles at these distances, px.
const RING_ANGLES := 72
const RING_DISTANCES := [25.0, 70.0, 150.0, 300.0, 600.0]
## Samples behind a corner, along the eye's line to it offset by these angles (degrees), this far
## past it (px), for corners within `CORNER_REACH`.
const BEHIND_ANGLES := [-3.0, -1.2, 1.2, 3.0]
const BEHIND_DISTANCES := [12.0, 40.0, 120.0, 350.0]
const CORNER_REACH := 450.0
## A sample this near something solid is left out, px.
const SOLID_MARGIN := 4.0
## A seen sample must also have a clear line this far to either side, px; a sample is behind a
## corner when the lines this far to either side are blocked too and the blocker is this much
## nearer.
const SIDE_MARGIN := 2.5
const BEHIND_MARGIN := 3.0
## At least this many samples of each kind must be checked, or the test proves nothing.
const MIN_BEHIND := 400
const MIN_SEEN := 1500

var _leaks := 0
var _missed := 0
var _behind := 0
var _seen := 0
var _t: TestContext
var _view: PlayerView
var _at := Vector2.ZERO
var _dir := Vector2.RIGHT
var _exclude: Array = []


func describe() -> Dictionary:
	return {
		"name": "The view's cone is exact at corners",
		"description": "From eyes near room corners and a doorway's ends, no point behind a corner "
			+ "is in the cone polygon and every point the eye sees is; a seen wall's near face is "
			+ "in it and the room beyond is not.",
		"tags": ["vision"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, Vector2(200, 300))
	s.switch(&"vision.enabled", true)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var eye := t.actor(&"eye")
	var view := Probe.view(t)
	if not t.require(view != null, "the world has a view"):
		return
	_view = view
	await t.frames(2)
	var corners := _corners()
	for at in _eyes(t, corners):
		for dir in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			if not await Probe.place(t, eye, at, dir):
				t.check(false, "the eye at %s faces %s" % [at, dir])
				return
			_check(t, eye, at, dir, corners)
	t.check(_leaks == 0, "%d of %d points behind a corner are inside the cone" % [_leaks, _behind])
	t.check(_missed == 0, "%d of %d seen points are outside the cone" % [_missed, _seen])
	t.check(_behind >= MIN_BEHIND, "premise: %d points behind corners checked" % _behind)
	t.check(_seen >= MIN_SEEN, "premise: %d seen points checked" % _seen)
	await _check_wall_top(t, view, eye)


## Every corner a view is judged round: the rooms' corners and the doorway's two ends.
func _corners() -> Array:
	var corners: Array = []
	for room in Probe.ROOMS:
		var rect: Rect2 = room["rect"]
		corners.append_array([
			rect.position, rect.position + Vector2(rect.size.x, 0.0),
			rect.end, rect.position + Vector2(0.0, rect.size.y),
		])
	var half: float = Probe.DOOR["width"] * 0.5
	corners.append(Probe.DOOR["pos"] + Vector2(0.0, half))
	corners.append(Probe.DOOR["pos"] - Vector2(0.0, half))
	return corners


## The eyes: `EYE_OFFSET` from each corner in 8 directions, on a room's floor and clear of solids.
func _eyes(t: TestContext, corners: Array) -> Array:
	var eyes: Array = []
	for corner: Vector2 in corners:
		for k in 8:
			var at := corner + Vector2.RIGHT.rotated(float(k) * PI * 0.25) * EYE_OFFSET
			if _on_a_floor(at) and not Probe.solid_near(t, at, 20.0):
				eyes.append(at)
	return eyes


func _on_a_floor(point: Vector2) -> bool:
	for room in Probe.ROOMS:
		if (room["rect"] as Rect2).grow(-14.0).has_point(point):
			return true
	return false


## Test every sample for the eye `at` facing `dir`.
func _check(t: TestContext, eye: Node2D, at: Vector2, dir: Vector2, corners: Array) -> void:
	_t = t
	_at = at
	_dir = dir
	_exclude = [eye.get_rid()]
	for i in RING_ANGLES:
		var ray := Vector2.from_angle((float(i) + 0.5) / RING_ANGLES * TAU)
		for dist: float in RING_DISTANCES:
			_test(at + ray * dist)
	for corner: Vector2 in corners:
		var to := corner - at
		if to.length() < 8.0 or to.length() > CORNER_REACH:
			continue
		for angle: float in BEHIND_ANGLES:
			for past: float in BEHIND_DISTANCES:
				_test(at + to.normalized().rotated(deg_to_rad(angle)) * (to.length() + past))


## Test one sample of the current eye: behind a corner it must be outside the cone, seen it must be
## inside.
func _test(sample: Vector2) -> void:
	if Probe.solid_near(_t, sample, SOLID_MARGIN):
		return
	var hit := Probe.blocker(_t, _at, sample, _exclude)
	if hit.is_empty():
		_test_seen(sample)
	elif _at.distance_to(hit["position"]) < _at.distance_to(sample) - BEHIND_MARGIN:
		_test_behind(sample)


func _test_behind(sample: Vector2) -> void:
	if not _blocked_either_side(sample):
		return
	_behind += 1
	if _view.sees(sample):
		_leaks += 1
		if _leaks <= 5:
			_t.trace("leak eye %s facing %s sample %s" % [_at, _dir, sample], 1.0)


func _test_seen(sample: Vector2) -> void:
	if not (_well_inside(sample) and _clear_either_side(sample)):
		return
	_seen += 1
	if not _view.sees(sample):
		_missed += 1
		if _missed <= 5:
			_t.trace("missed eye %s facing %s sample %s" % [_at, _dir, sample], 1.0)


## Whether `sample` is well inside the bubble or the cone and the reach, off their edges where the
## margin of the sampling would be the answer rather than the polygon.
func _well_inside(sample: Vector2) -> bool:
	var dist := _at.distance_to(sample)
	if dist <= Probe.BUBBLE - SIDE_MARGIN:
		return true
	var half := deg_to_rad(Probe.FOV) * 0.5 - 0.02
	return dist <= Probe.REACH - 5.0 and absf(_dir.angle_to(sample - _at)) <= half


func _side(sample: Vector2) -> Vector2:
	return (sample - _at).orthogonal().normalized() * SIDE_MARGIN


func _clear_either_side(sample: Vector2) -> bool:
	var side := _side(sample)
	return (
		Probe.blocker(_t, _at, sample + side, _exclude).is_empty()
		and Probe.blocker(_t, _at, sample - side, _exclude).is_empty()
	)


func _blocked_either_side(sample: Vector2) -> bool:
	var side := _side(sample)
	return (
		not Probe.blocker(_t, _at, sample + side, _exclude).is_empty()
		and not Probe.blocker(_t, _at, sample - side, _exclude).is_empty()
	)


## An eye facing a wall that has no doorway in it sees the wall's top: the polygon runs on to the
## wall's far face, and the room beyond is out of it.
func _check_wall_top(t: TestContext, view: PlayerView, eye: Node2D) -> void:
	var at := Vector2(400, 420)
	if not t.require(await Probe.place(t, eye, at, Vector2.RIGHT), "the eye faces the wall"):
		return
	var exclude: Array = [eye.get_rid()]
	var wall := Probe.blocker(t, at, Vector2(1100, 420), exclude)
	if not t.require(not wall.is_empty(), "premise: a wall stands east of the eye"):
		return
	var near: Vector2 = wall["position"]
	# The face of the room beyond, found from the far side with the line reversed.
	var far := Probe.blocker(t, Vector2(1100, 420), at, [])
	if not t.require(not far.is_empty(), "premise: the wall has a far face"):
		return
	var far_face: Vector2 = far["position"]
	t.check(near.x < far_face.x, "premise: the wall has a thickness (%s to %s)" % [near, far_face])
	t.check(view.sees(near + Vector2(3, 0)), "a point just inside the seen wall is in the cone")
	t.check(not view.sees(far_face + Vector2(40, 0)), "the room beyond the wall is not in the cone")
