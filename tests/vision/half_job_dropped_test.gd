extends GameTest
## V9 and V1 (`docs/player-vision.md`): a cone job half done is dropped with the view. The slice is
## small (a job of this house takes three frames), and
## - the viewer dies with a job in flight: the view's nodes are gone within a frame, the seen area
##   is cleared at once and stays cleared; the viewer dies in a physics frame ahead of the view's,
##   as a hit does, with the next slice enough to finish the job, which must not publish after the
##   lift (a queued view's tick is not run in that frame: engine behaviour this test holds);
## - the view is disabled with a job in flight (as the perf guards switch it off): the job is gone
##   at once (`building()` false), the seen area is cleared, nothing is stepped or published while
##   it is off, and when it is enabled again the first cone is built whole in that frame, of the
##   viewer's pose, and the area is written again.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(200, 300)
## The slice (units) that makes a job of this house three frames.
const SLICE := 90
## A place this far west of the viewer is far outside its cone and bubble.
const FAR := 3000.0
const OFF_FRAMES := 8
const AFTERWARDS := 30

var _t: TestContext
var _view: PlayerView
var _eye: Node2D
var _turned := false


func describe() -> Dictionary:
	return {
		"name": "A cone job half done is dropped with the view",
		"description": "The viewer killed, and the view disabled and enabled again, with a job in "
			+ "flight: the job is gone, the seen area cleared and not written again by it, and an "
			+ "enabled view builds its first cone whole.",
		"tags": ["vision"],
		"timeout": 30.0,
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
	await _disabled_with_a_job()
	await _lifted_with_a_job()


## A turn starts a job; wait until it is in flight (three slices, so it is for two frames more).
func _job_in_flight() -> bool:
	_turned = not _turned
	var angle := 0.08 if _turned else 0.0
	_t.puppet(&"eye").aim_at(_eye.global_position + Vector2.from_angle(angle) * 100.0)
	return _t.require(
		await _t.until(func() -> bool: return _view.building(), 0.5), "a turn starts a job"
	)


func _disabled_with_a_job() -> void:
	var far := _eye.global_position + Vector2(-FAR, 0)
	_t.check(not _reached(far), "premise: with the view standing a far place is hidden")
	if not await _job_in_flight():
		return
	_view.process_mode = Node.PROCESS_MODE_DISABLED
	_t.check(not _view.building(), "the job in flight is dropped when the view is disabled")
	_t.check(_reached(far), "nothing is hidden while it is disabled: a far place reaches the area")
	var starts := _view.starts()
	var published := _view.rebuilds()
	await _t.frames(OFF_FRAMES)
	_t.check(
		_view.starts() == starts and _view.rebuilds() == published,
		"a disabled view starts and publishes nothing",
	)
	_view.process_mode = Node.PROCESS_MODE_INHERIT
	await _t.frames(1)
	_t.check(
		_view.rebuilds() == published + 1 and not _view.building(),
		"enabled again, the view builds a cone whole in the first frame",
	)
	var pose := _view.published_pose()
	_t.check(
		pose["eye"] == _eye.global_position and pose["facing"] == _eye.get("facing"),
		"that cone is of the viewer's pose as it is",
	)
	_t.check(not _reached(far), "and the area it shows is written again")


func _lifted_with_a_job() -> void:
	var far := _eye.global_position + Vector2(-FAR, 0)
	if not await _job_in_flight():
		return
	# The next slice would finish the job; the viewer dies in the frame it is stepped in, before
	# the view's tick.
	VisionSliceConfig.slice_units = 1 << 30
	var hand := _Killer.new(_eye)
	_t.world.add_child(hand)
	await _t.frames(1)
	hand.queue_free()
	_t.check(_eye.is_dead, "premise: the viewer is dead")
	_t.check(Probe.views_under(_t.world).is_empty(), "the view is gone within a frame")
	_t.check(_reached(far), "the area is cleared: a far place reaches it")
	await _t.frames(AFTERWARDS)
	_t.check(
		Probe.views_under(_t.world).is_empty() and _reached(far),
		"no job finishes after the lift to write the area again",
	)


## Whether a disc or a box at `at` reaches the area the view shows live.
func _reached(at: Vector2) -> bool:
	return Probe.reached_by(at).has(true)


## Kills `who` from its own physics frame, ahead of the view's (priority 100), once.
class _Killer:
	extends Node

	var _who: Node2D

	func _init(who: Node2D) -> void:
		_who = who
		process_physics_priority = 50

	func _physics_process(_delta: float) -> void:
		if is_instance_valid(_who) and not _who.is_dead:
			_who.take_damage(1000.0)
