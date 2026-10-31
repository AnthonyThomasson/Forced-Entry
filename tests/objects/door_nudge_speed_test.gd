extends GameTest
## DR8: a character in a door's arc is nudged aside no faster than `DoorConfig.nudge_speed`: a leaf
## that sweeps faster than that (here the nudge is slowed to 80 px/s, under the swing's 240 px/s
## peak) stops against the character instead of running it over, and stays where it stopped.

const JAMB := 20.0
const SLOW := 80.0


func describe() -> Dictionary:
	return {
		"name": "A leaf faster than the nudge stops against a character",
		"description": "With the nudge slowed to 80 px/s a door opened toward a puppet in its arc "
			+ "stops short of fully open and stays there.",
		"tags": ["door", "objects", "nudge"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 300) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 300) },
	], [{
		"pos": Vector2(400, 100), "width": 52.0,
		"door": {
			"name": "door", "material": "hollow", "style": "flush",
			"hinge": Vector2(400, 100 - JAMB), "swing_into": Vector2.RIGHT,
		},
	}])
	s.set_static(DoorConfig, "nudge_speed", SLOW)
	s.von_down()
	s.actor(&"puppet", &"puppet", Vector2(420, 108))


func run(t: TestContext) -> void:
	await t.seconds(0.3)
	var door = t.object(&"door")
	door.toggle(null)
	await t.seconds(1.0)
	var stopped: float = door.angle()
	t.check(
		stopped > 0.0 and stopped < 80.0,
		"the leaf stops against the character short of fully open (%.0f)" % stopped,
	)
	await t.seconds(0.5)
	t.check(door.angle() == stopped, "and stays where it stopped (%.0f)" % door.angle())
