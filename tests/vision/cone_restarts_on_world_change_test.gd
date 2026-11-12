extends GameTest
## V1 (`docs/player-vision.md`), the world changing under a job: a job steps a slice a frame, so a
## blocker may move, or join, between its slices. The cone published is never a mix of two worlds:
## the job is dropped and started again from the viewer's live pose (a restart, counted by
## `PlayerView.starts()`), and the cone it publishes is the fresh reference cone of its pose in the
## world as it is then. The slice is small (a job of this house takes three frames) and the viewer
## stands still, so the pose is the same before and after, and the reference cones of the two worlds
## differ only by the change. Then
## - a wardrobe moved once from its own physics frame, between slices (as a door swings): the job
##   restarts, and the cone published is the reference cone of the world after the move, not the
##   one the job began on, and not a mix;
## - a solid that joins the world between slices: likewise;
## - a wardrobe moved in every frame: a job is started or restarted every frame and, after two
##   restarts in a row, the third is built whole in that frame, so a cone is published at least
##   every fourth frame, of the viewer's live pose, however long the wardrobe moves.
## The cone held while a job runs is the last published, whole (`tests/_vision/cone_checker.gd`
## holds that, and every published cone to the reference cone of its pose, in every frame).

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Checker := preload("res://tests/_vision/cone_checker.gd")
const Mover := preload("res://tests/_vision/physics_mover.gd")
const Reference := preload("res://tests/_vision/reference_view_cone.gd")
const EYE_AT := Vector2(200, 300)
## The slice (units) that makes a job of this house three frames.
const SLICE := 90
## Where the wardrobe stands, in the cone, and where it is moved to (and then creeps from).
const WARDROBE_AT := Vector2(450, 300)
const MOVED_TO := Vector2(450, 220)
## The solid that joins.
const JOINS_AT := Vector2(520, 340)
const SIZE := Vector2(30.0, 60.0)
## The spec's restart cap, and the most frames between two cones published while the world changes
## in every frame: a start, the restarts, and the whole build.
const CAP := 2
const MOST_BETWEEN := CAP + 2
const CREEP_FRAMES := 12
const CREEP_STEP := 3.0

var _t: TestContext
var _view: PlayerView
var _checker: Checker
var _eye: Node2D
var _wardrobe: AnimatableBody2D
var _hand: Mover
## The pose the viewer faces now, toggled so each scenario starts a job by a pose change.
var _turned := false


