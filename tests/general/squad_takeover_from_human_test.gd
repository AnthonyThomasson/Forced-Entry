extends GameTest
## LD26: taking over from a dead human leader. A puppet stands in for the human leader of an invader
## squad, built and bound the way Main builds it with "Lead the team" on (the human handed to
## `Squad.setup` as `human`, `MatchBuilder.bind_squad`), over the bare Terrace house. Its sergeant
## (rank 1) has no order and follows it. The human orders `defender` to defend the living room,
## `ambusher` to ambush the hall's doorway into the kitchen from the hall, and `stacker` to stack on
## the back door north of it, holding for its go. Once all three are in place the human is killed
## (`take_damage`). The sergeant leads within the frame (LD4); the squad posts one `cancel`, to the
## defender and the ambusher; the held stack is released (an `auto` go, D12), goes in and clears the
## kitchen; each member follows the sergeant once its order ends; and the sergeant's next claim of
## its own rallies them (a `join` order, the rally keyed on "the leader is not the human").
##
## Real Von, the whole pipeline; no switch. Premises: the defender and the ambusher start in the
## house, in the rooms their orders name (the orders are the human's, so their walks are not what is
## tested), and nobody but the human is ever killed.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
## The ambush click: in the hall, on the axis of its doorway into the kitchen (door_690_360).
const AMBUSH_AT := Vector2(690, 390)
## How long (s) the three have to be in place before the human dies.
const IN_PLACE_WITHIN := 40.0
## How long (s) after the death the team has to end its orders, follow and be rallied.
const TAKEOVER_WITHIN := 120.0


