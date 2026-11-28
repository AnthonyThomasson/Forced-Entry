extends GameTest
## G11 / G12 (#194 D10): `Explosion.MAX_CLEARED` is only a backstop, and what a line it ends reads
## as is the caller's rule (`Explosion.reaches`): a finite `cover_reach` (the flash, the bang) lets
## it reach, as a clear line would; INF (a frag's blast) keeps it stopped. Here more pieces than
## the cap stand on a line that none of them stops (the body is far behind the last), so the
## walk really runs out.

const BURST := Vector2(400, 100)
const VICTIM := Vector2(400, 780)
const RADIUS := 1000.0
const FIRST_Y := 150.0
## Beyond the cap, thin wardrobes (4 px deep) 5 px apart down the line: they do not overlap, so
## nothing shoves them off it.
const EXTRA := 6
const DEPTH := 4.0
const PITCH := 5.0


func describe() -> Dictionary:
	return {
		"name": "A line past the walk's cap reaches for a flash and a bang, stops for a frag",
		"description": "More wardrobes than the cap stand between a stun grenade and a character "
			+ "far behind them: the bang is not muffled and the flash reaches; the cap itself "
			+ "reads as stopped only for an infinite cover reach.",
		"tags": ["grenade", "stun", "cover", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 900))
	s.switch(&"nav.rebake", false)
	var thin: Dictionary = WorldGen.object_definition("wardrobe").duplicate()
	thin["size"] = Vector2(90.0, DEPTH)
	for i in Explosion.MAX_CLEARED + EXTRA:
		s.object(StringName("wardrobe%d" % i), thin, Vector2(BURST.x, FIRST_Y + PITCH * i))
	s.actor(&"thrower", &"puppet", Vector2(60, 60), { "max_health": 100_000.0 })
	s.actor(&"victim", &"puppet", VICTIM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	await t.frames(3)
	t.check(
		Explosion.reaches({ "exhausted": true }, Explosion.WALLS_ONLY),
		"a capped line reaches for the bang",
	)
	t.check(Explosion.reaches({ "exhausted": true }, 30.0), "a capped line reaches for the flash")
	t.check(
		not Explosion.reaches({ "exhausted": true }, INF),
		"a capped line stays stopped for a frag (an infinite reach)",
	)
	t.check(Explosion.reaches({}, INF), "a clear line reaches")
	t.check(
		not Explosion.reaches({ "collider": null }, 30.0), "a line with a stop on it does not reach"
	)
	var row: Dictionary = GrenadeConfig.row(&"stun").duplicate()
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
		"the bang is the full %.2f s past the cap: %s" % [want, events[0].get("deaf")],
	)
	t.check(
		float(events[0].get("blind", -1.0)) > 0.0,
		"the flash reaches past the cap: %s" % events[0].get("blind"),
	)
