extends GameTest
## P6 (docs/cover-and-stance.md): an NPC's choice to fire from behind cover and the rise of its shot
## are one rule (`CharacterRise.pose_along`, D7b: no reach limit, near or far). The trigger's gate
## (`AgentVision.fire_line_clear`) and the line of a spot (`fire_stop_from`, which the snapshot and
## the fire spots ask) say yes exactly where the body, trigger held, does hit the body beyond: over
## a filing cabinet at its face or 96 px on (the rise is to STAND), over a sofa 130 px ahead of a
## body 300 px past it (to FIRE_OVER); not behind a wardrobe, at its face or 150 px on (no pose
## clears: it stays ducked and its rounds meet the wardrobe).

const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const SHOOTERS := {
	&"near": Vector2(100, 297), &"wardrobe": Vector2(250, 297), &"far": Vector2(400, 300),
	&"sofa": Vector2(550, 470), &"far_wardrobe": Vector2(750, 470),
}
const TARGETS := {
	&"near": Vector2(100, 60), &"wardrobe": Vector2(250, 60), &"far": Vector2(400, 60),
	&"sofa": Vector2(550, 40), &"far_wardrobe": Vector2(750, 70),
}
## A cabinet 96 px from the far shooter, a sofa 130 px from the sofa shooter (its body 300 px past
## it) and a wardrobe 150 px from the far-wardrobe shooter: none is within the old 60 px reach.
const FAR_CABINET_AT := Vector2(400, 204)
const SOFA_AT := Vector2(550, 340)
const FAR_WARDROBE_AT := Vector2(750, 320)
const CLEAR := {
	&"near": true, &"wardrobe": false, &"far": true, &"sofa": true, &"far_wardrobe": false,
}
## The pose each shooter rises to (the duck for those it never rises for).
const POSE := {
	&"near": BodyHeights.STAND, &"wardrobe": BodyHeights.DUCK, &"far": BodyHeights.STAND,
	&"sofa": BodyHeights.FIRE_OVER, &"far_wardrobe": BodyHeights.DUCK,
}


func describe() -> Dictionary:
	return {
		"name": "The AI's rise line and the body's rise agree, near cover and far",
		"description": "The AI gate and the spot line say yes only where the ducked body, "
			+ "firing, rises to a pose whose rounds reach the body beyond: a cabinet at its face "
			+ "or 96 px on (stand), a sofa 130 px ahead (fire over), and no for a wardrobe, "
			+ "at its face or 150 px on (no reach limit: it stays ducked).",
		"tags": ["ai", "perception", "posture", "rise", "cover", "3d"],
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
	s.object(&"near_cabinet", "filing_cabinet", Vector2(100, 250))
	s.object(&"wardrobe", "wardrobe", Vector2(250, 250))
	s.object(&"far_cabinet", "filing_cabinet", FAR_CABINET_AT)
	var sofa := WorldGen.object_definition("sofa").duplicate()
	sofa["size"] = Vector2(50, 120)
	s.object(&"sofa", sofa, SOFA_AT, { "facing": Vector2.UP })
	s.object(&"far_wardrobe", "wardrobe", FAR_WARDROBE_AT)
	for lane: StringName in SHOOTERS:
		s.actor(
			StringName("shooter_%s" % lane),
			&"puppet",
			SHOOTERS[lane],
			{ "start_slot": 3, "max_health": 100_000.0 },
		)
		s.actor(
			StringName("target_%s" % lane),
			&"puppet",
			TARGETS[lane],
			{ "max_health": 100_000.0 },
		)


func run(t: TestContext) -> void:
	var vision := AgentVision.new()
	for lane: StringName in SHOOTERS:
		t.require(
			_shooter(
				t,
				lane,
			).movement.set_posture(&"crouch"), "premise: the %s shooter ducks" % lane
		)
		t.puppet(StringName("shooter_%s" % lane)).aim_at(_target(t, lane))
	await t.seconds(0.6)
	var gate := {}
	for lane: StringName in SHOOTERS:
		gate[lane] = vision.fire_line_clear(
			_shooter(t, lane), _target(t, lane), _target(t, lane).global_position
		)
		t.expect_eq(gate[lane], CLEAR[lane], "the AI's rise line toward the %s body" % lane)
		t.expect_eq(
			vision.fire_stop_from(
				t.world.get_world_2d().direct_space_state,
				_shooter(t, lane).global_position,
				_target(t, lane).global_position,
				_target(t, lane),
			).is_empty(),
			CLEAR[lane],
			"and the line of the spot it stands at, toward the %s body" % lane,
		)
		t.puppet(StringName("shooter_%s" % lane)).hold_fire(true)
	await t.seconds(1.2)
	for lane: StringName in SHOOTERS:
		var risen: bool = _shooter(t, lane).movement.body_posture() != BodyHeights.DUCK
		t.expect_eq(risen, CLEAR[lane], "the %s shooter rises exactly where the AI would" % lane)
		var hits := _hits(t, _target(t, lane))
		t.expect_eq(hits > 0, CLEAR[lane], "and its rounds reach the body (%d) just then" % hits)
	for lane: StringName in SHOOTERS:
		if CLEAR[lane]:
			t.expect_eq(
				_shooter(t, lane).movement.body_posture(),
				POSE[lane],
				"the %s shooter fires from the lowest pose that clears" % lane,
			)


func _shooter(t: TestContext, lane: StringName) -> Node:
	return t.actor(StringName("shooter_%s" % lane))


func _target(t: TestContext, lane: StringName) -> Node:
	return t.actor(StringName("target_%s" % lane))


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
