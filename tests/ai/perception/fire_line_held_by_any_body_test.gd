extends GameTest
## #194 rule 5 (docs/gaze-and-fire.md W2): a body is no obstacle to sight but a round hits it, so an
## NPC's line of fire is held by any living body standing in it: an ally, a bystander, the human
## player; not one the NPC knows as hostile, which a round may hit, and not one ducked under the
## line. Five lanes, a shooter 400 px from its target and a body (a puppet) between them: standing,
## ducked, none, a known hostile, and a bystander the shooter has no word on.

const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const LANES := {
	&"standing": 60.0, &"ducked": 160.0, &"none": 260.0, &"hostile": 360.0, &"bystander": 460.0,
}
const SHOOTER_X := 100.0
const BODY_X := 300.0
const TARGET_X := 500.0
const CLEAR := {
	&"standing": false, &"ducked": true, &"none": true, &"hostile": true, &"bystander": false,
}


func describe() -> Dictionary:
	return {
		"name": "Any body in the line of fire holds the shot, bar a known hostile or a ducked one",
		"description": "fire_line_clear is false with a standing body (ally or bystander) between "
			+ "the shooter and its target, true over a ducked one, with none, or with one the "
			+ "shooter knows as hostile; body_in_fire_line names the body.",
		"tags": ["ai", "perception", "cover", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 520))
	s.switch(&"nav.rebake", false)
	for lane: StringName in LANES:
		var y: float = LANES[lane]
		s.actor(StringName("shooter_%s" % lane), &"puppet", Vector2(SHOOTER_X, y))
		s.actor(StringName("target_%s" % lane), &"puppet", Vector2(TARGET_X, y))
		if lane != &"none":
			s.actor(StringName("body_%s" % lane), &"puppet", Vector2(BODY_X, y))


func run(t: TestContext) -> void:
	t.check(t.actor(&"body_ducked").movement.set_posture(&"crouch"), "the body ducks")
	await t.frames(5)
	var vision := AgentVision.new()
	var welcome := func(body: Node) -> bool: return body == t.actor(&"body_hostile")
	for lane: StringName in LANES:
		var shooter: Node2D = t.actor(StringName("shooter_%s" % lane))
		var target: Node2D = t.actor(StringName("target_%s" % lane))
		t.expect_eq(
			vision.fire_line_clear(shooter, target, target.global_position, welcome),
			CLEAR[lane],
			"the %s lane's line" % lane,
		)
	var named := vision.body_in_fire_line(
		t.actor(&"shooter_bystander"),
		t.actor(&"target_bystander"),
		t.actor(&"target_bystander").global_position,
		welcome,
	)
	t.check(named == t.actor(&"body_bystander"), "and the bystander in the way is named")
	t.check(
		vision.body_in_fire_line(
			t.actor(&"shooter_hostile"),
			t.actor(&"target_hostile"),
			t.actor(&"target_hostile").global_position,
			welcome,
		) == null,
		"a known hostile in the way is named by none",
	)
