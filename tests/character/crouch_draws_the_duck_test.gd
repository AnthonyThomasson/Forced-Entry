extends GameTest
## P1 and P3 (docs/cover-and-stance.md): the drawn crouch and the duck are one height. Settled, a
## crouched body is drawn as tall as the duck's head top (`BodyHeights`, 36 px), so the mesh, the
## twin and sight agree; risen to fire over cover, the drawn body rises to the fire-over's head top
## and drops back with the dwell.

const SOFA_AT := Vector2(400, 250)
const SHOOTER_AT := Vector2(350, 250)


func describe() -> Dictionary:
	return {
		"name": "A crouched body is drawn as tall as the duck",
		"description": "A standing body is drawn 74 px, a crouched one the duck's 36, and one "
			+ "risen over a sofa the fire-over's 52; the drawn height eases back with the dwell.",
		"tags": ["character", "posture", "crouch", "rig", "heights"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.set_static(CharacterRiseConfig, &"rise_time", 0.1)
	s.set_static(CharacterRiseConfig, &"dwell", 0.4)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
		straight[gun]["automatic"] = true
	s.set_static(GunConfig, &"guns", straight)
	var sofa := WorldGen.object_definition("sofa").duplicate()
	sofa["size"] = Vector2(50, 120)
	s.object(&"sofa", sofa, SOFA_AT, { "facing": Vector2.RIGHT })
	s.actor(&"shooter", &"puppet", SHOOTER_AT, { "start_slot": 3, "max_health": 100_000.0 })
	s.actor(&"target", &"puppet", Vector2(700, 250), { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var shooter := t.actor(&"shooter")
	t.puppet(&"shooter").aim_at(t.actor(&"target"))
	await t.seconds(0.5)
	t.expect_near(_drawn(shooter), BodyHeights.head_top(BodyHeights.STAND), 0.5, "standing")
	t.require(shooter.movement.set_posture(&"crouch"), "premise: it ducks")
	await t.seconds(1.0)
	t.expect_near(_drawn(shooter), BodyHeights.head_top(BodyHeights.DUCK), 0.5, "crouched")
	t.puppet(&"shooter").hold_fire(true)
	await t.seconds(1.0)
	t.expect_near(
		_drawn(shooter), BodyHeights.head_top(BodyHeights.FIRE_OVER), 0.5, "risen over the sofa"
	)
	t.puppet(&"shooter").hold_fire(false)
	await t.seconds(1.5)
	t.expect_near(_drawn(shooter), BodyHeights.head_top(BodyHeights.DUCK), 0.5, "ducked again")


## The drawn body's head top (px): a standing one's times how far it is folded.
func _drawn(shooter: Node) -> float:
	return shooter.movement.posture_height() * BodyHeights.head_top(BodyHeights.STAND)
