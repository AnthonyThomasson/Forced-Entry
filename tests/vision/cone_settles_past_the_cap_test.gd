extends GameTest
## V1 (`docs/player-vision.md`), the restart cap: a wardrobe that moves a little in every frame
## restarts the cone's job twice, and the third is a settling job, not a whole build in one frame:
## it goes on through moves of under `VisionSliceConfig.settle_px` from where it began (the cone it
## publishes is the world's to that, and the job after it starts at once, so the cone then is the
## reference cone of the world as it stands). A wardrobe that moves more than that in a frame is
## still built whole at the cap. Held to: no whole build and a settling job for the slow wardrobe,
## no settling job and a whole build for the fast one, a cone published at least every
## `SETTLED_BETWEEN` frames either way, the cones all of the live pose, the cone after the move is
## the reference cone, and the checker's other frames exact (`tests/_vision/cone_checker.gd`). A
## settling job's cone is held to its own bounds: the wardrobe lags the job's snapshot by at most
## `settle_px` when it is published (`ViewWatch.lag`; 2x for a piece that reverses), and the cone
## differs from the live reference by an area that is more than none and at most
## `Checker.SETTLE_AREA`. A change of the sight past the cap is built whole, as the doc says.

const RawTwins := preload("res://tests/_vision/raw_twins.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
const Checker := preload("res://tests/_vision/cone_checker.gd")
const Mover := preload("res://tests/_vision/physics_mover.gd")
const Reference := preload("res://tests/_vision/reference_view_cone.gd")
const EYE_AT := Vector2(200, 300)
## A slice that makes a job of this house three frames (the corners are priced at one).
const SLICE := 140
const WARDROBE_AT := Vector2(450, 300)
const SIZE := Vector2(30.0, 60.0)
## The frames the wardrobe moves, and its step (px) a frame, slow (a settling job's bound is
## `VisionSliceConfig.settle_px`, 1 px, for a whole job) and fast.
const MOVE_FRAMES := 14
const SLOW_STEP := 0.15
const FAST_STEP := 3.0
## The speed limit: a job here is a start and two more ticks, so a wardrobe that moves `settle_px`
## in the two frames after the start (0.5 px a frame) still fits its bound, the cone it publishes
## the widest a settling job's is; 0.75 px a frame leaves the bound inside the job, which is built
## whole at its restart.
const LIMIT_STEP := 0.5
const PAST_LIMIT_STEP := 0.75
## The most frames between two cones published while the wardrobe moves slowly: a start, the two
## restarts, the settling job's own slices.
const SETTLED_BETWEEN := 8
## The most a rounding of the lag may add to its bound.
const EPSILON := 0.001
## What the viewer's view distance is changed to, and from, each frame of the sight's phase.
const SIGHT_FLIP := 20.0

var _t: TestContext
var _view: PlayerView
var _checker: Checker
var _eye: Node2D
var _wardrobe: RawTwins.Solid
var _hand: Mover


func describe() -> Dictionary:
	return {
		"name": "A job past the restart cap settles through slow moves and is whole for fast ones",
		"description": "A wardrobe that moves under a pixel in every frame restarts the job twice "
			+ "and then settles it (no whole build), the next cone is the reference; one that "
			+ "moves three pixels a frame is built whole at the cap.",
		"tags": ["vision"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, EYE_AT)
	s.switch(&"vision.enabled", true)
	s.set_static(VisionSliceConfig, &"slice_units", SLICE)
	s.set_static(VisionSliceConfig, &"cost_shape", SLICE)
	s.set_static(CharacterVisionConfig, &"view_distance", CharacterVisionConfig.view_distance)
	s.view(&"eye")


func run(t: TestContext) -> void:
	_t = t
	Probe.twin_bare_solids(t.world)
	_view = Probe.view(t)
	if not t.require(_view != null, "the world has a view"):
		return
	_eye = t.actor(&"eye")
	if not t.require(await Probe.place(t, _eye, EYE_AT, Vector2.RIGHT), "the viewer faces east"):
		return
	_wardrobe = RawTwins.Solid.new()
	var shape := RawTwins.Shape.new()
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	shape.shape = rect
	_wardrobe.add_child(shape)
	_wardrobe.position = WARDROBE_AT
	t.world.add_child(_wardrobe)
	_hand = Mover.new()
	_hand.body = _wardrobe
	t.world.add_child(_hand)
	_checker = Checker.new(_view, _eye)
	t.world.add_child(_checker)
	if not await _settled():
		return
	await _moves(SLOW_STEP, true)
	_area_held("slow")
	await _moves(LIMIT_STEP, true)
	_area_held("at the limit")
	await _moves(PAST_LIMIT_STEP, false, false)
	await _moves(FAST_STEP, false)
	t.check(
		_checker.wrong() == 0,
		"every cone published but a settling job's was the reference cone of its pose: %s"
		% _checker.report(),
	)
	_checker.queue_free()
	await _sight_change()


## The worst settling job's cone so far is off the live world by some area and at most
## `SETTLE_AREA`.
func _area_held(what: String) -> void:
	var worst := _checker.worst_settled_area
	_t.check(
		worst > 0.0 and worst <= Checker.SETTLE_AREA,
		"%s: a settling job's cone is off the world by 0 < area <= %s px^2 (%.1f)"
		% [what, Checker.SETTLE_AREA, worst],
	)


## The wardrobe moves `step` px in each of `MOVE_FRAMES` frames; `slow` says it settles.
func _moves(step: float, slow: bool, none_settles := true) -> void:
	var what := "a wardrobe moving %s px a frame" % step
	_wardrobe.position = WARDROBE_AT
	if not await _rested():
		return
	var before := _view.rebuild_causes()
	var seen := await _moving(step, false)
	var after := _view.rebuild_causes()
	var whole: int = after["cap"] - before["cap"]
	var settled: int = after["settled"] - before["settled"]
	_t.check(seen["cones"] > 0, "%s: cones are published" % what)
	_t.check(
		seen["live"] == seen["cones"],
		"%s: each cone is of the live pose (%d of %d)" % [what, seen["live"], seen["cones"]],
	)
	if slow:
		_t.check(
			settled >= 1 and whole == 0,
			"%s: the job past the cap settles, no whole build (%d settled, %d whole)"
			% [what, settled, whole],
		)
		_t.check(seen["settled_cones"] >= 1, "%s: a cone of a settling job is published" % what)
		_t.check(
			seen["lag"] <= VisionSliceConfig.settle_px + EPSILON,
			"%s: the wardrobe lags the job by at most settle_px when it is published (%.3f)"
			% [what, seen["lag"]],
		)
		_t.check(
			seen["longest"] <= SETTLED_BETWEEN,
			"%s: a cone at least every %d frames (%d)" % [what, SETTLED_BETWEEN, seen["longest"]],
		)
	elif not none_settles:
		_t.check(
			whole >= 1,
			"%s: past the speed limit the job past the cap is built whole (%d whole, %d settled)"
			% [what, whole, settled],
		)
	else:
		_t.check(
			whole >= 1 and settled == 0,
			"%s: the job past the cap is built whole (%d whole, %d settled)" % [
				what,
				whole,
				settled,
			],
		)
		_t.check(seen["settled_cones"] == 0, "%s: no cone of a settling job" % what)
	_t.check(await _rested(), "%s: once it stops, the cone is the reference cone" % what)


## The viewer's sight changes in every frame the wardrobe creeps (`SIGHT_FLIP` px of view distance,
## back and forth): a restart each frame, so the third in a row is a change of the sight, and a
## sight is none of a settling job's slow moves: built whole at the cap, none settles.
func _sight_change() -> void:
	var what := "a wardrobe creeping with the view distance changing"
	_wardrobe.position = WARDROBE_AT
	if not await _rested():
		return
	var before := _view.rebuild_causes()
	var seen := await _moving(SLOW_STEP, true)
	var after := _view.rebuild_causes()
	_t.check(seen["cones"] > 0, "%s: cones are published" % what)
	_t.check(
		after["settled"] == before["settled"] and seen["settled_cones"] == 0,
		"%s: no job settles (%d)" % [what, after["settled"] - before["settled"]],
	)
	_t.check(
		after["cap"] > before["cap"],
		"%s: the job past the cap is built whole (%d)" % [what, after["cap"] - before["cap"]],
	)


## Move the wardrobe `step` px a frame for `MOVE_FRAMES` frames, with the view distance changing
## each frame when `sight`; what was published meanwhile: the cones, those of the live pose, those
## of a settling job (and the most the wardrobe lagged the job at one) and the most frames between
## two.
func _moving(step: float, sight: bool) -> Dictionary:
	var seen := { "cones": 0, "live": 0, "settled_cones": 0, "longest": 0, "lag": 0.0 }
	var gap := -1
	var base := CharacterVisionConfig.view_distance
	for i in MOVE_FRAMES + 1:
		if i < MOVE_FRAMES:
			_hand.arm(WARDROBE_AT + Vector2(0.0, step * float(i + 1)))
		if sight:
			CharacterVisionConfig.view_distance = base - SIGHT_FLIP * float(i % 2)
		var count := _view.rebuilds()
		await _t.frames(1)
		gap += 1
		if _view.rebuilds() == count:
			continue
		seen["longest"] = maxi(seen["longest"], gap)
		gap = 0
		seen["cones"] += 1
		if _view.settled_publish():
			seen["settled_cones"] += 1
			seen["lag"] = maxf(seen["lag"], _view.creep_lag())
		var pose := _view.published_pose()
		seen["live"] += int(pose["eye"] == _eye.global_position)
	CharacterVisionConfig.view_distance = base
	return seen


## Wait until no job is in flight and the cone is the reference cone of the world as it stands.
func _rested() -> bool:
	await _t.frames(3)
	return _t.require(
		await _t.until(
			func() -> bool:
				return not _view.building() and _published_is(_reference()),
			1.5,
		),
		"the view's cone is the reference cone of the world as it stands",
	)


func _settled() -> bool:
	return _t.require(
		await _t.until(func() -> bool: return not _view.building(), 1.0), "the view's job ends"
	)


func _reference() -> Reference:
	var cone := Reference.new()
	cone.rebuild(
		Probe.space(_t),
		_eye.global_position,
		_eye.get("facing"),
		SightRay.exclude_of(_eye),
		_eye.sight(),
	)
	return cone


func _published_is(want: Reference) -> bool:
	return Probe.polygons_differ(_view.cone(), _view.bubble(), want.cone, want.bubble) == ""
