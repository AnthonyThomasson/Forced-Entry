extends GameTest
## #194 D5, D7 (docs/cover-and-stance.md A-rules): a piece is cover for the AI when it is tall
## enough to duck behind, a solid part whose top hides a ducked head (36 px,
## `BodyHeights.head_top(DUCK)`), not by a rating the catalogue gives it. A sofa (back 38 px), a
## kitchen counter (38 px) and a wardrobe hide a crouched body; a coffee table (20 px) and a dining
## table (31 px, the old coverage 45) leave its head showing, so the geometry says "no cover" for
## them. The AI's tactics read it through `cover_cached`: the label of the cover-grade piece
## shielding a spot from a threat.

const AgentTactics := preload("res://scenes/ai/perception/agent_tactics.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
## The piece of each lane and whether it is cover, in the order they stand (a lane a row, 150 px
## apart); the spot behind a piece is 60 px west of it and the threat 400 px east.
const LANES := [
	[&"sofa", true], [&"kitchen_counter", true], [&"wardrobe", true],
	[&"coffee_table", false], [&"table", false], [&"desk", false],
]
const PIECE_X := 400.0
const SPOT_X := 340.0
const THREAT_X := 800.0
const LANE_Y := 100.0
const LANE_GAP := 130.0


func describe() -> Dictionary:
	return {
		"name": "Cover is a piece tall enough to duck behind",
		"description": "The AI's cover test reads real heights: a sofa, a counter and a wardrobe "
			+ "shield a spot (a crouched body hides behind them); a coffee table, a dining table "
			+ "and a desk, under a ducked head, do not.",
		"tags": ["ai", "combat", "cover", "heights", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, LANE_Y + LANE_GAP * LANES.size()))
	s.switch(&"nav.rebake", false)
	for i in LANES.size():
		var lane := _lane_y(i)
		s.object(StringName("piece_%d" % i), String(LANES[i][0]), Vector2(PIECE_X, lane))
	s.actor(&"npc", &"puppet", Vector2(100, 50))


func run(t: TestContext) -> void:
	await t.frames(3)
	var duck := BodyHeights.head_top(BodyHeights.DUCK)
	var tactics := AgentTactics.new()
	tactics.vision = AgentVision.new()
	var npc := t.actor(&"npc")
	var ctx := {
		"space": npc.get_world_2d().direct_space_state,
		"exclude": [npc.get_rid()],
	}
	for i in LANES.size():
		var name: StringName = LANES[i][0]
		var piece := t.object(StringName("piece_%d" % i))
		var top := PieceHeights.top_of(WorldGen.object_definition(String(name)))
		t.expect_eq(
			top >= duck, LANES[i][1],
			"premise: a %s is %.1f px, a ducked head %.1f" % [name, top, duck],
		)
		t.expect_eq(
			AgentTactics.is_cover(piece), LANES[i][1],
			"a %s is cover exactly when its top hides a ducked head" % name,
		)
		var spot := Vector2(SPOT_X, _lane_y(i))
		var shield: String = tactics.cover_cached(ctx, spot, Vector2(THREAT_X, _lane_y(i)), [])
		t.expect_eq(
			shield != "", LANES[i][1],
			"the spot behind the %s is shielded from the threat (%s)" % [name, shield],
		)


func _lane_y(i: int) -> float:
	return LANE_Y + LANE_GAP * i
