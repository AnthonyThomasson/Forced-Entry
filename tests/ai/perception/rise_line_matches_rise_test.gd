extends GameTest
## P6 (docs/cover-and-stance.md): an NPC's choice to fire from behind cover and the rise of its shot
## are one rule (`CharacterRise.pose_along`). `AgentVision.fire_line_clear` says a crouched NPC can
## fire exactly where the body, trigger held, does hit the body beyond: behind a filing cabinet
## right in front of it (a fire-over muzzle hits it, a standing one clears: the rise is to STAND and
## the rounds find the body); not behind a wardrobe (no pose clears) and not past a cabinet beyond
## the reach (not its cover, so the body does not rise and the rounds meet the cabinet).

const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const SHOOTERS := {
	&"near": Vector2(250, 297), &"wardrobe": Vector2(500, 297), &"far": Vector2(750, 300),
}
const TARGETS := {
	&"near": Vector2(250, 60), &"wardrobe": Vector2(500, 60), &"far": Vector2(750, 60),
}
## A cabinet 96 px from the far shooter: past the reach, near enough that a standing muzzle's line
## to the body beyond it still passes over (the old gate's yes, the rise's no).
const FAR_CABINET_AT := Vector2(750, 204)
const CLEAR := { &"near": true, &"wardrobe": false, &"far": false }


func describe() -> Dictionary:
	return {
		"name": "The AI's rise line and the body's rise agree",
		"description": "The AI gate for firing from behind cover says yes only where the ducked "
			+ "body, firing, rises to a pose whose rounds reach the body beyond: a cabinet at its "
			+ "face (it rises to stand), and no for a wardrobe and for a cabinet past the reach.",
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
	s.object(&"near_cabinet", "filing_cabinet", Vector2(250, 250))
	s.object(&"wardrobe", "wardrobe", Vector2(500, 250))
	# Anchored, so the rounds it stops do not shove it aside: shoved, it would uncover the head the
	# shooter then sees and aims over it.
	var far_cabinet: Dictionary = WorldGen.object_definition("filing_cabinet").duplicate()
	far_cabinet["anchored"] = true
	s.object(&"far_cabinet", far_cabinet, FAR_CABINET_AT)
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
	t.check(
		SHOOTERS[&"far"].distance_to(FAR_CABINET_AT) - 20.0 > CharacterRiseConfig.reach,
		"premise: the far cabinet's face is past the reach",
	)
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
		t.puppet(StringName("shooter_%s" % lane)).hold_fire(true)
	await t.seconds(1.2)
	for lane: StringName in SHOOTERS:
		var risen: bool = _shooter(t, lane).movement.body_posture() != BodyHeights.DUCK
		t.expect_eq(risen, CLEAR[lane], "the %s shooter rises exactly where the AI would" % lane)
		var hits := _hits(t, _target(t, lane))
		t.expect_eq(hits > 0, CLEAR[lane], "and its rounds reach the body (%d) just then" % hits)
	t.expect_eq(
		_shooter(t, &"near").movement.body_posture(),
		BodyHeights.STAND,
		"the cabinet at its face is fired over standing, a fire-over muzzle hitting it",
	)


func _shooter(t: TestContext, lane: StringName) -> Node:
	return t.actor(StringName("shooter_%s" % lane))


func _target(t: TestContext, lane: StringName) -> Node:
	return t.actor(StringName("target_%s" % lane))


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
