class_name TyreSolve extends RefCounted
## One physics step of a vehicle's tyres sideways (`VehicleDrive.step`, the bicycle model): the
## body's velocity in its own frame (`vx` forward, `vy` toward its right side, `w` the spin) and
## each axle's sideways impulse, which cancels that axle's slip up to its grip, both axles solved
## together by sequential impulses. The model fills the velocity, mass and inertia, then `solve`s.

## The velocity in the vehicle's frame: forward, toward its right side (px/s), and the spin
## (rad/s).
var vx := 0.0
var vy := 0.0
var w := 0.0
## The body's mass and moment of inertia.
var mass := 1.0
var inertia := 1.0
## The axles' levers along x from the centre of mass (px; the rear's negative).
var _front := 0.0
var _back := 0.0
## The cosine and sine of the front wheels' angle.
var _c := 1.0
var _s := 0.0
## Each axle's effective inverse mass along its sideways direction.
var _k_front := 1.0
var _k_rear := 1.0
## Each axle's grip limit this step and the impulse it has given so far.
var _grip_front := 0.0
var _grip_rear := 0.0
var _j_front := 0.0
var _j_rear := 0.0


## Solve the sideways impulses over `VehicleConfig.tyre_iterations` passes for a vehicle of `row`
## with its front wheels at `wheel_angle`, over a step of `dt` s; the handbrake (`handbrake`) leaves
## the rear its `handbrake_grip` share. Leaves the velocity solved.
func solve(row: Dictionary, wheel_angle: float, handbrake: bool, dt: float) -> void:
	_front = row["axle_front"]
	_back = -float(row["axle_rear"])
	_c = cos(wheel_angle)
	_s = sin(wheel_angle)
	_k_front = 1.0 / mass + (_front * _c) * (_front * _c) / inertia
	_k_rear = 1.0 / mass + _back * _back / inertia
	_grip_front = float(row["grip_front"]) * mass * 0.5 * dt
	_grip_rear = (float(row["grip_rear"])
			* (float(row["handbrake_grip"]) if handbrake else 1.0) * mass * 0.5 * dt)
	for _i in VehicleConfig.tyre_iterations:
		_front_pass()
		_rear_pass()


## The sliding speed the solve left (px/s): the larger of the two axles'.
func left() -> float:
	return maxf(absf(-vx * _s + (vy + w * _front) * _c), absf(vy - w * _back))


## The front axle's impulse along the turned wheel's normal, clamped at its grip.
func _front_pass() -> void:
	var slide_front := -vx * _s + (vy + w * _front) * _c
	var next := clampf(_j_front - slide_front / _k_front, -_grip_front, _grip_front)
	var d := next - _j_front
	_j_front = next
	vx += -_s * d / mass
	vy += _c * d / mass
	w += _front * _c * d / inertia


## The rear axle's sideways impulse, clamped at its grip.
func _rear_pass() -> void:
	var slide_rear := vy - w * _back
	var next := clampf(_j_rear - slide_rear / _k_rear, -_grip_rear, _grip_rear)
	var d := next - _j_rear
	_j_rear = next
	vy += d / mass
	w -= _back * d / inertia