func describe() -> Dictionary:
	return {
		"name": "When the human leader dies the next takes over the team",
		"description": "A human leader orders a defend, an ambush and a held stack, then dies: "
			+ "the defend and the ambush are cancelled, the held stack goes, each member follows "
			+ "the new leader, and its next claim rallies them.",
		"tags": ["general", "ai", "squad", "leadership", "join", "follow", "human", "von"],
		"requires_von": true,
		"timeout": 200.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Stack.human(s, &"me", Vector2(980, 330), { "rank": 2 })
	s.actor(&"sergeant", &"invader", Vector2(1000, 400), { "rank": 1, "max_health": 1_000_000.0 })
	s.actor(&"defender", &"invader", Vector2(240, 150), { "rank": 0, "max_health": 1_000_000.0 })
	s.actor(&"ambusher", &"invader", Vector2(560, 415), { "rank": 0, "max_health": 1_000_000.0 })
	s.actor(&"stacker", &"invader", Vector2(960, 60), { "rank": 0, "max_health": 1_000_000.0 })


func run(t: TestContext) -> void:
	var ids := [&"me", &"sergeant", &"defender", &"ambusher", &"stacker"]
	var squad := Follow.team(t, ids, &"me")
	if not t.require(squad != null, "the squad is built and bound (Squad.setup, bind_squad)"):
		return
	var me := t.actor(&"me")
	var sergeant := t.actor(&"sergeant")
	var defender := t.actor(&"defender")
	var ambusher := t.actor(&"ambusher")
	var stacker := t.actor(&"stacker")
	var members: Array = [defender, ambusher, stacker]
	var nodes: Array = [sergeant] + members
	await t.seconds(0.3)
	var defend := Order.issue(
		squad,
		{ "kind": Order.DEFEND, "to": [defender], "room": "living_room" },
	)
	var ambush := Order.issue(squad, { "kind": Order.AMBUSH, "to": [ambusher], "pos": AMBUSH_AT })
	var held := Order.stack_order(squad, [stacker], Order.BACK_NORTH, "quiet", true)
	if not t.require(
			not defend.is_empty() and not ambush.is_empty() and not held.is_empty(),
			"premise: the human's three orders are posted (issue)",
	):
		return
	var door := String(Order.Entry.BACK["id"])
	var w := Follow.new_watch()
	var in_place := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return (
			not Order.progress(t, "in_position", defender).is_empty()
				and not Order.progress(t, "in_position", ambusher).is_empty()
				and Follow.first_call(t, stacker, "ready", door) < INF
		)
	if not t.require(
			await t.until(in_place, IN_PLACE_WITHIN),
			"premise: the defender and the ambusher hold their posts and the stack is ready",
	):
		return

	me.take_damage(1.0e9)
	if not t.require(me.is_dead, "the human is dead"):
		return
	var died_at := t.time
	await t.frames(1)
	t.check(
		squad.leader() == sergeant,
		"the sergeant leads within the frame (leader %s)" % Follow.name_of(squad.leader()),
	)
	var rallied := func() -> Array:
		return Follow.raw_joins(t).filter(func(e): return (
			float(e["time"]) > died_at and e["data"].get("leader") == sergeant
		))
	var done := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return members.all(func(m): return Follow.following(m)) and not rallied.call().is_empty()
	await t.until(done, TAKEOVER_WITHIN)

	var cancels := Follow.raw_orders(t, Order.CANCEL).filter(
		func(e): return float(e["time"]) >= died_at,
	)
	var to: Array = cancels[0]["data"].get("to", []) if cancels.size() == 1 else []
	t.check(
		cancels.size() == 1
			and to.has(defender)
			and to.has(ambusher)
			and not to.has(stacker)
			and not to.has(sergeant),
		"the squad posted one cancel, to the defender and the ambusher only (%s)"
			% str(cancels.map(
				func(e): return (e["data"].get("to", []) as Array).map(
					func(n): return Follow.name_of(n),
				),
			)),
	)
	t.check(
		Follow.raw_orders(t, Order.GO).any(func(e): return (
			float(e["time"]) >= died_at
				and e["data"].get("auto") == true
				and (e["data"].get("to", []) as Array).has(stacker)
		)),
		"the held stack was released (an auto go to the stacker, D12)",
	)
	t.check(
		Follow.first_call(t, stacker, "going_in", door) < INF
			and not Follow.clears(t, "kitchen").is_empty(),
		"the stacker finished the human's stack: went in and the kitchen was called clear",
	)
	if not t.require(
			members.all(func(m): return squad.follows(m)),
			"premise: both members follow the new leader (Squad.follows)",
	):
		return
	for m: Node in members:
		t.check(
			Follow.following(m),
			"%s follows the new leader once its order is over (acts %s)"
				% [m.name, Follow.acts_of(w, m)],
		)
	t.check(
		not Follow.following(sergeant),
		"the sergeant, now the leader, no longer follows (acts %s)" % Follow.acts_of(w, sergeant),
	)
	# D24: a rally's join goes only to the members holding no order at
	# that moment; one still on another order (here, the stacker on the human's released stack at
	# the same doorway, when the sergeant's first claim joins it) keeps it, and is in that stack.
	var joins: Array = rallied.call()
	var joined: Array = joins[0]["data"].get("to", []) if not joins.is_empty() else []
	var holding: Array = members.filter(
		func(m): return not joins.is_empty() and not _held_before(t, m, joins[0]).is_empty(),
	)
	var free: Array = members.filter(func(m): return not holding.has(m))
	t.check(
		not joins.is_empty()
			and free.all(func(m): return joined.has(m))
			and holding.all(func(m): return not joined.has(m)),
		"the sergeant's first claim of its own rallied every member holding no order (%s) and "
			% str(free.map(func(n): return Follow.name_of(n)))
			+ "nobody holding one (joins %s; own claims %s)"
			% [
				str(joins.map(func(e): return e["data"])),
				str(Follow.own_claims(t, sergeant).map(
					func(e): return [snappedf(float(e["time"]), 0.1), e["data"].get("opening")],
				)),
			],
	)
	if not joins.is_empty():
		var opening := String(joins[0]["data"].get("opening", ""))
		t.check(
			holding.all(func(m): return (
				String(_held_before(t, m, joins[0]).get("kind", "")) == Order.STACK
					and String(_held_before(t, m, joins[0]).get("opening", "")) == opening
			)),
			"each member left out of it is in that same stack, on the human's stack order at %s "
				% opening
				+ "(%s)" % str(holding.map(func(n): return Follow.name_of(n))),
		)


## The order `m` held just before the event `until` (a raw `&"order"` event), by the radio: the
## latest order naming it posted before then (a `go` replaces nothing), unless a `cancel` naming it
## or a `done` it radioed about that order ended it since; {} for none.
static func _held_before(t: TestContext, m: Node, until: Dictionary) -> Dictionary:
	var held := {}
	for e: Dictionary in t.events:
		if e == until:
			break
		var d: Dictionary = e["data"]
		if e["topic"] == &"order" and (d.get("to", []) as Array).has(m):
			if String(d.get("kind", "")) == Order.CANCEL:
				held = {}
			elif String(d.get("kind", "")) != Order.GO:
				held = d
		elif (e["topic"] == &"callout"
				and d.get("speaker") == m
				and String(d.get("order_step", "")) == "done"
				and str(d.get("order_id", "")) == str(held.get("id", "-"))):
			held = {}
	return held
