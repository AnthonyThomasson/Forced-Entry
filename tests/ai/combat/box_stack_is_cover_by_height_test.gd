extends GameTest
## #194 stack-b, D20 / SI7: a stack of boxes is cover by its real height. The AI reads the twins
## (`AgentTactics.cover_cached`: 3D lines from the threat's eye to a ducked body's head, chest and
## hips), so a stack of items on a floor hides a ducked body by the height of the stack, not the
## top of the catalogue row of the box that is struck (12 px): one box (12) and two (24) leave a
## ducked head showing (35.9), three (36 and the gaps) and a crate under two (40) hide it. The same
## line against a table with a box on it: the table's 31 and the box's 12 are 43, cover.

const AgentTactics := preload("res://scenes/ai/perception/agent_tactics.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
## The stacks, a lane each: the kinds from the floor up, and whether it is cover.
const LANES := [
	[["box"], false], [["box", "box"], false], [["box", "box", "box"], true],
	[["crate", "box", "box"], true],
]
const PIECE_X := 400.0
const SPOT_X := 340.0
const THREAT_X := 800.0
const LANE_Y := 100.0
const LANE_GAP := 130.0


func describe() -> Dictionary:
	return {
		"name": "A stack of boxes is cover by its real height",
		"description": "The AI's cover test shields a spot behind a stack of three boxes (36 px) "
			+ "or a crate and two boxes, not behind one box or two: the stack's height, the "
			+ "twins' real tops, decides it.",
		"tags": ["ai", "combat", "cover", "heights", "3d", "stacking"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, LANE_Y + LANE_GAP * LANES.size()))
	s.switch(&"nav.rebake", false)
	for i in LANES.size():
		var kinds: Array = LANES[i][0]
		for n in kinds.size():
			var id := StringName("s%d_%d" % [i, n])
			if n == 0:
				s.object(id, String(kinds[n]), Vector2(PIECE_X, _lane_y(i)))
			else:
				s.object(id, String(kinds[n]), Vector2.ZERO, {
					"on": StringName("s%d_%d" % [i, n - 1]),
				})
	s.actor(&"npc", &"puppet", Vector2(100, 50))


func run(t: TestContext) -> void:
	await t.frames(30)
	var tactics := AgentTactics.new()
	tactics.vision = AgentVision.new()
	var npc := t.actor(&"npc")
	var ctx := { "space": TwinSpace.space_of(npc), "exclude": SightRay.exclude_of(npc) }
	for i in LANES.size():
		var kinds: Array = LANES[i][0]
		var label := "+".join(kinds)
		var top := t.object(StringName("s%d_%d" % [i, kinds.size() - 1]))
		t.check(is_instance_valid(top), "the %s stack stands" % label)
		var spot := Vector2(SPOT_X, _lane_y(i))
		var shield: String = tactics.cover_cached(ctx, spot, Vector2(THREAT_X, _lane_y(i)), [])
		t.expect_eq(
			shield != "", LANES[i][1],
			"the spot behind the %s stack is shielded exactly when it is cover (%s)" % [
				label,
				shield,
			],
		)


func _lane_y(i: int) -> float:
	return LANE_Y + LANE_GAP * i
