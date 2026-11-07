extends RefCounted
## Probe helper (not a test): walk a snapshot with the planner, as the decision tests do.

const DecisionPlanner := preload("res://scenes/ai/decision/decision_planner.gd")


## `snap` walked on a fresh planner with the NPC's own rules and scripted Von:
## `{ leaf, levels }` (the levels without their timings), or `{}` when it did not end.
static func walk(t: TestContext, brain: Node, snap: Dictionary) -> Dictionary:
	var own: Node = brain.get("_planner")
	var planner: Node = DecisionPlanner.new()
	t.world.add_child(planner)
	planner.entry_rules = own.entry_rules
	planner.disabled_nodes = own.disabled_nodes
	planner.setup(brain.tuning.decision)
	var leaf := {}
	planner.decided.connect(func(l: Dictionary) -> void: leaf.merge(l))
	planner.begin(snap, false)
	for i in 40:
		if not planner.is_pending():
			break
		await t.frames(1)
	var levels: Array = planner.debug_state()["levels"].duplicate(true)
	for level in levels:
		level.erase("ms")
	planner.queue_free()
	return {} if leaf.is_empty() else { "leaf": leaf, "levels": levels }
