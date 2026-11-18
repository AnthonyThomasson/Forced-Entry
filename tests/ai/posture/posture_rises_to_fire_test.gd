extends GameTest
## A defender fighting from behind cover fires by rising over it (docs/cover-and-stance.md A1, P6).
## A crouched defender with a hostile in view behind a sofa (38 px): its duck muzzle is blocked, so
## it rises to the fire-over pose, shoots over the back and hits the hostile, and ducks again after
## the dwell. Server down.

const COVER_AT := Vector2(340, 150)
const DEFENDER_AT := Vector2(300, 150)
const FOE_AT := Vector2(750, 150)


func describe() -> Dictionary:
	return {
		"name": "A defender behind a sofa rises to fire over it",
		"description": "Fighting from behind a sofa with the server down: the defender "
			+ "crouches, rises to the fire-over pose to shoot, hits the hostile and ducks again.",
		"tags": ["ai", "posture", "crouch", "cover", "rise"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 300))
	s.von_down()
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"nav.rebake", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsPenetrationConfig, &"min_speed", 1.0e9)
	var sofa := WorldGen.object_definition("sofa").duplicate()
	sofa["size"] = Vector2(50, 120)
	s.object(&"sofa", sofa, COVER_AT, { "facing": Vector2.RIGHT })
	s.actor(&"defender", &"defender", DEFENDER_AT)
	s.actor(&"foe", &"puppet", FOE_AT, { "faction": &"invader", "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var defender: Node = t.actor(&"defender")
	defender.movement.aim_point = FOE_AT
	t.check(
		await t.until(
			func(): return defender.movement.body_posture() == BodyHeights.FIRE_OVER,
			20.0,
		),
		"behind the sofa it rises to the fire-over pose to shoot",
	)
	t.check(
		await t.until(func(): return _hits(t, t.actor(&"foe")) > 0, 10.0),
		"and its rounds hit the hostile over the sofa",
	)
	t.check(
		await t.until(func(): return _ducked(defender), 10.0),
		"it is ducked again between bursts",
	)
	t.expect_eq(_hits(t, t.object(&"sofa")), 0, "and none of its rounds struck the sofa")


func _ducked(who: Node) -> bool:
	return who.movement.body_posture() == BodyHeights.DUCK and who.movement.posture() == &"crouch"


func _rounds(t: TestContext, who: Node) -> int:
	return t.events_of(&"shot", func(d): return d["attacker"] == who).size()


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
