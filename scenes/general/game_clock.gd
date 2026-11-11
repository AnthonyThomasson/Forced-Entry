extends Node
## General domain: autoloaded as `GameClock`, the pausable game clock (interface 11). It counts
## physics frames in `_physics_process` and is `PROCESS_MODE_PAUSABLE`, so it stands still while the
## tree is paused: a pause of any length ages nothing measured on it. Its time is frames over
## `Engine.physics_ticks_per_second`, so a headless `--fixed-fps` run reads the same times on every
## run, however fast it outpaces the wall clock. Every AI ttl, timer and age reads it
## (`docs/leadership.md` LD1); what measures real time (the Von server's boot timeout, Von's reply
## latency) stays on `Time`.
##
## An autoload node rather than a `class_name` holder (an autoload and a class cannot share a name):
## callers read `GameClock.msec()`, `GameClock.seconds()` and `GameClock.frame()` off the singleton.

## `seconds()` reads this much (relative) above the frames' exact time. A timer "has run N frames"
## is the test `seconds() - start >= ttl` with `ttl` an exact number of frames of time (0.8 s is
## 48), and the two readings are floats rounded where they fall: whether their difference then
## reaches `ttl` follows the frame the timer started on (0.8 s read short at 45 of 100 start
## frames), so a match played after another in one process swung the timer a frame. Every reading
## sits this much above exact, many times the rounding of an hour of play and far below a frame, so
## a timer ends on its frame whenever it started. So a timer reads `seconds()` at both ends: not
## `seconds()` against `msec() / 1000.0` or `frame() / 60.0`, which are exact (or whole ms) and
## differ from it by that bias and by rounding.
const SECONDS_BIAS := 1e-9

## Physics frames run while the tree was unpaused, since the game started.
var _frames := 0
## What `msec()` counts from (`align`): the frame it was last aligned on (modulo the grid's period)
## and the game ms it read there.
var _msec_phase := 0
var _msec_base := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _physics_process(_delta: float) -> void:
	_frames += 1


## Game milliseconds since the game started: the drop-in for `Time.get_ticks_msec()` on the pausable
## clock. A frame is 16 2/3 ms at 60 a second, so a span of frames reads 16 or 17 ms a frame
## depending on which frame of the grid (three of them) it starts on; `align` puts every world on
## the same grid.
func msec() -> int:
	@warning_ignore("integer_division")
	return _msec_base + ((_frames - _msec_phase) * 1000) / Engine.physics_ticks_per_second


## Put the ms grid's start on the frame the clock is on, without a jump in `msec()`: the spans of
## frames that follow then read the same ms from this frame on, whichever frame of the process this
## is. A world calls it when it begins (`WorldRng`), so a match's measured spans (a walker's speed
## over its last sighting, an age) do not follow what the process ran before it.
func align() -> void:
	var ticks := Engine.physics_ticks_per_second
	var now := msec()
	@warning_ignore("integer_division")
	_msec_phase = _frames % (ticks / _gcd(ticks, 1000))
	@warning_ignore("integer_division")
	_msec_base = now - ((_frames - _msec_phase) * 1000) / ticks


## The greatest common divisor of `a` and `b`.
func _gcd(a: int, b: int) -> int:
	return a if b == 0 else _gcd(b, a % b)


## Game seconds since the game started (`SECONDS_BIAS` above exact: a timer ends on its frame).
func seconds() -> float:
	return float(_frames) / float(Engine.physics_ticks_per_second) * (1.0 + SECONDS_BIAS)


## Physics frames run while unpaused since the game started.
func frame() -> int:
	return _frames
