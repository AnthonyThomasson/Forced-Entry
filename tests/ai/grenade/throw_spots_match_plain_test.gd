extends GameTest
## The throw-spot search lobs each snapped candidate at most once, whether its first try qualified
## or not, without changing the spots or their order from the undeduplicated search.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Plain := preload("res://tests/_ai/throw_spot_plain_probe.gd")
const AgentTactics := preload("res://scenes/ai/perception/agent_tactics.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")


func describe() -> Dictionary:
	return {
		"name": "Throw spots match the undeduplicated plain search",
		"description": "A snapped candidate is lob-tested once even after a failed first try, and "
			+ "the qualifying spots and their order are unchanged.",
		"tags": ["ai", "grenade"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	s.actor(&"npc", &"puppet", Maps.HALL_MIDDLE)


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	await t.frames(2)
	var tactics := AgentTactics.new()
	tactics.vision = AgentVision.new()
	tactics.cover_min = 40.0
	tactics.throw_spot_walk = 250.0
	var ctx := {
		"space": npc.get_world_2d().direct_space_state,
		"map": npc.get_world_2d().navigation_map,
		"self_pos": npc.global_position,
		"hostiles": [],
	}
	var aim := ThrowAim.new()
	aim.spot = npc.global_position + Vector2(48.0, 0.0)
	# The NPC's 240 ring and the aim's 0.8 × 240 ring share the point 240 px to its right.
	aim.reach = 240.0
	var failed := _repeated_point(tactics, ctx, aim)
	if not t.require(failed != Vector2.INF, "a snapped candidate occurs more than once"):
		return
	var calls: Array = []
	aim.lob = func(p: Vector2) -> bool:
		calls.append(p)
		return p != failed
	var fast: Array = tactics._throw_found(ctx, aim, [])
	var failed_calls := calls.count(failed)
	aim.lob = func(p: Vector2) -> bool: return p != failed
	var plain: Array = Plain.found(tactics, ctx, aim, [])
	t.check(fast == plain, "the same spots, annotations and order as the plain search")
	t.check(
		failed_calls == 1,
		"the duplicate whose first lob fails is tried once (%d)" % failed_calls,
	)


## The first cheap-test-passing point produced by two raw candidates, or INF when there is none.
func _repeated_point(tactics: RefCounted, ctx: Dictionary, aim: ThrowAim) -> Vector2:
	var seen := {}
	for r: Vector2 in tactics._throw_raw(ctx["self_pos"], aim):
		var p: Vector2 = tactics._throw_point(ctx, r, aim)
		if p == Vector2.INF:
			continue
		if seen.has(p):
			return p
		seen[p] = true
	return Vector2.INF
