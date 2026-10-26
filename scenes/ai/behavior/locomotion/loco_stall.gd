extends RefCounted
## AI BEHAVIOUR sub-domain — LOCOMOTION's stall sensing, its part `stall`: observation only. It
## samples the character's progress each tick (`sample`) and exposes it to the stuck overlay
## (`debug_progress`); nothing reacts to it. Built once with its Locomotion, it holds it (a node, so
## no reference cycle) for the body.

## Stuck-sensing window (s): displacement is compared over this span while the NPC is trying to
## move.
const WINDOW := 0.75
## Speed (px/s) below which an NPC that is trying to move counts as not progressing.
const SPEED := 8.0
## Seconds between recorded trail points, and the most points kept (a short recent-position trail).
const TRAIL_STEP := 0.25
const TRAIL_MAX := 24

## The Locomotion it belongs to.
var loco: Node
## Position at the start of the current stall-sensing window.
var _pos := Vector2.ZERO
## Seconds into the current window.
var _clock := 0.0
## Speed (px/s) measured over the last full window.
var _speed := 0.0
## Seconds the NPC has been trying to move without progressing.
var _stalled_for := 0.0
## Seconds since the last trail point.
var _trail_clock := 0.0
## Recent world positions, oldest first.
var _trail: Array = []


func _init(locomotion: Node) -> void:
	loco = locomotion


## Observation only: sample the character's progress each tick. While it is trying to move
## (`movement.move_input` set) it compares displacement over `WINDOW`; a speed under `SPEED` grows
## `_stalled_for`. Nothing reacts to it — `debug_progress()` exposes it to the stuck overlay.
func sample(delta: float) -> void:
	var character: Node = loco._character
	var here: Vector2 = character.global_position
	_trail_clock += delta
	if _trail_clock >= TRAIL_STEP:
		_trail_clock = 0.0
		_trail.append(here)
		if _trail.size() > TRAIL_MAX:
			_trail.pop_front()
	if (character.movement.move_input as Vector2).length() < 0.1:
		_clock = 0.0
		_pos = here
		_stalled_for = 0.0
		_speed = 0.0
		return
	_clock += delta
	if _clock >= WINDOW:
		_speed = here.distance_to(_pos) / _clock
		_stalled_for = _stalled_for + _clock if _speed < SPEED else 0.0
		_pos = here
		_clock = 0.0


## Read-only: the movement-progress state sampled by `sample()`, for the stuck debug overlay.
func debug_progress() -> Dictionary:
	return { "stalled_for": _stalled_for, "trail": _trail }
