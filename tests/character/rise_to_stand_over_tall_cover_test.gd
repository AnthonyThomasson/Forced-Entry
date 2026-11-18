extends GameTest
## P6 (docs/cover-and-stance.md): a ducked shooter rises only as far as it must (D7a). Cover its
## fire-over muzzle (43 px) does not clear is fired over standing (muzzle 65 px): a filing cabinet
## (56 px), and a kitchen counter whose top (38) the fire-over clears but whose backsplash (44), a
## part of the same piece along the rear, it does not. Rising per PART, not per piece.

const CABINET_AT := Vector2(250, 250)
const COUNTER_AT := Vector2(600, 250)
## South of each piece (25 px off its face), firing north at a body far beyond it.
const CABINET_SHOOTER := Vector2(250, 297)
const COUNTER_SHOOTER := Vector2(600, 300)
const TARGETS := { &"cabinet": Vector2(250, 60), &"counter": Vector2(600, 60) }


func describe() -> Dictionary:
	return {
		"name": "A ducked shooter rises to stand over cover too tall to fire over",
		"description": "Behind a filing cabinet, and in front of a counter whose backsplash is "
			+ "taller than its top, a ducked shooter rises all the way to a standing pose and "
			+ "hits the body beyond, the piece taking none of the rounds.",
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
	s.object(&"cabinet", "filing_cabinet", CABINET_AT)
	s.object(&"counter", "kitchen_counter", COUNTER_AT)
	var shooters := { &"cabinet": CABINET_SHOOTER, &"counter": COUNTER_SHOOTER }
	for lane: StringName in shooters:
		s.actor(
			StringName("shooter_%s" % lane),
			&"puppet",
			shooters[lane],
			{ "start_slot": 3, "max_health": 100_000.0 },
		)
		s.actor(
			StringName("target_%s" % lane),
			&"puppet",
			TARGETS[lane],
			{ "max_health": 100_000.0 },
		)


func run(t: TestContext) -> void:
	var cabinet_top := PieceHeights.top_of(WorldGen.object_definition("filing_cabinet"))
	var parts := PieceHeights.parts_of(WorldGen.object_definition("kitchen_counter"))
	var counter_top: float = parts[0]["top"]
	var splash_top: float = parts[parts.size() - 1]["top"]
	t.expect_eq(BodyHeights.lowest_clearing(cabinet_top), BodyHeights.STAND, "premise: cabinet")
	t.expect_eq(BodyHeights.lowest_clearing(counter_top), BodyHeights.FIRE_OVER, "premise: top")
	t.expect_eq(BodyHeights.lowest_clearing(splash_top), BodyHeights.STAND, "premise: splash")
	for lane: StringName in TARGETS:
		var shooter := t.actor(StringName("shooter_%s" % lane))
		t.require(shooter.movement.set_posture(&"crouch"), "premise: %s shooter ducks" % lane)
		# The counter's lane is a level shot: a shot aimed up at the torso already climbs over the
		# 44 px splash from the fire-over muzzle (43 px) and needs no more rise.
		var height := CharacterMovement.AIM_AUTO
		if lane == &"counter":
			height = CharacterMovement.AIM_LEVEL
		t.puppet(StringName("shooter_%s" % lane)).aim_at(
			t.actor(StringName("target_%s" % lane)), height
		)
	await t.seconds(0.6)
	for lane: StringName in TARGETS:
		t.puppet(StringName("shooter_%s" % lane)).hold_fire(true)
	await t.seconds(1.0)
	for lane: StringName in TARGETS:
		var shooter := t.actor(StringName("shooter_%s" % lane))
		t.expect_eq(
			shooter.movement.body_posture(),
			BodyHeights.STAND,
			"the %s shooter rises all the way to stand" % lane,
		)
		var hits := _hits(t, t.actor(StringName("target_%s" % lane)))
		t.check(hits > 0, "and hits the body beyond the %s (%d)" % [lane, hits])
		t.expect_eq(_hits(t, t.object(lane)), 0, "the %s takes none of its rounds" % lane)


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
