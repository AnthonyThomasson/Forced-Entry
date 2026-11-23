extends GameTest
## Desired (B2): the route to a flank point is checked as the walker would take it, bent round the
## target, not as the shortest line through it. In a bare room with the NPC, the target and the
## point behind it on one line the plain shortest walk runs through the target, yet the walker goes
## round it: the rear is still offered, its checked route clears the target by `route_clearance`,
## and so are the left and right.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(120, 350)
const TARGET_POS := Vector2(620, 350)
## The clearance B2 asks of a route (`NpcTacticsTuning.route_clearance`), less a cell's slack.
const CLEARANCE := 120.0 - 4.0


func describe() -> Dictionary:
	return {
		"name": "A rear flank is offered in a bare room, its route bent round the target",
		"description": "Bare warehouse, NPC, target (facing it) and the rear point on one line: "
			+ "the rear is offered with a route that clears the target, as the left and right.",
		"tags": ["ai", "flank", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s, false)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, { "look_at": TARGET_POS })
	Flank.target(s, &"target", TARGET_POS, NPC_POS)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var zones := Flank.zones(brain)
	if not t.check(zones.has("rear"), "the rear was weighed (%s)" % Flank.dump(brain)):
		return
	var rear: Vector2 = zones["rear"]["point"]
	var straight := Flank.route(t, NPC_POS, rear)
	t.check(
		_closest(straight, TARGET_POS) < CLEARANCE,
		"premise: the plain shortest walk to the rear passes the target (%.0f px)"
			% _closest(straight, TARGET_POS),
	)
	t.expect_eq(zones["rear"]["tags"]["crosses"], false, "the rear's route is not a crossing")
	var sides := Flank.offered_sides(brain)
	t.check(
		sides.has("left") and sides.has("right") and sides.has("rear"),
		"the flank level offers every side (%s)" % [sides],
	)


## How near `path` comes to `point`.
func _closest(path: PackedVector2Array, point: Vector2) -> float:
	var best := INF
	for i in range(1, path.size()):
		best = minf(
			best,
			Geometry2D.get_closest_point_to_segment(point, path[i - 1], path[i]).distance_to(point),
		)
	return best
