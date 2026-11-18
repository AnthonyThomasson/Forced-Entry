extends GameTest
## G7, G8 (#194 D10): a whole frag, its blast and its fragments, kills a standing hostile and spares
## a ducked one the same distance from it behind a sofa. A row of couches 55 px from a frag on the
## floor; a ducked hostile right behind them and a standing one in the open, each 125 px from the
## burst (inside the kill radius, where the blast alone deals more than a character's 50 HP): the
## couches' back (38 px) shields the ducked head (36 px) from the blast and from every fragment, the
## standing one has nothing between it and the burst.

const AT := Vector2(700, 400)
const ROW_Y := 480.0


func describe() -> Dictionary:
	return {
		"name": "A frag kills a standing hostile and spares a ducked one behind a sofa",
		"description": "A frag goes off 125 px from a standing hostile in the open and from a "
			+ "ducked one behind a row of couches: the standing one dies, the ducked one is "
			+ "untouched.",
		"tags": ["grenade", "frag", "blast", "fragments", "cover", "posture", "3d"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 1000))
	s.switch(&"nav.rebake", false)
	for i in 3:
		s.object(StringName("couch_%d" % i), "sofa", Vector2(AT.x - 120.0 + 120.0 * i, ROW_Y))
	s.actor(&"thrower", &"puppet", Vector2(60, 60), { "max_health": 1.0e9 })
	s.actor(&"ducked", &"puppet", Vector2(AT.x, AT.y + 125.0), { "faction": &"household" })
	s.actor(&"standing", &"puppet", Vector2(AT.x + 125.0, AT.y), { "faction": &"household" })


func run(t: TestContext) -> void:
	var ducked := t.actor(&"ducked")
	var standing := t.actor(&"standing")
	t.puppet(&"ducked").set_posture(&"crouch")
	await t.seconds(0.6)
	var row: Dictionary = GrenadeConfig.grenades[&"frag"]
	Explosion.frag(AT, t.world, t.actor(&"thrower"), row)
	await t.seconds(1.0)
	t.check(standing.is_dead, "the standing hostile in the open is killed")
	t.check(
		not ducked.is_dead and ducked.health >= ducked.max_health - 0.01,
		"the ducked one behind the couches is untouched (%.0f / %.0f)"
			% [ducked.health, ducked.max_health],
	)
