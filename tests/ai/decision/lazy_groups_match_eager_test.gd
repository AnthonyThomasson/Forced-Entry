extends GameTest
## The snapshot builds the option groups `leads`, `entries`, `search_rooms`, `explore`,
## `interactions` and `rooms` (and the facts `leads` and `lead_outside` that need the first) only
## when the planner's walk first reads them (#192 rule 23). Over a fight, an investigation, a
## tactical entry and an order, the walk over a snapshot built on demand takes the path an eager
## build gives, offering the same options worded the same, and builds only the groups it read; the
## full-set reader (`demand.complete()`: the debug overlay, the spectator card, a test) gets every
## group, equal to the eager one.
##
## The eager reference is the same snapshot completed before the walk begins. The expected sets of
## groups built come from the decision tree: a fight reads none of the six, an investigation reads
## the leads, the entry (SEARCH's doorways) reads the entries and what they exclude.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const DecisionPlanner := preload("res://scenes/ai/decision/decision_planner.gd")
## Where the invader stands: the back garden, outside the kitchen's back door.
const NPC := Vector2(900, 190)
## Where the trespasser waits until the fight (inside, out of the NPC's sight).
const FOE_AWAY := Vector2(260, 190)
## The groups built on demand.
const LAZY := ["leads", "entries", "search_rooms", "explore", "interactions", "rooms"]


