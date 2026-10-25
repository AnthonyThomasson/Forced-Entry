extends GameTest
## LD4 (`docs/leadership.md`): succession. When the leader dies, the next in line by the same rule
## (LD3: rank, then spawn order) leads within the frame, the squad posts `&"leader"`
## `{ faction, leader, previous }`, and the orders already given stand; a later order (from the new
## leader) replaces them.
##
## The match is built the way Main builds one (`s.declared_match`, populated through `MatchBuilder`
## on the bare Terrace house: its three invaders at their start points, ranked as a match ranks its
## unit, lead, sergeant, trooper, and given their squad). The leader is killed with `take_damage`.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const INVADERS := [Vector2(1000, 60), Vector2(1000, 330), Vector2(1100, 190)]


func describe() -> Dictionary:
	return {
		"name": "The next in line leads when the leader dies; orders stand",
		"description": "In a Main-built match the lead invader is killed: the sergeant leads "
			+ "within a frame, a leader event is posted, the trooper keeps the order it was "
			+ "given, and a newer order replaces it (LD4).",
		"tags": ["ai", "leadership", "squad", "match"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	# Scripted Von (the first option offered): the members' own decisions are not under test.
	Maps.house(s, false)
	s.von_script([])
	s.declared_match({ "defenders": { "count": 0 }, "invaders": { "at": INVADERS } })


func run(t: TestContext) -> void:
	var built := t.match_handle()
	var npcs: Array = built.get("combatants", [])
	if not t.require(npcs.size() == 3, "the match has its three invaders"):
		return
	t.expect_eq(
		npcs.map(func(n): return int(n.rank)),
		[2, 1, 0],
		"premise: ranked as a match ranks its unit (lead, sergeant, trooper)",
	)
	var squad := t.squad(&"invader")
	if not t.require(
			squad != null
				and npcs.all(func(n): return TestContext.controller_of(n).get("squad") == squad),
			"the match hands each NPC its squad (MatchBuilder.bind_squad)",
	):
		return
	if not t.require(squad.leader() == npcs[0], "the lead leads before it dies (premise)"):
		return
	await t.seconds(0.5)
	if not await _give_order(t, squad, npcs[2]):
		return
	if not await _check_succession(t, squad, npcs):
		return
	await _check_orders_stand(t, squad, npcs)


## The squad posts a defend order to the `trooper` and it takes it; false when either fails (the
## test ended).
func _give_order(t: TestContext, squad: Node, trooper: Node) -> bool:
	var given := Order.issue(squad, { "kind": Order.DEFEND, "to": [trooper], "room": "kitchen" })
	if not t.require(not given.is_empty(), "the squad posts the order (issue)"):
		return false
	var brain := TestContext.controller_of(trooper, &"current_act")
	return t.require(
			await t.until(func(): return Order.on_order(brain), 3.0),
			"the trooper takes the order (act %s)" % brain.current_act(),
	)


## The lead (the first of `npcs`) is killed: the sergeant (the second) leads within a frame, one
## leader event names both, and the squad's view names the new leader. False when the lead did not
## die (the test ended).
func _check_succession(t: TestContext, squad: Node, npcs: Array) -> bool:
	var lead: Node = npcs[0]
	var sergeant: Node = npcs[1]
	lead.take_damage(1.0e9)
	if not t.require(lead.is_dead, "the lead is dead"):
		return false
	await t.frames(1)
	t.check(
		squad.leader() == sergeant,
		"the sergeant leads within a frame (leader %s)" % _name(squad.leader()),
	)
	var calls := t.events_of(&"leader", func(d): return d.get("faction") == &"invader")
	t.check(calls.size() == 1, "one leader event is posted (%d)" % calls.size())
	if not calls.is_empty():
		t.check(
			calls[0].get("leader") == sergeant and calls[0].get("previous") == lead,
			"it names the new leader and the previous one (%s after %s)"
				% [_name(calls[0].get("leader")), _name(calls[0].get("previous"))],
		)
	t.check(Order.view(squad).get("leader") == sergeant, "the squad's view names the new leader")
	return true


## The trooper (the third of `npcs`) keeps its order through the succession, and a later order,
## from the new leader (the second), replaces it.
func _check_orders_stand(t: TestContext, squad: Node, npcs: Array) -> void:
	var sergeant: Node = npcs[1]
	var trooper: Node = npcs[2]
	var brain := TestContext.controller_of(trooper, &"current_act")
	await t.seconds(2.0)
	var kept: Dictionary = Order.member_view(squad, trooper).get("order", {})
	t.check(
		String(kept.get("kind", "")) == Order.DEFEND and String(kept.get("room", "")) == "kitchen",
		"the trooper's order stands in the squad's view (%s)" % str(kept),
	)
	t.check(
		Order.on_order(brain),
		"and the trooper is still carrying it out (act %s)" % brain.current_act(),
	)

	var newer := Order.issue(
		squad,
		{ "kind": Order.DEFEND, "to": [trooper], "room": "living_room" },
	)
	t.check(
		newer.get("leader") == sergeant,
		"a later order is given by the new leader (%s)" % _name(newer.get("leader")),
	)
	await t.seconds(1.0)
	var now: Dictionary = Order.member_view(squad, trooper).get("order", {})
	t.check(
		String(now.get("room", "")) == "living_room",
		"the later order replaces the standing one (%s)" % str(now),
	)
	# The order's own params (`debug_state()["order"]`): the trooper's walk into the house is
	# guarded (LD8), so the running params may be those of an entry detour on its way.
	var running: Dictionary = brain.debug_state().get("order", {}).get("params", {})
	t.check(
		String(running.get("room", "")) == "living_room",
		"in the trooper's running order too (params %s)" % str(running),
	)


## A node's name for a message, or the value as text.
func _name(n: Variant) -> String:
	return String(n.name) if n is Node and is_instance_valid(n) else str(n)
