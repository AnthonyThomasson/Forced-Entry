extends GameTest
## DR10: a pushed leaf stops where it meets furniture. Two ajar hollow doors swing east, hinged on
## their upper jamb; each is shoved from the west every frame for a second and a half with a
## walker's shove (interface 5), and a fridge stands in the arc of one.

const JAMB := 20.0
const ROWS := { &"free": 100.0, &"fridged": 250.0 }
## A walker's shove along its heading, a frame's worth (`docs/doors.md` DR10: about 900).
const SHOVE := Vector2(900, 0)
## How long the shove goes on.
const PUSHING := 1.5
## The fridge: 60 by 70 px, its west face 36 px east of the hinge, level with the doorway's middle,
## in the arc of the leaf at about 45 to 90 degrees.
const FRIDGE := Vector2(466, 256)


func describe() -> Dictionary:
	return {
		"name": "A pushed leaf stops at furniture",
		"description": "A shove on an ajar door opens it wide; with a fridge in its arc the leaf "
			+ "stops short of it and the fridge stays where it stood.",
		"tags": ["door", "objects", "push"],
		"timeout": 12.0,
	}


func _doorway(id: StringName) -> Dictionary:
	var y: float = ROWS[id]
	return {
		"pos": Vector2(400, y), "width": 52.0,
		"door": {
			"name": String(id), "material": "hollow", "style": "flush",
			"hinge": Vector2(400, y - JAMB), "swing_into": Vector2.RIGHT, "angle": 25.0,
		},
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 400) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 400) },
	], [_doorway(&"free"), _doorway(&"fridged")])
	s.von_down()
	s.object(&"fridge", "fridge", FRIDGE)


func run(t: TestContext) -> void:
	await t.seconds(0.4)
	var fridge_at: Vector2 = t.object(&"fridge").global_position
	var shove := func() -> bool:
		for id: StringName in ROWS:
			t.object(id).apply_impulse(SHOVE)
		return false
	await t.until(shove, PUSHING)
	await t.seconds(0.5)
	var free: float = t.object(&"free").angle()
	var fridged: float = t.object(&"fridged").angle()
	t.check(
		free >= 80.0,
		"premise: with nothing in its arc the shoved leaf opens wide (%.0f°)" % free,
	)
	t.check(
		fridged > 25.0 and fridged < 65.0,
		"a fridge in its arc stops the leaf short of it (%.0f°)" % fridged,
	)
	t.check(
		t.object(&"fridge").global_position.distance_to(fridge_at) < 1.0,
		"and the leaf does not move the fridge (%.1f px)" % (
			t.object(&"fridge").global_position.distance_to(fridge_at)),
	)
