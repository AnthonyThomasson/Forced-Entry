extends GameTest
## Whether a car's door can open is asked of the twin space (#194, interface 29): an
## armchair in the rear-left door's swing blocks it by its 3D body, and so does another car in the
## swing; a person standing at the door's stand point blocks it
## (a character's 3D body is a solid like any other); the rider at its own stand point does not.
## Any piece in the arc blocks, as in 2D: its height is not read.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const CAR_AT := Vector2(450, 300)
## Off the car's rear-left corner: its near corner reaches into the rear-left door's swing.
const CHAIR_AT := CAR_AT + Vector2(-90, -90)
## Where the other car stands: its body reaches into the same swing, and not into the first car.
const OTHER_CAR_AT := CAR_AT + Vector2(-150, -150)


func describe() -> Dictionary:
	return {
		"name": "A door's swing is blocked by a 3D body, not the 2D footprint",
		"description": "An armchair, another car (2D shapes off) or a person at the stand "
			+ "point holds the rear-left door shut; the rider at its own stand point does not.",
		"tags": ["vehicle", "car", "board", "door", "3d"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", CAR_AT)
	s.vehicle(&"other_car", &"car", Vector2(780, 540))
	s.object(&"chair", "armchair", CHAIR_AT)
	s.actor(&"me", &"puppet", Vector2(150, 500))
	s.actor(&"other", &"puppet", Vector2(100, 100))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	await t.frames(3)
	me.global_position = Vector2(300, 520)
	await t.frames(3)
	t.check(
		not car.can_board(me, &"rear_left"),
		"the armchair, by its 3D body, holds the rear-left door shut",
	)
	t.check(car.can_board(me, &"front_left"), "the front-left door is clear")
	t.object(&"chair").free()
	await t.frames(3)
	t.check(car.can_board(me, &"rear_left"), "with the armchair gone the rear-left door is clear")
	var door = car.cabin.door(&"rear_left")
	var stand: Vector2 = car.to_global(door.stand_point(me.radius))
	var other := t.actor(&"other")
	other.global_position = stand
	await t.frames(3)
	t.check(not car.can_board(me, &"rear_left"), "a person at the stand point holds the door shut")
	other.global_position = Vector2(100, 100)
	me.global_position = stand
	await t.frames(3)
	t.check(car.can_board(me, &"rear_left"), "the rider at its own stand point does not block it")
	var other_car := t.vehicle(&"other_car") as Node2D
	if other_car == null:
		return
	other_car.global_position = OTHER_CAR_AT
	await t.frames(3)
	t.check(not car.can_board(me, &"rear_left"), "another car in the swing holds the door shut")
	t.check(car.can_board(me, &"front_left"), "the front-left door, clear of it, opens")
