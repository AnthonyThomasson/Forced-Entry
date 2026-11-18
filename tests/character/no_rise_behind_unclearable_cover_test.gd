extends GameTest
## P6 (docs/cover-and-stance.md): a ducked shooter rises only when its duck muzzle line is blocked
## by cover that some pose clears. Behind a wardrobe (above a standing muzzle) it does not rise and
## its rounds meet the wardrobe (fire around it); in the open, with no cover in reach, it fires from
## the duck muzzle without rising; a far obstacle (beyond the reach) is not its cover.

const WARDROBE_AT := Vector2(250, 250)
const WARDROBE_SHOOTER := Vector2(250, 297)
const OPEN_SHOOTER := Vector2(500, 300)
const FAR_SHOOTER := Vector2(750, 300)
## A filing cabinet (56 px: a standing shooter's cover) well beyond the reach in the far lane's line
## of fire.
const FAR_CABINET_AT := Vector2(750, 150)
const LANES := {
	&"wardrobe": Vector2(250, 60), &"open": Vector2(500, 60), &"far": Vector2(750, 60),
}
const REACH := 60.0


func describe() -> Dictionary:
	return {
		"name": "A ducked shooter does not rise for a wardrobe, in the open or for far cover",
		"description": "Behind a wardrobe the shooter stays ducked and its rounds meet the "
			+ "wardrobe; in the open its rounds leave at the duck's muzzle; a cabinet far down "
			+ "the line is not its cover: it stays ducked and the round meets the cabinet.",
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
	s.set_static(CharacterRiseConfig, &"reach", REACH)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
		straight[gun]["automatic"] = true
	s.set_static(GunConfig, &"guns", straight)
	s.object(&"wardrobe", "wardrobe", WARDROBE_AT)
	s.object(&"far_cabinet", "filing_cabinet", FAR_CABINET_AT)
	var shooters := {
		&"wardrobe": WARDROBE_SHOOTER, &"open": OPEN_SHOOTER, &"far": FAR_SHOOTER,
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
	t.check(
		OPEN_SHOOTER.distance_to(FAR_CABINET_AT) > REACH + 20.0,
		"premise: the cabinet is past the reach",
	)
	# Fixed: a round shoves a free cabinet toward its body, and a cabinet beside it shows the head
	# over it, which a shooter that sees it aims at (docs/gaze-and-fire.md W2).
	t.object(&"far_cabinet").freeze = true
	for lane: StringName in LANES:
		t.require(
			t.actor(StringName("shooter_%s" % lane)).movement.set_posture(&"crouch"),
			"premise: the %s shooter ducks" % lane,
		)
		t.puppet(StringName("shooter_%s" % lane)).aim_at(t.actor(StringName("target_%s" % lane)))
	await t.seconds(0.6)
	for lane: StringName in LANES:
		t.puppet(StringName("shooter_%s" % lane)).hold_fire(true)
	var fired := await t.until(
		func(): return LANES.keys().all(func(lane): return _rounds(t, _shooter(lane)) > 0),
		3.0,
	)
	t.require(fired, "every shooter fires")
	var open_round := _round_from(t, OPEN_SHOOTER.x)
	if open_round != null:
		t.expect_near(
			open_round.height,
			BodyHeights.muzzle(BodyHeights.DUCK),
			1.5,
			"the open shooter's round leaves at the duck's muzzle",
		)
	await t.seconds(1.0)
	for lane: StringName in LANES:
		t.expect_eq(
			t.actor(StringName("shooter_%s" % lane)).movement.body_posture(),
			BodyHeights.DUCK,
			"the %s shooter never rises" % lane,
		)
	t.check(_hits(t, t.object(&"wardrobe")) > 0, "the wardrobe takes the wardrobe lane's rounds")
	t.expect_eq(_hits(t, t.actor(&"target_wardrobe")), 0, "and the body behind it none")
	t.check(_hits(t, t.actor(&"target_open")) > 0, "the open lane's rounds find their body")
	t.check(_hits(t, t.object(&"far_cabinet")) > 0, "the far lane's rounds meet the far cabinet")
	t.expect_eq(_hits(t, t.actor(&"target_far")), 0, "and not the body behind it")


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
