extends GameTest
## G8 (#194 D10): the fragments are real rays rising from the burst, stopped by what is in their
## way, so a body ducked behind a couch is shielded from them and one standing beside it is hit.
## A row of couches 50 px from a burst on the floor; a ducked dummy right behind them (125 px from
## the burst) and a standing one beside the row (200 px, nothing between it and the burst), over 120
## bursts: the standing one takes fragment hits, the ducked one none. (The whole frag, blast and
## fragments, killing the one and sparing the other: `frag_kills_standing_spares_ducked`.)

const AT := Vector2(700, 400)
const BURSTS := 120
## the couches (their back edge at y 450) and the dummies
const ROW_Y := 480.0


func describe() -> Dictionary:
	return {
		"name": "A ducked body behind a couch takes no fragment, a standing one beside it does",
		"description": "Over 120 frag bursts (the blast switched off) a standing dummy in the "
			+ "open takes fragment hits and a ducked one behind a row of couches takes none.",
		"tags": ["grenade", "frag", "fragments", "cover", "posture", "3d"],
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 1000))
	s.switch(&"nav.rebake", false)
	for i in 3:
		s.object(StringName("couch_%d" % i), "sofa", Vector2(AT.x - 120.0 + 120.0 * i, ROW_Y))
	s.actor(&"thrower", &"puppet", Vector2(60, 60), { "max_health": 1.0e9 })
	s.actor(&"ducked", &"puppet", Vector2(AT.x, 525.0), { "max_health": 1.0e9 })
	s.actor(&"standing", &"puppet", Vector2(AT.x + 195.0, 450.0), { "max_health": 1.0e9 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var ducked := t.actor(&"ducked")
	var standing := t.actor(&"standing")
	t.puppet(&"ducked").set_posture(&"crouch")
	await t.seconds(0.6)
	var row: Dictionary = (GrenadeConfig.grenades[&"frag"] as Dictionary).duplicate()
	row["blast_damage"] = 0.0
	row["blast_impulse"] = 0.0
	# every hit shoves and spins what it strikes: each burst finds the dummies and the couches where
	# (and as) they stood (a couch left turned would show a gap or its low seat side to the burst)
	var placed: Dictionary = {}
	var turned: Dictionary = {}
	for body: Node2D in [ducked, standing] + _couches(t):
		placed[body] = body.global_position
		turned[body] = body.rotation
	for _i in BURSTS:
		for body: Node2D in placed:
			body.global_position = placed[body]
			body.rotation = turned[body]
			body.set("angular_velocity", 0.0)
			body.set("linear_velocity", Vector2.ZERO)
			body.set("velocity", Vector2.ZERO)
		Explosion.frag(AT, t.world, thrower, row)
		await t.frames(14)
	var hits := func(victim: Node) -> int:
		return t.events_of(
			&"hit",
			func(d): return d.get("victim") == victim and d.get("outcome") != &"blast",
		).size()
	t.check(
		hits.call(standing) >= 5,
		"the standing dummy is hit (%d fragments)" % hits.call(standing),
	)
	t.expect_eq(hits.call(ducked), 0, "the ducked dummy behind the couches is hit by none")


## The three couches.
func _couches(t: TestContext) -> Array:
	return [t.object(&"couch_0"), t.object(&"couch_1"), t.object(&"couch_2")]
