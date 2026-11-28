extends GameTest
## Desired (B2): the route to a flank point is checked as the walker would take it, bent round the
## target, not as the shortest line through it. In a bare room with the NPC, the target and the
## point behind it on one line the plain shortest walk runs through the target, yet the walker goes
## round it: the rear is still offered, its checked route clears the target by `route_clearance`,
## and so are the left and right. The checked route is the walked one: the flank goal carries the
## waypoint the route bends by (`via`), and the NPC sent to the rear passes the target no nearer
## than the route does (less the walker's own slack, `WALK_SLACK`).

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(120, 350)
const TARGET_POS := Vector2(620, 350)
## The clearance B2 asks of a route (`NpcTacticsTuning.route_clearance`), less a cell's slack.
const CLEARANCE := 120.0 - 4.0
## How much nearer the walker's body may come than the route it follows: measured 6 px here (145 px
## offered, 139 walked: it cuts the corner at the waypoint the agent's reach stops short of).
const WALK_SLACK := 12.0
const WALK_SPEED := 150.0                # the invader preset's speed


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
	Flank.rules(s, [{ "pick": "combat" }, { "pick": "flank" }, { "pick": "side_rear" }])
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
	# The offered route: the goal's waypoint, then the point. Its clearance, not only `crosses`.
	if not t.check(zones["rear"].has("via"), "the rear goal carries the waypoint it bends by"):
		return
	var via: Vector2 = zones["rear"]["via"]
	var offered := Flank.route(t, NPC_POS, via)
	offered.append_array(Flank.route(t, via, rear).slice(1))
	t.check(
		_closest(offered, TARGET_POS) >= CLEARANCE,
		"the offered route clears the target by route_clearance (%.0f px)"
			% _closest(offered, TARGET_POS),
	)
	await _walk_clears_target(t, brain, rear)


## The walk: the NPC goes to the rear and never comes nearer the target than the route does.
func _walk_clears_target(t: TestContext, brain: Node, rear: Vector2) -> void:
	var npc := t.actor(&"npc")
	brain.tuning.decision.max_commit_time = 6.0
	npc.movement.speed = WALK_SPEED
	var walked := PackedVector2Array([npc.global_position])
	var arrived := await t.until(
		func():
			walked.append(npc.global_position)
			return npc.global_position.distance_to(rear) < 40.0,
		25.0, "the NPC walks to the rear point (at %s, point %s)" % [npc.global_position, rear],
	)
	if arrived:
		t.check(
			_closest(walked, TARGET_POS) >= CLEARANCE - WALK_SLACK,
			"the walk passes the target no nearer than the route does (%.0f px, slack %.0f)"
				% [_closest(walked, TARGET_POS), WALK_SLACK],
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
