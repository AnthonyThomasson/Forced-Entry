extends GameTest
## A vehicle is a plan handle (#194 del2d-c3, D4, interface 19): a plain `Node2D` in the groups
## `vehicles`, `TwinSpace.BODIES` and `TwinSpace.HARD`, no 2D physics body, shape or layer. Its 3D
## `VehicleBody` leads it and is the outline lifted to the belt, the handle follows, and a character
## that boards it shares space with it (the contacts leave it out) until it has cleared it.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const PlanProbe := preload("res://tests/_general/plan_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A vehicle is a plain Node2D plan handle",
		"description": "A car is no CollisionObject2D and holds no 2D shape; it is in the groups "
			+ "of plan bodies and hard bodies, a scan of plan bodies finds it, its twin stands "
			+ "where it does, and a body it shares space with is left out of its contacts.",
		"tags": ["vehicle", "car", "twins", "del2d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 500), { "floor": "concrete" })
	s.vehicle(&"car", &"car", Vector2(300, 250))
	s.actor(&"rider", &"puppet", Vector2(100, 100))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"rider"]):
		return
	await t.frames(3)
	var car: Node2D = t.vehicle(&"car")
	t.check(not car is CollisionObject2D, "the car is no 2D collision object")
	t.check(
		car.find_children("*", "CollisionShape2D", true, false).is_empty(),
		"the car holds no 2D shape",
	)
	for group: StringName in [&"vehicles", TwinSpace.BODIES, TwinSpace.HARD]:
		t.check(car.is_in_group(group), "the car is in the group %s" % group)
	t.check(PlanProbe.bodies_under(t.world).has(car), "a scan of plan bodies finds the car")
	var twin := TwinSpace.leader_of(car)
	t.require(twin != null, "premise: the car has its 3D body")
	t.check(
		PlanSpace.plan_of(twin.global_position).is_equal_approx(car.global_position),
		"the handle stands where its 3D body does",
	)
	var rider := t.actor(&"rider")
	car.contacts.share_space(rider, true)
	t.check(car.contacts.shares_space_with(rider), "a body it shares space with is left out")
	car.contacts.share_space(rider, false)
	t.check(not car.contacts.shares_space_with(rider), "and counted again once it has cleared it")
