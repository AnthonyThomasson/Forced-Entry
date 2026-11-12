extends GameTest
## V1 (`docs/player-vision.md`), the cone's pipeline: a stale view starts a job from the viewer's
## live pose and steps it a slice each physics frame (`VisionSliceConfig.slice_units`); the cone it
## publishes is the exact cone of that pose, so it is as old as the job is long (2 to 4 frames for a
## job of 3 slices), never a made-up pose. A checker (`tests/_vision/cone_checker.gd`) holds every
## published cone to a fresh reference cone of the pose the view says it is of, and the cone held
## between two publishes to the one before; `tests/_vision/cone_age.gd` says how old each frame's
## cone is. The slice is small here so that a job of this little house takes three frames. Then
## - a walking viewer (2 px a frame) and a turning one (0.5 degrees a frame) show cones at most 4
##   frames old, every one of a pose the viewer stood at, and a pose change alone never restarts a
##   job (a job is started per cone published, one in flight apart);
## - an eye jumped past the bound (a teleport, a vehicle: 60 px) has its cone built whole in that
##   very frame, and a facing turned 90 degrees at once is not a jump but a pose change;
## - a character that blocks (the viewer looks over only what is lower than a standing body, and
##   one stands in the way) is a change of the world in every frame: a job is started or restarted
##   every frame, and after two restarts in a row the third frame builds the cone whole, so a cone
##   is published at least every fourth frame;
## - the memory paints only cones the view published.
## The sight numbers' own case is `vision/view_watch_suite`'s; a world that changes between slices:
## `vision/cone_restarts_on_world_change`.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Checker := preload("res://tests/_vision/cone_checker.gd")
const EYE_AT := Vector2(200, 300)
## A character in the viewer's way, east of it.
const STANDER_AT := Vector2(400, 300)
## The slice (units) that makes a job of this house three frames.
const SLICE := 90
## The viewer's step in a frame (px) and its turn (degrees).
const WALK := Vector2(2.0, 0.0)
const TURN := 0.5
const FRAMES := 40
## The eye's jump (px) past the bound of the spec (48), and a turn at once (degrees).
const JUMP := 60.0
const SWING := 90.0
## Half of `JUMP` (px): inside the bound by itself.
const HALF_JUMP := 30.0
## The spec's restart cap, and the most frames between two publishes while the world changes in
## every one: a start, the restarts, and the whole build.
const CAP := 2
const MOST_BETWEEN := CAP + 2
## The oldest a cone may be in a job of three slices (frames), and the youngest the walk must show
## to prove the job is sliced.
const OLDEST := 4
const YOUNGEST := 2

var _t: TestContext
var _view: PlayerView
var _checker: Checker
var _eye: Node2D
## The polygons the memory's painter held, one a frame.
var _painted: Array[PackedVector2Array] = []


