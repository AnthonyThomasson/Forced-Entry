extends GameTest
## #194 stack-b, D20 / SI4: a car drives over what lies within a step and shoves what is taller. A
## row of plates on its path is driven over: they keep their places, the car loses no speed and no
## crash is posted (a flat item is on `TWIN_WALKOVER` and its mask leaves out `TWIN_VEHICLE`, so
## the car's body neither strikes nor flicks it). A stack of three boxes farther on is struck and
## shoved on ahead, the boxes thrown apart as free bodies (nothing joins them), the car going on
## through.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
const PLATES_X := [700.0, 730.0, 760.0]
const STACK_AT := Vector2(1300, 300)


func describe() -> Dictionary:
	return {
		"name": "A car drives over plates and shoves a box stack",
		"description": "The car drives over a row of plates, moving or striking none and losing no "
			+ "speed, then into a stack of three boxes, which it shoves on and scatters.",
		"tags": ["vehicle", "car", "collision", "stacking", "push"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3600, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(250, 300))
	for i in PLATES_X.size():
		s.object(StringName("plate_%d" % i), "plate", Vector2(PLATES_X[i], 300))
	s.object(&"box_0", "box", STACK_AT)
	s.object(&"box_1", "box", Vector2.ZERO, { "on": &"box_0" })
	s.object(&"box_2", "box", Vector2.ZERO, { "on": &"box_1" })
	s.actor(&"me", &"puppet", Vector2(120, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	if not t.require(
		await VehicleRide.board_by(t, &"me", car, &"front_left"), "the driver gets in"
	):
		return
	await t.frames(20)
	var boxes: Array[Vector2] = []
	for i in 3:
		boxes.append(t.object(StringName("box_%d" % i)).global_position)
	var front := VehicleFrame.forward(car)
	var plates := _plates(t)
	t.puppet(&"me").drive(1.0, 0.0, false)
	var speeds := await _drive_through(t, car)
	t.puppet(&"me").drive(0.0, 0.0, false)
	if not t.require(speeds[1] > 0.0, "the car passes the plates"):
		return
	t.check(
		speeds[1] > 0.9 * speeds[0],
		"the plates cost the car no speed (%.0f before, %.0f after)" % [speeds[0], speeds[1]],
	)
	for i in plates.size():
		var moved: float = _plates(t)[i].distance_to(plates[i])
		t.check(moved < 1.0, "plate %d lies where it was (%.1f px)" % [i, moved])
	t.check(_crashes_before(t, STACK_AT.x - 150.0) == 0, "no plate is struck: no crash is posted")
	_check_stack(t, car, boxes, front, speeds[0])


## Where the plates lie.
func _plates(t: TestContext) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in PLATES_X.size():
		out.append(t.object(StringName("plate_%d" % i)).global_position)
	return out


## Drive on until the car is well past the stack: its speed `[before the plates, after them]`.
func _drive_through(t: TestContext, car: Node2D) -> Array[float]:
	var speed_before := 0.0
	var speed_after := 0.0
	var deadline := t.time + 12.0
	while t.time < deadline:
		await t.frames(1)
		var x := car.global_position.x
		if x < PLATES_X[0] - 80.0:
			speed_before = car.speed()
		if x > PLATES_X[2] + 60.0 and speed_after == 0.0:
			speed_after = car.speed()
		if x > STACK_AT.x + 200.0:
			break
	return [speed_before, speed_after]


## The crashes the car posted at a place before plan x `limit`.
func _crashes_before(t: TestContext, limit: float) -> int:
	var crashes := t.events_of(&"vehicle", func(d): return d.get("stage") == &"crash")
	return crashes.filter(func(d: Dictionary) -> bool: return d["position"].x < limit).size()


## The stack's boxes were shoved on along the car's path, the stack scattered, the car went on.
func _check_stack(
	t: TestContext,
	car: Node2D,
	before: Array[Vector2],
	front: Vector2,
	cruising: float,
) -> void:
	var shoved := 0.0
	var scattered := false
	for i in 3:
		var at: Vector2 = t.object(StringName("box_%d" % i)).global_position
		shoved = maxf(shoved, (at - before[i]).dot(front))
		scattered = scattered or at.distance_to(STACK_AT) > 30.0
	t.check(shoved > 30.0, "a box is shoved on along the car's path (%.0f px)" % shoved)
	t.check(scattered, "the stack is scattered")
	t.check(
		car.speed() > 0.3 * cruising,
		"the car goes on through the stack (%.0f px/s)" % car.speed(),
	)
