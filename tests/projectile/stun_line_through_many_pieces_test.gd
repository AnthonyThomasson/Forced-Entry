extends GameTest
## G11 / G12 (#194 D10): a line from the burst that passes more twins than `Explosion.MAX_CLEARED`
## without one stopping it counts as stopped (the walk's `exhausted` answer), for the flash and the
## bang alike. Nine wardrobes stand in a row between a stun grenade and a character: the burst
## must reach the character's lines without a script error (the walk's answer has no hit to read),
## and the character is not flashed through nine wardrobes.

const BURST := Vector2(400, 100)
const VICTIM := Vector2(400, 780)
## Nine wardrobes (45 px deep) with a 10 px gap, down the line from the burst to the victim.
const FIRST_Y := 190.0
const STEP := 55.0
const PIECES := 9


func describe() -> Dictionary:
	return {
		"name": "A stun's line past more pieces than the walk clears counts as stopped",
		"description": "Nine wardrobes stand between a stun grenade and a character: the burst "
			+ "reads the line as stopped, with no script error, and the character is stunned "
			+ "(the bang reaches by range) but not flashed.",
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
	row["flash_radius"] = 1000.0
	row["bang_radius"] = 1000.0
	var victim := t.actor(&"victim")
	Explosion.stun(BURST, t.world, t.actor(&"thrower"), row)
	await t.frames(2)
	var events := t.events_of(&"stun", func(d): return d.get("character") == victim)
	if not t.require(not events.is_empty(), "the victim is stunned (the bang reaches by range)"):
		return
	t.check(
		float(events[0].get("blind", -1.0)) == 0.0,
		"the victim is not flashed through nine wardrobes",
	)
