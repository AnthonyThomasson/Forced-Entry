extends RefCounted
## Objects domain (private): a door's push, `door.push`: the turn a body walking into an ajar or
## open leaf gives it. The shove adds to the leaf's spin by its moment about the hinge against the
## leaf's weight; the hinge's friction takes the spin down again, so the leaf stops soon after the
## walker. It only works out the spin and the angle one step on; the door moves its body to it,
## after asking what stands in the way (`docs/doors.md` DR5, DR10).

## The leaf's spin now (degrees a second, positive opening).
var spin := 0.0
## The angle the leaf stood at when this push began.
var began_at := 0.0


## Add the spin a shove of `impulse` landing at world point `contact` gives a leaf of `weight`
## turning about `pivot`; `turn` is the door's turn sign (`door_swing.gd`). The spin is held to
## `DoorConfig.burst_speed`, no faster than a latch throws the door.
func shove(
	impulse: Vector2, contact: Vector2, pivot: Vector2, turn: float, weight: float
) -> void:
	var moment := (contact - pivot).cross(impulse)
	spin += turn * moment / (weight * DoorPushConfig.resistance)
	spin = clampf(spin, -DoorConfig.burst_speed, DoorConfig.burst_speed)


## Whether the leaf is turning.
func moving() -> bool:
	return not is_zero_approx(spin)


## The angle `delta` seconds on from `angle`, within shut and `limit`.
func after(angle: float, delta: float, limit: float) -> float:
	return clampf(angle + spin * delta, 0.0, limit)


## The hinge's friction takes `delta` seconds of the spin; the leaf rests once it is slow enough.
func slow(delta: float) -> void:
	spin *= exp(-DoorPushConfig.friction * delta)
	if absf(spin) < DoorPushConfig.rest_speed:
		spin = 0.0


## The leaf stops turning: it met something, reached shut or open, or a swing took over.
func stop() -> void:
	spin = 0.0
