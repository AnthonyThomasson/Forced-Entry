extends GameTest
## A vehicle's twin (`VehicleTwins`, interface 29): a kinematic body over the vehicle's outline,
## 36 px tall for a car (the mesh's belt). A level ray at 30 px strikes it and one at 40 px passes
## over it. Shoved along, the car's twin stays within two steps of travel behind it, and once the
## car stops the twin is under it.

const Probe := preload("res://tests/_general/twin_probe.gd")
const AT := Vector2(300, 250)
const VEHICLES := PhysicsLayers.TWIN_VEHICLE
## A car's belt (px).
const BELT := 36.0


func describe() -> Dictionary:
	return {
		"name": "A car's twin is 36 px tall and follows it as it rolls",
		"description": "A ray at 30 px strikes a parked car's twin, one at 40 px passes over; "
			+ "shoved east the car's twin keeps within two steps of it and rests under it.",
		"tags": ["twins", "3d", "heights", "vehicle"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 500))
	s.vehicle(&"car", &"car", AT)


func run(t: TestContext) -> void:
	await t.frames(3)
	var car := t.vehicle(&"car") as RigidBody2D
	if not t.require(car != null, "premise: the car is placed"):
		return
	var hit := Probe.down(t, AT, VEHICLES)
	t.check(hit.get("owner") == car, "a ray dropped on the car finds it")
	t.expect_near(Probe.top_at(t, AT, VEHICLES), BELT, 0.5, "its body is 36 px tall")
	var across := Vector2(0, 100)
	t.check(
		not Probe.level(t, AT - across, AT + across, 30.0, VEHICLES).is_empty(),
		"30 px strikes",
	)
	t.check(
		Probe.level(t, AT - across, AT + across, 40.0, VEHICLES).is_empty(),
		"40 px passes over",
	)
	await _roll(t, car)


## Shove the car east and compare its twin with it each frame, then at rest.
func _roll(t: TestContext, car: RigidBody2D) -> void:
	car.apply_central_impulse(Vector2(60_000.0, 0.0))
	var worst := 0.0
	var peak := 0.0
	for i in 90:
		await t.frames(1)
		var twin: Node3D = t.world.twin_space().twin_of(car)
		var plan := PlanSpace.plan_of(twin.global_position)
		worst = maxf(worst, plan.distance_to(car.global_position))
		peak = maxf(peak, car.linear_velocity.length())
	t.require(car.global_position.distance_to(AT) > 30.0, "premise: the car rolled")
	t.check(worst <= peak / 60.0 * 2.0 + 0.1, "the twin stayed within two steps (%.2f px)" % worst)
	car.linear_velocity = Vector2.ZERO
	car.angular_velocity = 0.0
	await t.frames(4)
	var rest := PlanSpace.plan_of(t.world.twin_space().twin_of(car).global_position)
	t.check(rest.distance_to(car.global_position) < 0.1, "at rest the twin is under the car")
