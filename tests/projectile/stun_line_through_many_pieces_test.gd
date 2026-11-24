extends GameTest
## G11 / G12 (#194 D10): a line from the burst that passes many pieces of furniture, none of them
## at the body's face, is not stopped by their number. Nine wardrobes (more than the 8 the walk
## once cleared) stand in a row between a stun grenade and a character 128 px behind the last of
## them: the bang is the full fall-off of the distance (furniture muffles nothing, G12: not x0.4)
## and the flash reaches the eye (the pieces are far from the body, G11).

const BURST := Vector2(400, 100)
const VICTIM := Vector2(400, 780)
## Nine wardrobes (45 px deep) with a 10 px gap, down the line from the burst to the victim.
const FIRST_Y := 190.0
const STEP := 55.0
const PIECES := 9
const RADIUS := 1000.0


func describe() -> Dictionary:
	return {
		"name": "A stun's line through nine wardrobes is not stopped by their number",
		"description": "Nine wardrobes stand between a stun grenade and a character 128 px "
			+ "behind the last: the bang is not muffled and the flash reaches it.",
		"tags": ["grenade", "stun", "cover", "3d"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 900))
	s.switch(&"nav.rebake", false)
	for i in PIECES:
		s.object(StringName("wardrobe%d" % i), "wardrobe", Vector2(BURST.x, FIRST_Y + STEP * i))
	s.actor(&"thrower", &"puppet", Vector2(60, 60), { "max_health": 100_000.0 })
	s.actor(&"victim", &"puppet", VICTIM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	await t.frames(3)
	var row: Dictionary = GrenadeConfig.row(&"stun").duplicate()
	# Reach the victim, 680 px off, whatever the stock radii are.
	row["flash_radius"] = RADIUS
	row["bang_radius"] = RADIUS
	var victim := t.actor(&"victim")
	Explosion.stun(BURST, t.world, t.actor(&"thrower"), row)
	await t.frames(2)
	var events := t.events_of(&"stun", func(d): return d.get("character") == victim)
	if not t.require(not events.is_empty(), "the victim is stunned"):
		return
	var want := float(row["max_deaf"]) * (1.0 - BURST.distance_to(VICTIM) / RADIUS)
	t.check(
		absf(float(events[0].get("deaf", -1.0)) - want) < 0.01,
		"the bang is the full %.2f s through nine wardrobes (not x%s): %s"
			% [want, row["wall_factor"], events[0].get("deaf")],
	)
	t.check(
		float(events[0].get("blind", -1.0)) > 0.0,
		"the victim 128 px behind the last wardrobe is flashed: %s" % events[0].get("blind"),
	)
