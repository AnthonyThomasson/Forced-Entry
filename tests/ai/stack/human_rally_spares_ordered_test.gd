extends GameTest
## LD24 and D24: a rally's `join` goes only to the members holding no order. A puppet stands in for
## the human leader of a squad of three invader NPCs, built and bound the way Main builds it with
## "Lead the team" on (the human handed to `Squad.setup` as `human`, its `PlayerStack` attached as
## `MatchBuilder.bind_player` attaches it and handed the squad by `MatchBuilder.bind_squad`). The
## human orders the teammate standing by the front door to defend the living room, as the command
## menu asks it (`Squad.issue`), then walks up beside the bare Terrace house's back door, where
## nobody is stacking: its stack radio claims a slot of its own and the squad rallies the team
## there. The two free teammates in the back garden get the `join` and stack with the human; the
## defender is left out of it and keeps its defend order.
##
## Real Von, the whole pipeline; no switch. The human (a puppet) is never killed.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
## Where the human stands: against the wall north of the back door, a stack spot beside it.
const STEP_UP := Order.BACK_NORTH
## The room the defender is ordered to hold: across the house from the back door, reached from
## where it stands by the front door and the hall.
const DEFEND_ROOM := "living_room"
## How long (s) the free teammates have, once the human has claimed, to stand ready in the stack.
const READY_WITHIN := 20.0


func describe() -> Dictionary:
	return {
		"name": "A human leader's rally spares a teammate holding an order",
		"description": "A puppet human leader orders one teammate to defend the living room, then "
			+ "walks up beside the back door: the two free teammates get the join and stack with "
			+ "it, and the defender keeps its defend order.",
		"tags": ["ai", "stack", "squad", "join", "leadership", "human", "order", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Stack.human(s, &"me", Vector2(930, 40), { "aim_point": STEP_UP })
	s.actor(&"m1", &"invader", Vector2(980, 0))
	s.actor(&"m2", &"invader", Vector2(990, 80))
	# The defender stands outside the front door, so its way to the living room is its own (front
	# door, hall) and never the back door the human rallies at.
	s.actor(&"d", &"invader", Maps.DOOR_FRONT + Vector2(-90, 0))
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var me := t.actor(&"me")
	var free: Array = [t.actor(&"m1"), t.actor(&"m2")]
	var defender := t.actor(&"d")
	var squad := t.squad(&"invader")
	if not _has_stack(t, squad, me):
		return
	var defend := _order_defend(t, squad, defender)
	if defend.is_empty():
		return
	var nodes: Array = [me, defender] + free
	var w := Follow.new_watch()
	if not await _step_up(t, w, nodes, squad):
		return
	var door := String(Entry.BACK["id"])
	if not await _own_claim(t, w, nodes, squad, door):
		return
	var ready := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return free.all(func(m): return Follow.first_call(t, m, "ready", door) < INF)
	await t.until(ready, READY_WITHIN)

	_check_joins(t, w, defender, free, door)
	_check_order_kept(t, squad, defender, defend, door)
	for m: Node in free:
		t.check(
			Follow.first_call(t, m, "claim", door) < INF
				and Follow.first_call(t, m, "ready", door) < INF,
			"%s stacked with the human: claimed the back door and stood ready (claim %.2f s, "
				% [m.name, Follow.first_call(t, m, "claim", door)]
				+ "ready %.2f s)" % Follow.first_call(t, m, "ready", door),
		)


func _has_stack(t: TestContext, squad: Node, me: Node) -> bool:
	var stack := t.player_stack()
	if not t.require(stack != null, "the human has a stack radio (MatchBuilder.bind_player)"):
		return false
	return t.require(
		stack.get("squad") == squad and squad.leader() == me,
		"premise: the human's stack is handed its squad, and the human leads (Lead the team)",
	)


func _order_defend(t: TestContext, squad: Node, defender: Node) -> Dictionary:
	var defend := Order.issue(
		squad,
		{ "kind": Order.DEFEND, "to": [defender], "room": DEFEND_ROOM },
	)
	if not t.require(
			String(defend.get("kind", "")) == Order.DEFEND
				and String(defend.get("room", "")) == DEFEND_ROOM,
			"premise: the human ordered the defender to defend the living room (%s)" % str(defend),
	):
		return {}
	return defend


func _step_up(t: TestContext, w: Dictionary, nodes: Array, squad: Node) -> bool:
	var puppet := t.puppet(&"me")
	puppet.walk_to(STEP_UP)
	var arrived := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return puppet.has_arrived()
	if not t.require(await t.until(arrived, 8.0), "the human walked up beside the back door"):
		return false
	puppet.stop()
	return true


func _own_claim(t: TestContext, w: Dictionary, nodes: Array, squad: Node, door: String) -> bool:
	var me: Node = nodes[0]
	var claimed := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return Follow.first_call(t, me, "claim", door) < INF
	return t.require(
		await t.until(claimed, 4.0),
		"premise: the human claimed a slot on the back door of its own (its rally)",
	)


func _check_joins(t: TestContext, w: Dictionary, defender: Node, free: Array, door: String) -> void:
	t.check(
		Follow.took(w, defender, "order"),
		"premise: the defender carried out its defend order (ORDER; acts %s)"
			% Follow.acts_of(w, defender),
	)
	var joins := Follow.raw_joins(t).filter(
		func(e): return String(e["data"].get("opening", "")) == door,
	)
	var to: Array = joins[0]["data"].get("to", []) if not joins.is_empty() else []
	t.check(
		not joins.is_empty() and free.all(func(m): return to.has(m)),
		"the squad gave both free teammates a join order on the back door (joins %s)"
			% str(joins.map(func(e): return e["data"])),
	)
	var all_joins := Follow.raw_joins(t)
	t.check(
		all_joins.all(func(e): return not (e["data"].get("to", []) as Array).has(defender)),
		"no join went to the defender, who holds an order (joins %s)"
			% str(all_joins.map(func(e): return e["data"])),
	)


func _check_order_kept(
		t: TestContext,
		squad: Node,
		defender: Node,
		defend: Dictionary,
		door: String,
) -> void:
	var held: Dictionary = Order.member_view(squad, defender).get("order", {})
	t.check(
		String(held.get("kind", "")) == Order.DEFEND
			and str(held.get("id", "")) == str(defend.get("id", "")),
		"the defender still holds its defend order (%s)" % str(held),
	)
	t.check(
		Follow.first_call(t, defender, "claim", door) == INF,
		"the defender took no slot in the back door's stack",
	)
