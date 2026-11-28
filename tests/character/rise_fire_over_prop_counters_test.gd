extends GameTest
## P6 / D7a (docs/cover-and-stance.md): the rise asks per PART of the cover, and a prop standing on
## a counter (the shop counter's till, the noodle bar's bowl) is no part of it: the counter's own
## top (40 px) is what a ducked shooter must clear, so it rises to FIRE_OVER (muzzle 43 px), not all
## the way to STAND. Only a real part taller than the fire-over muzzle (a kitchen counter's 44 px
## backsplash: `rise_to_stand_over_tall_cover`) asks for a stand. The shooters fire level at a body
## 200 px beyond each counter.

const LANES := {
	&"shop_counter": Vector2(200, 250),
	&"noodle_counter": Vector2(600, 250),
}
const TARGET_RUN := 200.0
const SHOOTER_RUN := 45.0


func describe() -> Dictionary:
	return {
		"name": "A ducked shooter fires over a counter's top, not its till or bowl",
		"description": "Behind a shop counter and a noodle-bar counter a ducked shooter rises to "
			+ "the fire-over pose, not a stand: the props on them are no part of the cover.",
		"tags": ["character", "posture", "crouch", "rise", "cover", "heights"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(CharacterRiseConfig, &"rise_time", 0.2)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
		straight[gun]["automatic"] = true
	s.set_static(GunConfig, &"guns", straight)
	for lane: StringName in LANES:
		var at: Vector2 = LANES[lane]
		s.object(lane, String(lane), at)
		s.actor(
			StringName("shooter_%s" % lane),
			&"puppet",
			at + Vector2(0, SHOOTER_RUN),
			{ "start_slot": 3, "max_health": 100_000.0 },
		)
		s.actor(
			StringName("target_%s" % lane),
			&"puppet",
			at - Vector2(0, TARGET_RUN),
			{ "max_health": 100_000.0 },
		)


func run(t: TestContext) -> void:
	for lane: StringName in LANES:
		var parts := PieceHeights.parts_of(WorldGen.object_definition(String(lane)))
		t.expect_eq(parts.size(), 1, "premise: %s is one part (no prop in it)" % lane)
		t.expect_eq(
			BodyHeights.lowest_clearing(parts[0]["top"]),
			BodyHeights.FIRE_OVER,
			"premise: its top is cleared by the fire-over muzzle",
		)
		var shooter := t.actor(StringName("shooter_%s" % lane))
		t.require(shooter.movement.set_posture(&"crouch"), "premise: %s shooter ducks" % lane)
		t.puppet(StringName("shooter_%s" % lane)).aim_at(
			t.actor(StringName("target_%s" % lane)), CharacterMovement.AIM_LEVEL
		)
	await t.seconds(0.6)
	for lane: StringName in LANES:
		t.puppet(StringName("shooter_%s" % lane)).hold_fire(true)
	await t.seconds(1.0)
	for lane: StringName in LANES:
		var shooter := t.actor(StringName("shooter_%s" % lane))
		t.expect_eq(
			shooter.movement.body_posture(),
			BodyHeights.FIRE_OVER,
			"the %s shooter rises only to fire over" % lane,
		)
		var hits := t.events_of(
			&"hit", func(d): return d["victim"] == t.actor(StringName("target_%s" % lane))
		)
		t.check(hits.size() > 0, "and hits the body beyond the %s (%d)" % [lane, hits.size()])
