extends GameTest
## #194 rule 5 (docs/gaze-and-fire.md W2): a body is no obstacle to sight but a round hits it, so an
## NPC line of fire is held by a living ally standing in it. Three lanes, a shooter 400 px from its
## target and the ally (a puppet) between them: the ally standing holds the shot; the ally ducked
## (a head 36 px up under a muzzle's 65 px line) is shot over; no ally leaves the line clear.

const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const LANES := { &"standing": 100.0, &"ducked": 250.0, &"none": 400.0 }
const SHOOTER_X := 100.0
const ALLY_X := 300.0
const TARGET_X := 500.0


func describe() -> Dictionary:
	return {
		"name": "An ally in the line of fire holds the shot unless it is ducked",
		"description": "fire_line_clear is false with a standing ally between the shooter and its "
			+ "target, true over a ducked one or with none, and ally_in_fire_line names the ally.",
		"tags": ["ai", "perception", "cover", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	for lane: StringName in LANES:
		var y: float = LANES[lane]
		s.actor(StringName("shooter_%s" % lane), &"puppet", Vector2(SHOOTER_X, y))
		s.actor(StringName("target_%s" % lane), &"puppet", Vector2(TARGET_X, y))
		if lane != &"none":
			s.actor(StringName("ally_%s" % lane), &"puppet", Vector2(ALLY_X, y))


func run(t: TestContext) -> void:
	t.check(t.actor(&"ally_ducked").movement.set_posture(&"crouch"), "the ally ducks")
	await t.frames(5)
	var vision := AgentVision.new()
	var clear := {}
	for lane: StringName in LANES:
		var shooter: Node2D = t.actor(StringName("shooter_%s" % lane))
		var target: Node2D = t.actor(StringName("target_%s" % lane))
		clear[lane] = vision.fire_line_clear(shooter, target, target.global_position)
	t.expect_eq(clear[&"standing"], false, "a standing ally holds the shot")
	t.expect_eq(clear[&"ducked"], true, "a ducked one is shot over")
	t.expect_eq(clear[&"none"], true, "with no ally the line is clear")
	var named := vision.ally_in_fire_line(
		t.actor(&"shooter_standing"),
		t.actor(&"target_standing"),
		t.actor(&"target_standing").global_position,
	)
	t.check(named == t.actor(&"ally_standing"), "and the ally in the way is named")
