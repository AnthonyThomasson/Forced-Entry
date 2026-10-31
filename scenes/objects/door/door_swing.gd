extends RefCounted
## Objects domain (private): a door's swing, `door.swing`: the leaf's angle (degrees from shut) and
## the turn it is making toward `target`, eased over its time (a hand on the door) or at a steady
## rate (a burst latch throws it). It only works out the angle; the door moves its body to it, after
## asking what stands in the way.

## The leaf's angle now.
var angle := 0.0
## +1 when a positive turn swings the leaf toward `swing_into`, else -1.
var turn := 1.0
## The angle the leaf is turning to (its own, when it is at rest).
var target := 0.0
## The angle the turn began at, the seconds into it and its length.
var _from := 0.0
var _elapsed := 0.0
var _duration := 1.0
## Whether the turn starts and ends gently (a hand) or runs at one rate (a burst).
var _eased := true


## Begin turning from `angle` to `to`, taking `duration` seconds.
func begin(to: float, duration: float, eased := true) -> void:
	_from = angle
	target = to
	_elapsed = 0.0
	_duration = maxf(duration, 0.001)
	_eased = eased


## Whether the leaf is still turning.
func moving() -> bool:
	return not is_equal_approx(angle, target)


## The angle `delta` seconds on, without turning there.
func after(delta: float) -> float:
	var progress := clampf((_elapsed + delta) / _duration, 0.0, 1.0)
	return lerpf(_from, target, smoothstep(0.0, 1.0, progress) if _eased else progress)


## Turn on by `delta` seconds.
func advance(delta: float) -> void:
	angle = after(delta)
	_elapsed += delta


## Stop where the leaf is: it rests at this angle.
func halt() -> void:
	target = angle
