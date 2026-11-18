extends GameTest
## #194 D9 (docs/cover-and-stance.md A-rules): a low piece is cover only where it hides a ducked
## head from the threat's eye, the real 3D line. A sofa's back (38 px) over a ducked head (32 px)
## right behind it hides it from a standing threat far off (its eye looks along the room, over
## nothing) and from a crouched one anywhere, not from a standing one close by (its eye looks down
## over the back) and not from the seat side (the back is farther from the spot, so the line clears
## it). A wardrobe hides it from every one of them. Read through `AgentTactics.cover_cached`.

const AgentTactics := preload("res://scenes/ai/perception/agent_tactics.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const SOFA_X := 400.0
## The spot 25 px short of the sofa's west face (375): the back's, or the seat's when it faces west.
const SPOT_X := 350.0
## A far standing threat, a near one 110 px from the spot, and the seat-side spot's far threat.
const FAR_X := 680.0
const NEAR_X := 460.0
const LANE_Y := 80.0
const LANE_GAP := 120.0
## [name, piece, the sofa faces, the threat's x, ducked threat, hides?]
const LANES := [
	[&"far_standing", "sofa", Vector2.RIGHT, FAR_X, false, true],
	[&"near_standing", "sofa", Vector2.RIGHT, NEAR_X, false, false],
	[&"near_crouched", "sofa", Vector2.RIGHT, NEAR_X, true, true],
	[&"seat_side", "sofa", Vector2.LEFT, FAR_X, false, false],
	[&"wardrobe_near", "wardrobe", Vector2.RIGHT, NEAR_X, false, true],
]


func describe() -> Dictionary:
	return {
		"name": "A low piece is cover only where it hides a ducked head from the threat",
		"description": "A spot behind a sofa's back is cover from a far standing threat and a "
			+ "crouched one, not from a near standing one nor from the seat side; a wardrobe "
			+ "is cover from all of them.",
		"tags": ["ai", "combat", "cover", "heights", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, LANE_Y + LANE_GAP * LANES.size()))
	s.switch(&"nav.rebake", false)
	for i in LANES.size():
		var def := WorldGen.object_definition(String(LANES[i][1])).duplicate()
		if LANES[i][1] == "sofa":
			def["size"] = Vector2(50, 120)
		def["anchored"] = true
		s.object(
			StringName("piece_%d" % i), def, Vector2(SOFA_X, _lane_y(i)), { "facing": LANES[i][2] }
		)
		if LANES[i][4]:
			s.actor(StringName("threat_%d" % i), &"puppet", Vector2(LANES[i][3], _lane_y(i)))


func run(t: TestContext) -> void:
	for i in LANES.size():
		if LANES[i][4]:
			t.require(t.actor(StringName("threat_%d" % i)).movement.set_posture(&"crouch"), "ducks")
	await t.frames(3)
	var tactics := AgentTactics.new()
	tactics.vision = AgentVision.new()
	var space := t.world.get_world_2d().direct_space_state
	var ctx := { "space": space, "exclude": [] }
	for i in LANES.size():
		var node: Variant = t.actor(StringName("threat_%d" % i)) if LANES[i][4] else null
		var spot := Vector2(SPOT_X, _lane_y(i))
		var threat := Vector2(LANES[i][3], _lane_y(i))
		var shield: String = tactics.cover_cached(ctx, spot, threat, [], node)
		t.expect_eq(
			shield != "",
			LANES[i][5],
			"the %s lane: the spot %s hidden (%s)" % [
				LANES[i][0], "is" if LANES[i][5] else "is not", shield,
			],
		)


	for i in LANES.size():
		if LANES[i][4] or LANES[i][0] == &"seat_side":
			continue  # a crouched threat has no standing muzzle; the seat lane's margin is thin
		t.expect_eq(
			tactics._hidden_from(
				ctx,
				[Vector2(LANES[i][3], _lane_y(i))],
				Vector2(SPOT_X, _lane_y(i)),
			),
			LANES[i][5],
			"and a retreat to the spot is %s in the %s lane" % [
				"hidden" if LANES[i][5] else "not hidden", LANES[i][0],
			],
		)


func _lane_y(i: int) -> float:
	return LANE_Y + LANE_GAP * i
