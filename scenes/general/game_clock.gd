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
## a timer ends
## on its frame whenever it started.
const SECONDS_BIAS := 1e-9

## Physics frames run while the tree was unpaused, since the game started.
var _frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _physics_process(_delta: float) -> void:
	_frames += 1


## Game milliseconds since the game started: the drop-in for `Time.get_ticks_msec()` on the pausable
## clock.
func msec() -> int:
	return int(_frames * 1000.0 / Engine.physics_ticks_per_second)


## Game seconds since the game started (`SECONDS_BIAS` above exact: a timer ends on its frame).
func seconds() -> float:
	return float(_frames) / float(Engine.physics_ticks_per_second) * (1.0 + SECONDS_BIAS)


## Physics frames run while unpaused since the game started.
func frame() -> int:
	return _frames
