extends GameTest
## G12 (#194 D10): a wall behind nine wardrobes muffles the bang (x`wall_factor`) and stops the
## flash: the count of pieces on the line changes neither (see `stun_line_through_many_pieces`).

const BURST := Vector2(400, 100)
const VICTIM := Vector2(400, 780)
const FIRST_Y := 190.0
const STEP := 55.0
const PIECES := 9
const RADIUS := 1000.0
## The wall between the rooms, behind the last wardrobe (its face is at y 652).
const WALL_Y := 700.0


func describe() -> Dictionary:
	return {
		"name": "A wall behind nine wardrobes still muffles the bang and stops the flash",
		"description": "Nine wardrobes and then a wall stand between a stun grenade and a "
			+ "character: the bang is x0.4 and the flash does not reach it.",
		"tags": ["grenade", "stun", "cover", "3d"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "north", "type": "living_room", "rect": Rect2(0, 0, 800, WALL_Y) },
		{ "key": "south", "type": "kitchen", "rect": Rect2(0, WALL_Y, 800, 200) },
	])
	s.switch(&"nav.rebake", false)
	for i in PIECES:
		s.object(StringName("wardrobe%d" % i), "wardrobe", Vector2(BURST.x, FIRST_Y + STEP * i))
	s.actor(&"thrower", &"puppet", Vector2(60, 60), { "max_health": 100_000.0 })
	s.actor(&"victim", &"puppet", VICTIM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	await t.frames(3)
	var row: Dictionary = GrenadeConfig.row(&"stun").duplicate()
	row["flash_radius"] = RADIUS
	row["bang_radius"] = RADIUS
	var victim := t.actor(&"victim")
	Explosion.stun(BURST, t.world, t.actor(&"thrower"), row)
	await t.frames(2)
	var events := t.events_of(&"stun", func(d): return d.get("character") == victim)
	if not t.require(not events.is_empty(), "the victim is stunned"):
		return
	var full := float(row["max_deaf"]) * (1.0 - BURST.distance_to(VICTIM) / RADIUS)
	var want := full * float(row["wall_factor"])
	t.check(
		absf(float(events[0].get("deaf", -1.0)) - want) < 0.01,
		"the bang is x%s through the wall: %.2f s, expected %.2f (full %.2f)"
			% [row["wall_factor"], float(events[0].get("deaf", -1.0)), want, full],
	)
	t.check(
		float(events[0].get("blind", -1.0)) == 0.0,
		"the wall stops the flash: %s" % events[0].get("blind"),
	)