func describe() -> Dictionary:
	return {
		"name": "Option groups built on demand match an eager build",
		"description": "Over a fight, an investigation, an entry and an order, the walk's path, "
			+ "its options and their text equal an eager build's; the groups it did not read "
			+ "were not built; the full-set reader gets all of them.",
		"tags": ["ai", "decision", "snapshot", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"npc", &"invader", NPC, { "movement:speed": 0.0, "facing": Vector2.LEFT })
	s.actor(&"boss", &"puppet", Vector2(1000, 330), { "faction": &"invader" })
	s.actor(&"foe", &"puppet", FOE_AWAY, { "faction": &"household", "max_health": 1_000_000.0 })


func run(t: TestContext) -> void:
	await t.frames(3)
	var brain := t.controller(&"npc", &"debug_state")
	var perception: Node = brain.get("_perception")
	await _entry(t, brain, perception)
	await _investigation(t, brain, perception)
	await _order(t, brain, perception)
	await _fight(t, brain, perception)


## Nothing known: SEARCH's doorways are read (and the groups the entries leave out of the others).
func _entry(t: TestContext, brain: Node, perception: Node) -> void:
	var out := await _compare(t, brain, perception, "entry", [{ "pick": "search" }])
	if out.is_empty():
		return
	var built: Array = out["built"]
	t.check(built.has("entries"), "the entry walk read the doorways to enter by (%s)" % str(built))
	t.check(
		not built.has("interactions") and not built.has("rooms"),
		"IDLE is off for a pursuer, so its groups were not built (%s)" % str(built),
	)


## Gunfire heard from inside the house: INVESTIGATE needs the leads.
func _investigation(t: TestContext, brain: Node, perception: Node) -> void:
	EventBus.post(
		&"hit",
		{
			"position": Maps.KITCHEN_CENTRE, "direction": Vector2.LEFT, "damage": 10.0,
			"attacker": null, "victim": null,
		},
	)
	await t.frames(3)
	var out := await _compare(t, brain, perception, "investigation", [{ "pick": "investigate" }])
	if out.is_empty():
		return
	var built: Array = out["built"]
	t.check(built.has("leads"), "the investigation read the leads (%s)" % str(built))
	t.check(
		not built.has("interactions") and not built.has("rooms"),
		"the investigation did not build IDLE's groups (%s)" % str(built),
	)


## An order is taken at the ORDER node, whose one group is built with every snapshot.
func _order(t: TestContext, brain: Node, perception: Node) -> void:
	Order.post({
		"id": "order_kitchen", "leader": t.actor(&"boss"), "faction": &"invader",
		"to": [t.actor(&"npc")], "kind": Order.DEFEND, "room": "kitchen",
	})
	await t.frames(3)
	var out := await _compare(t, brain, perception, "order", [])
	if out.is_empty():
		return
	var built: Array = out["built"]
	t.check(built.is_empty(), "an order walk built none of the six groups (%s)" % str(built))
	t.check(
		String(out["path"][0]) == "order",
		"the walk took the ORDER node (path %s)" % str(out["path"]),
	)
	Order.post({ "id": "order_kitchen", "leader": t.actor(&"boss"), "faction": &"invader",
		"to": [t.actor(&"npc")], "kind": Order.CANCEL })
	await t.frames(3)


## A trespasser in plain sight: the walk is COMBAT's, which reads none of the six.
func _fight(t: TestContext, brain: Node, perception: Node) -> void:
	var npc := t.actor(&"npc")
	npc.facing = Vector2.RIGHT
	t.actor(&"foe").global_position = npc.global_position + Vector2.RIGHT * 60.0
	var seen := func() -> bool: return (brain.debug_state().get("contacts", []) as Array).any(
		func(c): return c.get("hostile", false)
	)
	if not t.require(await t.until(seen, 3.0), "set-up: the invader sees the trespasser"):
		return
	var out := await _compare(
		t, brain, perception, "fight", [{ "pick": "combat" }, { "pick": "engage" }]
	)
	if out.is_empty():
		return
	var built: Array = out["built"]
	t.check(built.is_empty(), "a fight walk built none of the six groups (%s)" % str(built))
	t.check(
		String(out["path"][0]) == "combat",
		"the walk took COMBAT (path %s)" % str(out["path"]),
	)


## Walks one snapshot built on demand and one completed before its walk: the paths, options and
## state texts must be equal; the full set of the first equals the second's. `{}` when a premise
## failed, else `{ built, path }` of the on-demand walk.
func _compare(
		t: TestContext, brain: Node, perception: Node, label: String, rules: Array,
) -> Dictionary:
	var goal: String = brain.get("goal")
	DecisionStub.rules = rules
	var lazy_snap: Dictionary = perception.sense(goal, "", 0)
	var eager_snap: Dictionary = perception.sense(goal, "", 0)
	var lazy_demand = lazy_snap.get("demand")
	if not t.require(
			lazy_demand != null and eager_snap.get("demand") != null,
			"%s: a snapshot carries the demand that builds its groups" % label,
		):
		return {}
	t.require(
		(lazy_demand.built as Array).is_empty(),
		"%s: nothing is built on demand before the walk reads it" % label,
	)
	eager_snap["demand"].complete()
	var eager := await _walk(t, brain, eager_snap)
	var lazy := await _walk(t, brain, lazy_snap)
	if not t.require(not eager.is_empty() and not lazy.is_empty(), "%s: both walks end" % label):
		return {}
	var built: Array = (lazy_demand.built as Array).duplicate()
	t.expect_eq(lazy["leaf"], eager["leaf"], "%s: the leaf the walk ends at" % label)
	t.expect_eq(lazy["levels"], eager["levels"], "%s: every level's options and text" % label)
	lazy_demand.complete()
	for name in LAZY:
		t.check(
			(lazy_snap["options"] as Dictionary).has(name),
			"%s: the full set holds %s" % [label, name],
		)
	t.check(
		lazy_snap["facts"].has("leads") and lazy_snap["facts"].has("lead_outside"),
		"%s: the full set holds the lead facts" % label,
	)
	t.expect_eq(lazy_snap["options"], eager_snap["options"], "%s: the full option set" % label)
	t.expect_eq(lazy_snap["facts"], eager_snap["facts"], "%s: the full facts" % label)
	t.expect_eq(lazy_snap["sections"], eager_snap["sections"], "%s: the full sections" % label)
	return { "built": built, "path": lazy["leaf"].get("path", []) }


## `snap` walked on a fresh planner with the NPC's own rules and scripted Von:
## `{ leaf, levels }` (the levels without their timings), or `{}` when it did not end.
func _walk(t: TestContext, brain: Node, snap: Dictionary) -> Dictionary:
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
