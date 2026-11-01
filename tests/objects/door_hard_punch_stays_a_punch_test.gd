extends GameTest
## DR9, DR10: the strike names its kind, so a punch is a punch however hard it shoves. A punch whose
## shove is retuned to a kick's size (2200 here, the spec's kick shove) still marks a shut hollow
## door by the melee factor and never wears its latch: six of them leave it shut, where two real
## kicks burst it.

const DOORWAY := Vector2(400, 200)
## The hinge sits on the north jamb, 20 px from the middle, and the leaf swings east.
const HINGE := Vector2(400, 180)
## A punch's shove retuned to the size of a kick's (the spec's number: `docs/doors.md` DR10).
const HARD_PUNCH := 2200.0


func describe() -> Dictionary:
	return {
		"name": "A hard punch is still a punch to a door",
		"description": "With a punch's shove as hard as a kick's, six punches mark a shut hollow "
			+ "door and never burst it.",
		"tags": ["door", "objects", "punch"],
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
	s.set_static(CharacterMeleeConfig, &"punch_impulse", HARD_PUNCH)
	s.von_down()
	s.actor(&"puncher", &"puppet", Vector2(370, 200), { "start_slot": 2 })


func run(t: TestContext) -> void:
	var door = t.object(&"door")
	var puncher := t.puppet(&"puncher")
	puncher.aim_at(Vector2(470, 200))
	await t.seconds(0.6)
	var landed := func(d: Dictionary) -> bool: return d["body"] == door and d["hand"] >= 0
	for _i in 6:
		puncher.punch()
		await t.seconds(0.6)
	t.expect_eq(t.events_of(&"hit_landed", landed).size(), 6, "all six punches landed on the door")
	t.check(door.angle() == 0.0, "punches never burst a door (angle %.0f)" % door.angle())
	t.check(door.damage.hp < door.damage.max_hp, "though they mark it")
