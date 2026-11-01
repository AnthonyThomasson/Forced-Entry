extends RefCounted
## Shared helper for `perf/match_npc_vision_relative` (`docs/player-vision.md`, Perf): what the
## view's cone costs a physics frame, and what the plain cone would cost from the same eye. Not a
## test.
##
## Two nodes in the view's world bracket the view's own physics step: one just before it
## (`process_physics_priority` under `PlayerView.PRIORITY`), one just after. Between them runs the
## view and nothing else, so the difference is the live cone's cost for the frame: the change
## check, and the rebuild when there was one. A frame the view skipped costs the check alone, which
## is the point: the saving is what it is on average, skips included.
##
## While the view is switched off (its node disabled) and `measure_reference` is set, the second
## node rebuilds the reference cone (`tests/_vision/reference_view_cone.gd`, the cone as it was
## before any saving, built whole every frame) from the same eye, facing and sight the view would
## have used, and times that. The reference runs only in blocks of its own, never while the view's
## cost against the unviewed match is measured, so it adds nothing to that.

const Reference := preload("res://tests/_vision/reference_view_cone.gd")

## Whether the second node times the reference cone on the frames the view is off.
var measure_reference := false
## The time (µs) and the frames the live cone, and the reference cone, were timed over.
var live_us := 0
var live_frames := 0
var reference_us := 0
var reference_frames := 0
var _view: PlayerView
var _reference := Reference.new()
var _started := 0


## Bracket the physics step of `view`, with two nodes added to the world it is in.
func attach(view: PlayerView) -> void:
	_view = view
	var before := _Tick.new(_begin, PlayerView.PRIORITY - 1)
	var after := _Tick.new(_end, PlayerView.PRIORITY + 1)
	before.name = "ConeStopwatchBefore"
	after.name = "ConeStopwatchAfter"
	view.get_parent().add_child(before)
	view.get_parent().add_child(after)


## Forget what was timed.
func reset() -> void:
	live_us = 0
	live_frames = 0
	reference_us = 0
	reference_frames = 0


## The live cone's average cost over the frames timed (µs); 0 with none.
func live_average() -> float:
	return float(live_us) / maxf(float(live_frames), 1.0)


## The reference cone's average cost over the frames timed (µs); 0 with none.
func reference_average() -> float:
	return float(reference_us) / maxf(float(reference_frames), 1.0)


func _begin() -> void:
	_started = Time.get_ticks_usec()


func _end() -> void:
	if not is_instance_valid(_view):
		return
	if _view.can_process():
		live_us += Time.get_ticks_usec() - _started
		live_frames += 1
	elif measure_reference:
		var viewer := _view.viewer()
		var began := Time.get_ticks_usec()
		_reference.rebuild(
			_view.get_world_2d().direct_space_state,
			viewer.global_position,
			viewer.get("facing"),
			[viewer.get_rid()],
			viewer.sight(),
		)
		reference_us += Time.get_ticks_usec() - began
		reference_frames += 1


## A node that calls `tick` each physics frame at `priority`.
class _Tick:
	extends Node

	var _tick: Callable

	func _init(tick: Callable, priority: int) -> void:
		_tick = tick
		process_physics_priority = priority

	func _physics_process(_delta: float) -> void:
		# The stopwatch is gone once its test has ended; the world is not, for a frame or two.
		if _tick.is_valid():
			_tick.call()
