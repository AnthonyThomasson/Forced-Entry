extends GameTest
## DR14, interface 24: `character.use.doors.open_fully(door)`, how an NPC works a door in its way,
## never shuts one. Called on a door that is already swinging open, and again on one that stands
## wide open (a second walker reaching a door the first opened), it leaves the door open: a toggle
## would swing it shut.

const DOORWAY := Vector2(400, 200)
## The hinge sits on the north jamb, 20 px from the middle, and the leaf swings east.
const HINGE := Vector2(400, 180)
## The brief's fully open, in degrees, and the time (s) a swing takes with a little to spare.
const FULL := 90.0
const SWING := 0.4
const SLACK := 0.2


func describe() -> Dictionary:
	return {
		"name": "open_fully never shuts a door",
		"description": "A character telling a door to open fully while it is swinging open, and "
			+ "once it is wide open, leaves it open.",
		"tags": ["door", "character", "use"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 400) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 400) },
	], [{
		"pos": DOORWAY, "width": 52.0,
		"door": {
			"name": "door", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])
	s.von_down()
	s.actor(&"opener", &"puppet", Vector2(370, 215), { "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	var door: Node = t.object(&"door")
	var doors = t.actor(&"opener").use.doors
	t.puppet(&"opener").aim_at(DOORWAY)
	await t.seconds(0.3)
	if not t.require(doors.open_fully(door), "premise: the door is in the opener's reach"):
		return
	await t.seconds(SWING * 0.4)
	if not t.require(
		door.angle() > 5.0 and door.angle() < FULL - 5.0,
		"premise: it is swinging open",
	):
		return
	t.check(doors.open_fully(door), "a second call reaches the door mid-swing")
	await t.seconds(SWING + SLACK)
	t.expect_near(door.angle(), FULL, 0.1, "a door told twice while opening ends fully open")
	t.check(doors.open_fully(door), "and a call on the wide open door reaches it")
	await t.seconds(SWING + SLACK)
	t.expect_near(door.angle(), FULL, 0.1, "the wide open door is left wide open")
