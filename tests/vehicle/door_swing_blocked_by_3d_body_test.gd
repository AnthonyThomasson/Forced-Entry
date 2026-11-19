extends GameTest
## Whether a car's door can open is asked of the twin space (#194 chars3d-b, interface 29): an
## armchair standing in the rear-left door's swing blocks it by its 3D body, with its 2D footprint's
## shapes off, a low piece the door's swing clears does not, and a person standing at the stand
## point beside the door does, a character's 3D body being a solid like any other.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const CAR_AT := Vector2(450, 300)
## Off the car's rear-left corner: its near corner reaches into the rear-left door's swing.
const CHAIR_AT := CAR_AT + Vector2(-90, -90)


func describe() -> Dictionary:
	return {
		"name": "A door's swing is blocked by a 3D body, not the 2D footprint",
		"description": "An armchair in the rear-left door's swing, its 2D shapes off, still holds "
			+ "the door shut; the front-left door is clear.",
		"tags": ["vehicle", "car", "board", "door", "3d"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", CAR_AT)
	s.object(&"chair", "armchair", CHAIR_AT)
	s.actor(&"me", &"puppet", Vector2(150, 500))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	var chair := t.object(&"chair")
	await t.frames(3)
	for shape in chair.find_children("*", "CollisionShape2D", true, false):
		(shape as CollisionShape2D).disabled = true
	me.global_position = Vector2(300, 520)
	await t.frames(3)
	t.check(
		not car.can_board(me, &"rear_left"),
		"the armchair, by its 3D body, holds the rear-left door shut",
	)
	t.check(car.can_board(me, &"front_left"), "the front-left door is clear")
	chair.free()
	await t.frames(3)
	t.check(car.can_board(me, &"rear_left"), "with the armchair gone the rear-left door is clear")
