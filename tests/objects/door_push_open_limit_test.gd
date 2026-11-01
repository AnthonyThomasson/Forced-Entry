extends GameTest
## DR10: a pushed leaf stops at fully open (90°) however hard it is shoved. An ajar hollow door,
## hinged on its upper jamb and swinging east, is shoved from the west every frame with a shove
## hard enough (resistance cut to a fiftieth, no hinge friction) to throw it at its fastest.

const JAMB := 20.0
const DOORWAY := Vector2(400, 200)
const SHOVE := Vector2(900, 0)
## The most a leaf opens, whatever pushes it (`docs/doors.md` DR1).
const OPEN := 90.0


func describe() -> Dictionary:
	return {
		"name": "A hard-pushed leaf stops at fully open",
		"description": "An ajar door shoved as hard as the rules let it spin opens to 90° and no "
			+ "further.",
		"tags": ["door", "objects", "push"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 400) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 400) },
	], [{
		"pos": DOORWAY, "width": 52.0,
		"door": {
			"name": "limit", "material": "hollow", "style": "flush",
			"hinge": DOORWAY - Vector2(0, JAMB), "swing_into": Vector2.RIGHT, "angle": 25.0,
		},
	}])
	s.von_down()
	s.set_static(DoorPushConfig, &"resistance", 1.2)
	s.set_static(DoorPushConfig, &"friction", 0.0)


func run(t: TestContext) -> void:
	await t.seconds(0.4)
	var door = t.object(&"limit")
	var highest := { "angle": 0.0 }
	var shove := func() -> bool:
		door.apply_impulse(SHOVE)
		highest["angle"] = maxf(highest["angle"], door.angle())
		return false
	await t.until(shove, 1.5)
	t.check(
		highest["angle"] > 60.0,
		"premise: the hard shove turns the leaf a long way (%.0f°)" % highest["angle"],
	)
	t.check(
		highest["angle"] <= OPEN and door.angle() <= OPEN,
		"and never past fully open (%.2f°, at most %.2f°)" % [door.angle(), highest["angle"]],
	)
	t.check(door.angle() >= OPEN - 1.0, "it ends open (%.1f°)" % door.angle())
