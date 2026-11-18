extends GameTest
## P6 (docs/cover-and-stance.md), the player's trigger: a click on a semi-automatic gun that comes
## while the body rises over its cover is not lost to the rise, and it is taken once. It fires when
## the rise is done (one round, not two, however long the rise), and a click whose rise is dropped
## first (the player stands up) is void: it does not fire later as a standing body.

const SOFA_AT := Vector2(400, 250)
## 25 px short of the sofa's back (its west face at x 375).
const SHOOTER_AT := Vector2(350, 250)
const TARGET_AT := Vector2(700, 250)
const RISE_TIME := 0.3
const DWELL := 0.4


func describe() -> Dictionary:
	return {
		"name": "A click during the rise fires once after it, and stand-up voids it",
		"description": "A crouched player behind a sofa clicks a semi-automatic pistol: no round "
			+ "while it rises, one round once it has, never a second from the same click; a click "
			+ "followed by standing up before the rise ends fires nothing.",
		"tags": ["character", "posture", "crouch", "rise", "player", "input"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()  # the aim reads the plain window's pointer, which the test injects
	s.lock_interaction([&"camera"])
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(CharacterRiseConfig, &"rise_time", RISE_TIME)
	s.set_static(CharacterRiseConfig, &"dwell", DWELL)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
		straight[gun]["automatic"] = false
	s.set_static(GunConfig, &"guns", straight)
	var sofa := WorldGen.object_definition("sofa").duplicate()
	sofa["size"] = Vector2(50, 120)
	s.object(&"sofa", sofa, SOFA_AT, { "facing": Vector2.RIGHT })
	s.actor(&"you", &"player", SHOOTER_AT, { "start_slot": 3, "max_health": 100_000.0 })
	s.actor(&"target", &"puppet", TARGET_AT, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var you := t.actor(&"you")
	Pointer.inject(Pointer.screen_of(you, TARGET_AT))
	t.require(you.movement.set_posture(&"crouch"), "premise: the player ducks")
	await t.seconds(0.6)
	t.expect_eq(you.movement.body_posture(), BodyHeights.DUCK, "premise: ducked until it fires")

	await _click(t)
	t.expect_eq(you.movement.body_posture(), BodyHeights.FIRE_OVER, "the click makes it rise")
	t.expect_eq(_rounds(t), 0, "no round leaves while it rises")
	await t.seconds(RISE_TIME + 0.15)
	t.expect_eq(_rounds(t), 1, "the click's round leaves once it has risen")
	await t.seconds(0.3)
	t.expect_eq(_rounds(t), 1, "and the one click fires it once, not again")
	await t.seconds(DWELL + 0.3)
	t.expect_eq(you.movement.body_posture(), BodyHeights.DUCK, "premise: ducked again")

	await _click(t)
	t.require(you.movement.set_posture(&"stand"), "the player stands up mid-rise")
	await t.seconds(RISE_TIME + 0.4)
	t.expect_eq(_rounds(t), 1, "the click that lost its rise fires nothing as a standing body")
	Pointer.release()


## Press the fire button for two frames, as a click does, and leave it a frame after.
func _click(t: TestContext) -> void:
	Input.action_press(Keybinds.FIRE)
	await t.frames(2)
	Input.action_release(Keybinds.FIRE)
	await t.frames(1)


func _rounds(t: TestContext) -> int:
	return t.events_of(&"shot", func(d): return d["attacker"] == t.actor(&"you")).size()
