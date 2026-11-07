extends GameTest
## V1 (`docs/player-vision.md`), the pose lag: while only the viewer's eye (moved at most 5 px) or
## facing (turned at most 1 degree) differs from the last rebuild's, the cone is rebuilt at most
## every `VisionConfig.rebuild_gap` (2) physics frames, and a frame in between shows the exact cone
## of the last rebuild: a fresh cone of an eye the viewer stood at. A checker
## (`tests/_vision/cone_checker.gd`) holds every frame's polygon to a fresh reference cone of the
## pose the view last rebuilt at, counts the frames rebuilt right after a rebuilt one, and the
## frames the view held a cone while the viewer was past the bounds. Then
## - a walking viewer (2 px a frame) and a turning one (0.5 degrees a frame) rebuild at most every
##   second frame;
## - an eye moved 8 px, or a facing turned 3 degrees, in the frame after a rebuild (a frame the lag
##   would skip) is rebuilt at once;
## - a solid that comes into the world in such a frame is rebuilt at once;
## - a character that blocks (the viewer looks over only what is lower than a standing body, and
##   one stands in the way) is rebuilt every frame the viewer walks, and the frame after;
## - the memory paints only cones the view built.
## The sight numbers' own case is `vision/view_watch_suite`'s.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Checker := preload("res://tests/_vision/cone_checker.gd")
const EYE_AT := Vector2(200, 300)
## A character in the viewer's way, east of it.
const STANDER_AT := Vector2(400, 300)
## The viewer's step in a frame (px) and its turn (degrees): inside the lag's bounds (5 px, 1
## degree).
const WALK := Vector2(2.0, 0.0)
const TURN := 0.5
const FRAMES := 40
## A jump past the bounds: px, degrees.
const JUMP := 8.0
const SWING := 3.0
## The most rebuilds in `FRAMES` frames at one every second frame, and the fewest that show the
## pose did change the cone.
const MOST := 21
const LEAST := 15
## How long to wait for a rebuild to line the next frame up as one the lag would skip.
const SYNC_FRAMES := 14
## A solid that comes into the cone, in the world.
const NEW_SOLID_AT := Vector2(450, 330)

var _t: TestContext
var _view: PlayerView
var _checker: Checker
var _eye: Node2D
## The polygons the memory's painter held, one a frame.
var _painted: Array[PackedVector2Array] = []


