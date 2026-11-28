extends GameTest
## A vehicle still strikes a standing character (interface 19) now the character's 3D body is the
## truth (#194): the knock-back and the harm reach it, and the 3D body takes the place the
## 2D body was knocked to, then walks on from there.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
## The car's closing speed (px/s): between the speed harm starts at and the speed it kills.
const SPEED := 200.0
const GAP := 8.0


func describe() -> Dictionary:
	return {
		"name": "A vehicle's strike reaches the character's 3D body",
		"description": "A car rolls into a standing puppet: it is knocked back and hurt, its 3D "
			+ "body is where the 2D one was knocked to, and it walks on from there.",
		"tags": ["vehicle", "character", "collision", "3d", "twins", "leader"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(400, 250))
	s.actor(&"hit", &"puppet", Vector2(100, 250))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car"):
		return
	await t.frames(3)
	var car := t.vehicle(&"car") as Node2D
	var body: Node2D = t.actor(&"hit")
	var lead := TwinSpace.twin_for(body) as CharacterBody3D
	if not t.require(lead != null, "premise: the character has a 3D body"):
		return
	var front := VehicleFrame.forward(car)
	var start: Vector2 = VehicleFrame.edge(car, front) + front * (body.radius + GAP)
	await VehicleRide.place(t, &"hit", start)
	car.set("linear_velocity", front * SPEED)
	await t.seconds(1.2)
	t.check(
		(body.global_position - start).dot(front) > 3.0,
		"the car knocked the character back (%.1f px)" % (body.global_position - start).dot(front),
	)
	t.check(body.health < body.max_health, "and hurt it (health %.1f)" % body.health)
	t.check(
		PlanSpace.plan_of(lead.global_position).distance_to(body.global_position) < 0.1,
		"its 3D body is where it was knocked to",
	)
	var knocked: Vector2 = body.global_position
	car.set("linear_velocity", Vector2.ZERO)
	t.puppet(&"hit").walk(front)
	await t.seconds(0.4)
	t.check(
		(body.global_position - knocked).dot(front) > 10.0,
		"it walks on from there (%.1f px)" % (body.global_position - knocked).dot(front),
	)
