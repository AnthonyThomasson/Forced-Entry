extends GameTest
## P6 (docs/cover-and-stance.md, D7b: no reach limit): a ducked shooter rises to the lowest pose
## whose muzzle clears every piece on its line, near or far, and stays ducked when none does (an
## NPC's gate then refuses the shot; a body fired anyway, as these puppets are, shoots from the
## duck).
## Behind a wardrobe (above a standing muzzle), at its face or 150 px on, it does
## not rise and its rounds meet the wardrobe (fire around it); in the open, with no cover, it fires
## from the duck muzzle without rising; behind a filing cabinet 150 px on (56 px: a standing
## muzzle's cover) it rises and its rounds reach the body beyond.

const WARDROBE_AT := Vector2(150, 250)
const WARDROBE_SHOOTER := Vector2(150, 297)
const OPEN_SHOOTER := Vector2(350, 300)
const FAR_SHOOTER := Vector2(550, 300)
const FAR_WARDROBE_SHOOTER := Vector2(750, 300)
## A filing cabinet (56 px: a standing shooter's cover) and a wardrobe, each 100 px or more down the
## line of fire.
const FAR_CABINET_AT := Vector2(550, 190)
const FAR_WARDROBE_AT := Vector2(750, 190)
const LANES := {
	&"wardrobe": Vector2(150, 60),
	&"open": Vector2(350, 60),
	&"far": Vector2(550, 60),
	&"far_wardrobe": Vector2(750, 60),
}


func describe() -> Dictionary:
	return {
		"name": "A ducked shooter rises for far cover it can clear and not for a wardrobe",
		"description": "Behind a wardrobe, at its face or 100 px on, the shooter stays ducked "
			+ "and its rounds meet the wardrobe; in the open its rounds leave at the duck's "
			+ "muzzle; a cabinet 100 px down the line is its cover: it rises and its rounds "
			+ "reach the body beyond.",
		"tags": ["character", "posture", "crouch", "rise", "cover", "ballistics"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsPenetrationConfig, &"min_speed", 1.0e9)
	s.set_static(CharacterRiseConfig, &"rise_time", 0.2)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
		straight[gun]["automatic"] = true
	s.set_static(GunConfig, &"guns", straight)
	s.object(&"wardrobe", "wardrobe", WARDROBE_AT)
	s.object(&"far_cabinet", "filing_cabinet", FAR_CABINET_AT)
	s.object(&"far_wardrobe", "wardrobe", FAR_WARDROBE_AT)
	var shooters := {
		&"wardrobe": WARDROBE_SHOOTER,
		&"open": OPEN_SHOOTER,
		&"far": FAR_SHOOTER,
		&"far_wardrobe": FAR_WARDROBE_SHOOTER,
	}
	for lane: StringName in LANES:
		s.actor(
			StringName("shooter_%s" % lane),
			&"puppet",
			shooters[lane],
			{ "start_slot": 3, "max_health": 100_000.0 },
		)
		s.actor(StringName("target_%s" % lane), &"puppet", LANES[lane], { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	t.check(
		BodyHeights.lowest_clearing(PieceHeights.top_of(WorldGen.object_definition("wardrobe")))
			== BodyHeights.NONE,
		"premise: no pose fires over a wardrobe",
	)
	for lane: StringName in LANES:
		t.require(
			t.actor(StringName("shooter_%s" % lane)).movement.set_posture(&"crouch"),
			"premise: the %s shooter ducks" % lane,
		)
		t.puppet(StringName("shooter_%s" % lane)).aim_at(t.actor(StringName("target_%s" % lane)))
	await t.seconds(0.6)
	for lane: StringName in LANES:
		t.puppet(StringName("shooter_%s" % lane)).hold_fire(true)
	# The open lane's first round, the frame it leaves (the far lane's shooter rises first, and a
	# round climbs toward its aim as it flies).
	t.require(
		await t.until(func(): return _rounds(t, &"shooter_open") > 0, 3.0),
		"the open shooter fires",
	)
	var open_round := _round_from(t, OPEN_SHOOTER.x)
	if open_round != null:
		t.expect_near(
			open_round.height,
			BodyHeights.muzzle(BodyHeights.DUCK),
			1.5,
			"the open shooter's round leaves at the duck's muzzle",
		)
	var fired := await t.until(
		func(): return LANES.keys().all(func(lane): return _rounds(t, _shooter(lane)) > 0),
		3.0,
	)
	t.require(fired, "every shooter fires")
	await t.seconds(1.0)
	_check_outcomes(t)


## Who rose, and whose rounds struck what, after a second of held fire.
func _check_outcomes(t: TestContext) -> void:
	for lane: StringName in [&"wardrobe", &"open", &"far_wardrobe"]:
		t.expect_eq(
			t.actor(StringName("shooter_%s" % lane)).movement.body_posture(),
			BodyHeights.DUCK,
			"the %s shooter never rises" % lane,
		)
	t.check(_hits(t, t.object(&"wardrobe")) > 0, "the wardrobe takes the wardrobe lane's rounds")
	t.expect_eq(_hits(t, t.actor(&"target_wardrobe")), 0, "and the body behind it none")
	t.check(_hits(t, t.actor(&"target_open")) > 0, "the open lane's rounds find their body")
	t.check(_hits(t, t.object(&"far_wardrobe")) > 0, "the far wardrobe takes its lane's rounds")
	t.expect_eq(_hits(t, t.actor(&"target_far_wardrobe")), 0, "and the body behind it none")
	t.expect_eq(
		t.actor(&"shooter_far").movement.body_posture(),
		BodyHeights.STAND,
		"the far lane's shooter rose over the cabinet 100 px down its line (no reach limit)",
	)
	t.check(_hits(t, t.actor(&"target_far")) > 0, "and its rounds find the body beyond")
	t.expect_eq(_hits(t, t.object(&"far_cabinet")), 0, "without touching the cabinet")


## The bullet in the world nearest the lane `x`.
func _round_from(t: TestContext, x: float) -> Node:
	for child in t.world.get_children():
		if child.name.begins_with("Projectile") and absf(child.position.x - x) < 30.0:
			return child
	return null


func _shooter(lane: StringName) -> StringName:
	return StringName("shooter_%s" % lane)


func _rounds(t: TestContext, who: StringName) -> int:
	return t.events_of(&"shot", func(d): return d["attacker"] == t.actor(who)).size()


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