func describe() -> Dictionary:
	return {
		"name": "The cone lags a little pose change by at most a frame",
		"description": "While only the eye (5 px) or the facing (1 degree) changes the cone is "
			+ "rebuilt at most every second frame, a skipped frame shows the last rebuild's "
			+ "exact cone, and a jump past the bounds, a new solid or a character that blocks "
			+ "is rebuilt at once.",
		"tags": ["vision"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, EYE_AT)
	s.switch(&"vision.enabled", true)
	s.set_static(CharacterVisionConfig, &"see_over_coverage", Probe.LOOK_OVER_LOW)
	s.actor(&"stander", &"puppet", STANDER_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	_t = t
	_view = Probe.view(t)
	if not t.require(_view != null, "the world has a view"):
		return
	_eye = t.actor(&"eye")
	if not t.require(await Probe.place(t, _eye, EYE_AT, Vector2.RIGHT), "the viewer faces east"):
		return
	_checker = Checker.new(_view, _eye)
	t.world.add_child(_checker)
	await t.frames(3)
	await _blocking_character()
	if not await _crouch_stander():
		return
	await _walking()
	await _turning()
	await _jumps()
	await _new_solid()
	_whole()


## The character stands in the way and blocks the viewer's sight: every frame of a walk rebuilds.
func _blocking_character() -> void:
	var before := _view.rebuilds()
	for i in 12:
		_eye.global_position += WALK
		await _t.frames(1)
	_t.check(
		_view.rebuilds() - before == 12,
		"a viewer walking before a character that blocks rebuilds every frame (%d in 12)"
		% (_view.rebuilds() - before),
	)
	_t.check(_checker.lag.back_to_back >= 11, "premise: those rebuilds came back to back")


## The character crouches and no longer blocks; the viewer is put back where it started.
func _crouch_stander() -> bool:
	var stander := _t.actor(&"stander")
	if not _t.require(
		await _t.until(func(): return stander.movement.set_posture(&"crouch"), 3.0),
		"the character crouches",
	):
		return false
	await _t.frames(5)
	return _t.require(await Probe.place(_t, _eye, EYE_AT, Vector2.RIGHT), "the viewer faces east")


## The viewer walks `FRAMES` frames at `WALK` a frame.
func _walking() -> void:
	var before := _view.rebuilds()
	var back := _checker.lag.back_to_back
	for i in FRAMES:
		_eye.global_position += WALK
		await _t.frames(1)
		_paint_sample()
	_lag_checks("a walking viewer", before, back)


## The viewer turns `FRAMES` frames at `TURN` degrees a frame.
func _turning() -> void:
	var before := _view.rebuilds()
	var back := _checker.lag.back_to_back
	for i in FRAMES:
		_aim(float(i + 1) * TURN)
		await _t.frames(1)
		_paint_sample()
	_lag_checks("a turning viewer", before, back)


func _lag_checks(who: String, before: int, back: int) -> void:
	var rebuilds := _view.rebuilds() - before
	_t.check(
		rebuilds <= MOST,
		"%s rebuilds at most every second frame (%d in %d)" % [who, rebuilds, FRAMES],
	)
	_t.check(
		rebuilds >= LEAST,
		"premise: %s changes the cone, so it still rebuilds (%d in %d)" % [who, rebuilds, FRAMES],
	)
	_t.check(
		_checker.lag.back_to_back == back,
		"%s never rebuilds in two frames running (%d did)" % [
			who,
			_checker.lag.back_to_back - back,
		],
	)


## A jump past the bounds in a frame the lag would skip is rebuilt in that frame.
func _jumps() -> void:
	_t.require(await Probe.place(_t, _eye, EYE_AT, Vector2.RIGHT), "the viewer faces east")
	await _sync()
	var before := _view.rebuilds()
	_eye.global_position += Vector2(0.0, JUMP)
	await _t.frames(1)
	_t.check(_view.rebuilds() == before + 1, "an eye moved %d px is rebuilt at once" % JUMP)
	await _sync()
	before = _view.rebuilds()
	_aim(SWING)
	await _t.frames(2)
	_t.check(
		_view.rebuilds() == before + 1,
		"a facing turned %d degrees is rebuilt as soon as it has turned" % SWING,
	)


## A solid that joins the world with the eye moved a pixel is rebuilt in that frame.
func _new_solid() -> void:
	await _sync()
	var before := _view.rebuilds()
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.SOLID
	body.position = NEW_SOLID_AT
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30.0, 30.0)
	shape.shape = rect
	body.add_child(shape)
	_t.world.add_child(body)
	_eye.global_position += Vector2(1.0, 0.0)
	await _t.frames(1)
	_t.check(_view.rebuilds() == before + 1, "a solid that joins the world is rebuilt at once")


## Wait until the view has just rebuilt, so that the next frame is one the lag would skip.
func _sync() -> void:
	var before := _view.rebuilds()
	_t.require(
		await _t.until(func() -> bool: return _view.rebuilds() != before, 0.25),
		"the view rebuilds (the backstop) within %d frames" % SYNC_FRAMES,
	)


## Face `degrees` off east.
func _aim(degrees: float) -> void:
	_t.puppet(&"eye").aim_at(_eye.global_position + Vector2.from_angle(deg_to_rad(degrees)) * 100.0)


## Keep what the memory's painter holds this frame.
func _paint_sample() -> void:
	var points: PackedVector2Array = _view.painter().points()
	_painted.append(points.slice(0, _view.cone().size()))


func _whole() -> void:
	_t.check(
		_checker.wrong() == 0,
		"every frame held a fresh cone of the pose of the last rebuild: %s" % _checker.report(),
	)
	_t.check(
		_checker.lag.past_bounds == 0,
		"%d frames held a cone past the lag's bounds" % _checker.lag.past_bounds,
	)
	var foreign := 0
	for painted in _painted:
		if not _checker.lag.real_cones.has(painted):
			foreign += 1
	_t.check(
		_painted.size() >= 2 * FRAMES and foreign == 0,
		"the memory painted only cones the view built (%d of %d were not)"
		% [foreign, _painted.size()],
	)
