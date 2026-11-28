extends GameTest
## V5 (#194, D13): a vehicle is a free 3D body (`RigidBody3D`) locked upright: it leads
## (`TwinSpace.leader_of`), its 2D body only the footprint written from it. It cannot roll or
## pitch: struck as hard as a round can at its roof, and shoved high at its flank, it turns about
## up and slides but stays level, on the floor.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const AT := Vector2(600, 400)
## A shove far past what a person or a round gives (impulse, px/s x mass) at the roof's height.
const BLOW := 400_000.0
const ROOF := 55.0
const LEVEL := 0.9999


func describe() -> Dictionary:
	return {
		"name": "A vehicle is a 3D body that cannot roll over",
		"description": "The car's 3D body leads and its 2D body follows. A huge shove at its roof "
			+ "height at one side turns it about up and slides it, but it never leans.",
		"tags": ["vehicle", "car", "3d", "physics", "locked"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1600, 800), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", AT)


func run(t: TestContext) -> void:
	await t.frames(4)
	var car := t.vehicle(&"car") as Node2D
	if not t.require(car != null, "premise: the car is placed"):
		return
	var lead := TwinSpace.leader_of(car)
	if not t.require(lead != null, "the car's truth is a free 3D body (a RigidBody3D that leads)"):
		return
	t.check(
		lead.axis_lock_angular_x and lead.axis_lock_angular_z,
		"locked about the horizontal axes: it cannot roll or pitch",
	)
	var start := car.global_position
	Knockback.push(car, Vector2(0.0, BLOW), Vector2(60.0, -55.0), ROOF)
	var worst := 1.0
	var highest := 0.0
	for _i in 120:
		await t.frames(1)
		worst = minf(worst, lead.global_transform.basis.y.normalized().y)
		highest = maxf(highest, lead.global_position.y)
	t.check(
		car.global_position.distance_to(start) > 20.0,
		"premise: the blow moved it (%.0f px)" % car.global_position.distance_to(start),
	)
	t.check(worst > LEVEL, "it never leaned (up axis %.5f at its most tilted)" % worst)
	t.check(highest < 2.0, "and never left the floor (%.2f px at its highest)" % highest)
	t.check(
		car.global_position.distance_to(PlanSpace.plan_of(lead.global_position)) < 0.5,
		"its 2D body is the footprint, under the 3D body",
	)
