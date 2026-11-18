extends GameTest
## H1 (docs/cover-and-stance.md): a round leaves the muzzle at the shooter's posture's height
## (`BodyHeights.muzzle`): a standing shooter's bore is 65 px up, a crouched one fires from the
## fire-over muzzle (43 px), its body staying at the duck's height (36). A level shot keeps that
## height; one aimed at a body's torso starts there and climbs or falls to it.

const STAND_AT := Vector2(150, 150)
const CROUCH_AT := Vector2(150, 300)
const TARGET_AT := Vector2(700, 225)


func describe() -> Dictionary:
	return {
		"name": "A round leaves at the shooter's posture's muzzle height",
		"description": "Level pistol rounds from a standing and a crouched shooter fly at the "
			+ "standing and the fire-over muzzle heights; aimed at a standing body's torso the "
			+ "round starts at the muzzle and falls toward it.",
		"tags": ["projectile", "posture", "crouch", "aim", "ballistics"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 450))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, &"guns", straight)
	s.actor(&"stander", &"puppet", STAND_AT, { "start_slot": 3 })
	s.actor(&"ducker", &"puppet", CROUCH_AT, { "start_slot": 3 })
	s.actor(&"target", &"puppet", TARGET_AT, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	t.check(t.actor(&"ducker").movement.set_posture(&"crouch"), "the second shooter crouches")
	t.puppet(&"stander").aim_at(Vector2(880, STAND_AT.y), CharacterMovement.AIM_LEVEL)
	t.puppet(&"ducker").aim_at(Vector2(880, CROUCH_AT.y), CharacterMovement.AIM_LEVEL)
	await t.seconds(0.5)
	t.puppet(&"stander").shoot()
	t.puppet(&"ducker").shoot()
	await t.frames(2)
	var stand_round := _round_from(t, STAND_AT.y)
	var duck_round := _round_from(t, CROUCH_AT.y)
	if not t.require(stand_round != null and duck_round != null, "both rounds are in the air"):
		return
	t.expect_near(
		stand_round.height, BodyHeights.muzzle(BodyHeights.STAND), 0.01,
		"a standing shooter's level round flies at the standing muzzle's height",
	)
	t.expect_near(
		duck_round.height, BodyHeights.muzzle(BodyHeights.FIRE_OVER), 0.01,
		"a crouched shooter's, at the fire-over muzzle's (its body stays duck height)",
	)
	t.check(
		BodyHeights.muzzle(BodyHeights.FIRE_OVER) > BodyHeights.head_top(BodyHeights.DUCK),
		"premise: the fire-over bore is above the ducked head",
	)
	await t.seconds(1.0)

	# Aimed at a standing body's torso: it starts at the muzzle and falls toward the torso.
	t.puppet(&"stander").aim_at(t.actor(&"target"))
	await t.seconds(0.4)
	t.puppet(&"stander").shoot()
	await t.frames(1)
	var aimed := _round_from(t, TARGET_AT.y, 150.0)
	if not t.require(aimed != null, "the aimed round is in the air"):
		return
	t.check(aimed.rise < 0.0, "it falls toward the torso (rise %.3f)" % aimed.rise)
	await t.seconds(0.6)
	var hit: Array = t.events_of(&"hit", func(d): return d["victim"] == t.actor(&"target"))
	t.expect_eq(hit.size(), 1, "and strikes the body")


## The bullet in the world nearest the lane `y` (a plan y, within `slack` px of it).
func _round_from(t: TestContext, y: float, slack := 30.0) -> Node:
	for child in t.world.get_children():
		if child.name.begins_with("Projectile") and absf(child.position.y - y) < slack:
			return child
	return null
