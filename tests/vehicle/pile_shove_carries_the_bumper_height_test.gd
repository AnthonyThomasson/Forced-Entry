extends GameTest
## A vehicle's shove of the bodies it pushes before it (its pile: a person, a piece pressed against
## one) is given at the real height the bumper meets them (#194 chars3d-b): each member's blow
## carries the height the bumper strikes at, never a push at no height (the body's centre), and
## still at the member's centre on the plan, so a piece leans by where it is struck and slides where
## it is struck low.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const CAR_AT := Vector2(300, 300)


func describe() -> Dictionary:
	return {
		"name": "A vehicle's shove of its pile is given at the bumper's height",
		"description": "The blows queued for a person and a piece in a car's pile each carry the "
			+ "bumper's height and a central contact point.",
		"tags": ["vehicle", "car", "character", "3d", "knockback"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", CAR_AT)
	s.actor(&"person", &"puppet", CAR_AT + Vector2(150.0, 0.0))
	s.object(&"crate", "armchair", CAR_AT + Vector2(150.0, 100.0))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"person"]):
		return
	await t.frames(4)
	var car := t.vehicle(&"car") as Node2D
	var contacts: VehicleContacts = car.contacts
	var members: Array = []
	for body: Node in [t.actor(&"person"), t.object(&"crate")]:
		members.append({
			"body": body,
			"mass": float(body.get_mass()),
			"character": body is CharacterBody2D,
			"through": 0.0,
		})
	var hit := {
		"normal": Vector2.RIGHT,
		"position": CAR_AT + Vector2(110.0, 0.0),
		"new": false,
	}
	contacts._shove_pile(TwinSpace.leader_of(car), hit, members, 200.0, 0.0)
	var want := VehicleCollisionConfig.strike_height(car.kind)
	t.require(contacts._struck.size() == 2, "both members are queued a blow")
	for blow: Dictionary in contacts._struck:
		var name := String((blow["body"] as Node).name)
		t.expect_near(
			float(blow.get("height", -1.0)), want, 0.01,
			"%s is struck at the bumper's height" % name,
		)
		t.check(blow.get("at", Vector2.INF) == Vector2.ZERO, "%s at its centre on the plan" % name)