func describe() -> Dictionary:
	return {
		"name": "A world that changes between slices restarts the cone's job",
		"description": "A blocker moved or joined between two slices of a job drops it and starts "
			+ "it again from the live pose; the cone published is the reference cone of the "
			+ "world after the change, never a mix; a world that changes every frame is built "
			+ "whole after two restarts.",
		"tags": ["vision"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, EYE_AT)
	s.switch(&"vision.enabled", true)
	s.set_static(VisionSliceConfig, &"slice_units", SLICE)
	s.view(&"eye")


func run(t: TestContext) -> void:
	_t = t
	_view = Probe.view(t)
	if not t.require(_view != null, "the world has a view"):
		return
	_eye = t.actor(&"eye")
	if not t.require(await Probe.place(t, _eye, EYE_AT, Vector2.RIGHT), "the viewer faces east"):
		return
	_wardrobe = AnimatableBody2D.new()
	_wardrobe.collision_layer = PhysicsLayers.SOLID
	_wardrobe.add_child(_shape())
	_wardrobe.position = WARDROBE_AT
	t.world.add_child(_wardrobe)
	_hand = Mover.new()
	_hand.body = _wardrobe
	t.world.add_child(_hand)
	_checker = Checker.new(_view, _eye)
	t.world.add_child(_checker)
	if not await _settled():
		return
	await _moved_between_slices()
	await _joined_between_slices()
	await _moved_every_frame()
	_t.check(
		_checker.wrong() == 0,
		"every cone published was the reference cone of its pose, and held whole: %s"
		% _checker.report(),
	)


## The wardrobe moves once, in the frame after a job began on the world with it at `WARDROBE_AT`.
func _moved_between_slices() -> void:
	if not await _job_begun():
		return
	var then := _reference()
	var starts := _view.starts()
	_hand.arm(MOVED_TO)
	if not await _settled():
		return
	var now := _reference()
	_t.check(
		Probe.polygons_differ(then.cone, then.bubble, now.cone, now.bubble) != "",
		"premise: moving the wardrobe changes what the viewer sees",
	)
	_t.check(
		_view.starts() - starts >= 1,
		"a wardrobe moved between slices restarts the job (%d starts since)"
		% (_view.starts() - starts),
	)
	_t.check(_published_is(now), "the cone published is the reference cone of the world after")
	_t.check(
		not _published_is(then), "the cone published is not the one the job began on, nor a mix"
	)
	_wardrobe.position = WARDROBE_AT
	await _settled()


## A solid joins the world between two slices.
func _joined_between_slices() -> void:
	_wardrobe.position = WARDROBE_AT
	if not await _settled() or not await _job_begun():
		return
	var then := _reference()
	var starts := _view.starts()
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.SOLID
	body.position = JOINS_AT
	body.add_child(_shape())
	_t.world.add_child(body)
	if not await _settled():
		return
	var now := _reference()
	_t.check(
		Probe.polygons_differ(then.cone, then.bubble, now.cone, now.bubble) != "",
		"premise: the solid that joins changes what the viewer sees",
	)
	_t.check(
		_view.starts() - starts >= 1,
		"a solid that joins between slices restarts the job (%d starts since)"
		% (_view.starts() - starts),
	)
	_t.check(_published_is(now), "the cone published is the reference cone of the world after")
	body.queue_free()
	await _settled()


## The wardrobe moves in every frame: the job restarts every frame until the third restart builds
## the cone whole, from the viewer's live pose.
func _moved_every_frame() -> void:
	if not await _settled():
		return
	_wardrobe.position = WARDROBE_AT
	await _t.frames(3)
	var starts := _view.starts()
	var published := _view.rebuilds()
	var longest := 0
	var gap := 0
	var live := 0
	# The hand moves the wardrobe in the frame after it is armed, so the last place is reached in
	# the frame after the loop's arming ends.
	for i in CREEP_FRAMES + 1:
		if i < CREEP_FRAMES:
			_hand.arm(WARDROBE_AT + Vector2(0.0, CREEP_STEP * float(i + 1)))
		var before := _view.rebuilds()
		await _t.frames(1)
		gap += 1
		if _view.rebuilds() != before:
			longest = maxi(longest, gap)
			gap = 0
			var pose := _view.published_pose()
			if pose["eye"] == _eye.global_position and pose["facing"] == _eye.get("facing"):
				live += 1
	_t.check(
		_view.starts() - starts >= CREEP_FRAMES,
		"a wardrobe moved every frame starts or restarts a job every frame (%d in %d)"
		% [_view.starts() - starts, CREEP_FRAMES],
	)
	var cones := _view.rebuilds() - published
	_t.check(
		cones >= float(CREEP_FRAMES) / MOST_BETWEEN - 1.0,
		"after two restarts in a row the third frame builds the cone whole (%d cones in %d frames)"
		% [cones, CREEP_FRAMES],
	)
	_t.check(
		longest <= MOST_BETWEEN,
		"a cone is published at least every %d frames while the world changes in every one (%d)"
		% [MOST_BETWEEN, longest],
	)
	_t.check(
		live == cones, "each of them is of the viewer's live pose (%d of %d)" % [live, cones]
	)
	_wardrobe.position = WARDROBE_AT
	await _settled()


## Turn the viewer a little and wait for the frame the job it starts begins in; true when it is
## in flight after it (a job of three slices).
func _job_begun() -> bool:
	_turned = not _turned
	var starts := _view.starts()
	var angle := 0.08 if _turned else 0.0
	_t.puppet(&"eye").aim_at(_eye.global_position + Vector2.from_angle(angle) * 100.0)
	if not _t.require(
		await _t.until(func() -> bool: return _view.starts() != starts, 0.5), "a turn starts a job"
	):
		return false
	return _t.require(_view.building(), "the job started is in flight (it has slices to go)")


## Wait until no job is in flight.
func _settled() -> bool:
	return _t.require(
		await _t.until(func() -> bool: return not _view.building(), 1.0), "the view's job ends"
	)


## The reference cone of the viewer as it stands now, in the world as it is now.
func _reference() -> Reference:
	var cone := Reference.new()
	cone.rebuild(
		Probe.space(_t), _eye.global_position, _eye.get("facing"), [_eye.get_rid()], _eye.sight()
	)
	return cone


## Whether the cone the view holds is the reference cone `want`.
func _published_is(want: Reference) -> bool:
	return Probe.polygons_differ(_view.cone(), _view.bubble(), want.cone, want.bubble) == ""


func _shape() -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	shape.shape = rect
	return shape