func describe() -> Dictionary:
	return {
		"name": "The cone is as old as its job is long, and of a pose the viewer stood at",
		"description": "A job steps a slice a frame from the viewer's pose and publishes its exact "
			+ "cone: at most 4 frames old for 3 slices; a pose change alone never restarts it; a "
			+ "jump past the bound is built whole at once; a world that changes every frame is "
			+ "restarted twice and then built whole.",
		"tags": ["vision"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, EYE_AT)
	s.switch(&"vision.enabled", true)
	s.set_static(CharacterVisionConfig, &"see_over_coverage", Probe.LOOK_OVER_LOW)
	s.set_static(VisionSliceConfig, &"slice_units", SLICE)
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
	_whole()


## The character stands in the way and blocks the viewer's sight: the world changes every frame,
## so a job is started or restarted every frame, and the third restart is a whole build.
func _blocking_character() -> void:
	var starts := _view.starts()
	var published := _view.rebuilds()
	for i in 12:
		_eye.global_position += WALK
		await _t.frames(1)
	_t.check(
		_view.starts() - starts == 12,
		"a viewer walking before a blocker starts or restarts a job every frame (%d in 12)"
		% (_view.starts() - starts),
	)
	_t.check(
		_view.rebuilds() - published >= 12.0 / MOST_BETWEEN,
		"a cone is published at least every %d frames (%d in 12)"
		% [MOST_BETWEEN, _view.rebuilds() - published],
	)


## The character crouches and no longer blocks; the viewer is put back where it started.
func _crouch_stander() -> bool:
	var stander := _t.actor(&"stander")
	if not _t.require(
		await _t.until(func(): return stander.movement.set_posture(&"crouch"), 3.0),
		"the character crouches",
	):
		return false
	await _t.frames(8)
	if not _t.require(await Probe.place(_t, _eye, EYE_AT, Vector2.RIGHT), "the viewer faces east"):
		return false
	return await _settled()


## The viewer walks `FRAMES` frames at `WALK` a frame.
func _walking() -> void:
	var before := _counts()
	for i in FRAMES:
		_eye.global_position += WALK
		await _t.frames(1)
		_paint_sample()
	_age_checks("a walking viewer", before)


## The viewer turns `FRAMES` frames at `TURN` degrees a frame.
func _turning() -> void:
	var before := _counts()
	for i in FRAMES:
		_aim(float(i + 1) * TURN)
		await _t.frames(1)
		_paint_sample()
	_age_checks("a turning viewer", before)


## `[starts, publishes]`.
func _counts() -> Array[int]:
	return [_view.starts(), _view.rebuilds()]


func _age_checks(who: String, before: Array[int]) -> void:
	var published := _view.rebuilds() - before[1]
	var started := _view.starts() - before[0]
	_t.check(
		_checker.age.max_age <= OLDEST,
		"%s's cone is at most %d frames old (%d)" % [who, OLDEST, _checker.age.max_age],
	)
	_t.check(
		_checker.age.max_age >= YOUNGEST,
		"premise: %s's job takes frames, so its cone lags (oldest %d)" % [
			who,
			_checker.age.max_age,
		],
	)
	_t.check(
		published >= float(FRAMES) / (OLDEST + 1) and published <= float(FRAMES) / 2.0,
		"premise: %s still publishes, one cone per job (%d in %d)" % [who, published, FRAMES],
	)
	_t.check(
		started - published <= 1,
		"%s changes the pose only, so no job is restarted (%d started, %d published)"
		% [who, started, published],
	)
	_t.check(
		_checker.age.foreign == 0,
		"%s's cone was always of a pose the viewer stood at (%d frames were not)"
		% [who, _checker.age.foreign],
	)


## An eye past the bound is built whole in the frame it jumps in; a facing turned at once is a
## pose change.
func _jumps() -> void:
	_t.require(await Probe.place(_t, _eye, EYE_AT, Vector2.RIGHT), "the viewer faces east")
	if not await _settled():
		return
	var before := _view.rebuilds()
	var at := _eye.global_position + Vector2(0.0, JUMP)
	_eye.global_position = at
	await _t.frames(1)
	_t.check(_view.rebuilds() == before + 1, "an eye moved %d px is built whole at once" % JUMP)
	_t.check(
		_view.published_pose()["eye"] == at and not _view.building(),
		"the cone built whole is of the eye's new place",
	)
	if not await _settled():
		return
	before = _view.rebuilds()
	_aim(SWING)
	await _t.frames(1)
	_t.check(
		_view.rebuilds() == before and _view.building(),
		"a facing turned %d degrees is a job over some frames, not a jump" % SWING,
	)
	await _jump_in_flight()


## An eye that comes to be past the bound from the cone shown, while a job (begun from an eye still
## inside the bound) is in flight, is built whole in that frame: the bound is the cone shown's, so
## it is never more than the bound behind. Two steps of `HALF_JUMP` each: the first is a job, the
## second is 60 px from the cone shown and 30 from the job's eye.
func _jump_in_flight() -> void:
	if not await _settled():
		return
	_eye.global_position += Vector2(0.0, HALF_JUMP)
	if not _t.require(
		await _t.until(func() -> bool: return _view.building(), 0.5), "a step of 30 px starts a job"
	):
		return
	var before := _view.rebuilds()
	var at := _eye.global_position + Vector2(0.0, HALF_JUMP)
	_eye.global_position = at
	await _t.frames(1)
	_t.check(
		_view.rebuilds() == before + 1 and _view.published_pose()["eye"] == at,
		"an eye %d px from the cone shown, with a job in flight, is built whole at once" % JUMP,
	)


## Wait until the view is not building (a published cone is the newest there is).
func _settled() -> bool:
	return _t.require(
		await _t.until(func() -> bool: return not _view.building(), 0.5), "the view's job ends"
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
		"every published cone was a fresh cone of its pose, and held until the next: %s"
		% _checker.report(),
	)
	var foreign := 0
	for painted in _painted:
		if not _checker.age.real_cones.has(painted):
			foreign += 1
	_t.check(
		_painted.size() >= 2 * FRAMES and foreign == 0,
		"the memory painted only cones the view published (%d of %d were not)"
		% [foreign, _painted.size()],
	)
