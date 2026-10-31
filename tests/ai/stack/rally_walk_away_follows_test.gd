extends GameTest
## D38 rule 5 with LD25: the human leader walking away frees its held rally to follow it, never to
## go in. A puppet human leader rallies its two NPC teammates at the bare Terrace house's back door
## (`rally_held_until_leader_crosses`' world); once both stand ready, held, the human walks off
## across the garden, past `reserve_range * leave_factor` (450 px) of walking: its stack radio
## withdraws its claim (`abort`), the squad cancels the joins, and both NPCs leave the stack and
## follow it. Neither crosses into the kitchen.
##
## Real Von, the whole pipeline; no switch.

const Rally := preload("res://tests/_ai/rally_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
## Where the human walks to: far across the back garden, past where its claim is kept.
const AWAY := Vector2(1450, 750)
## How long (s) the human has to get there.
const WALK_WITHIN := 15.0
## How long (s) the NPCs have, from the cancel, to follow the human.
const FOLLOW_WITHIN := 10.0


func describe() -> Dictionary:
	return {
		"name": "A human leader walking away from its held rally is followed",
		"description": "A puppet human leader rallies its two NPC teammates at the back door, "
			+ "held; it walks away across the garden: the squad cancels the joins and both "
			+ "follow it, neither going in.",
		"tags": ["ai", "stack", "squad", "join", "leadership", "human", "movement", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Rally.world(s)


func run(t: TestContext) -> void:
	var w := FollowWatch.new_watch()
	if not await Rally.rallied(t, w):
		return
	var members := Rally.members(t)
	var squad: Node = t.world.squad(&"invader")
	var nodes: Array = [t.actor(&"me")] + members
	var left_at := t.time
	var puppet := t.puppet(&"me")
	puppet.walk_to(AWAY)
	var cancelled := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return members.all(func(m): return _cancelled_since(t, m, left_at))
	t.check(
		await t.until(cancelled, WALK_WITHIN),
		"the squad cancelled both joins once the human walked away (cancels %s)"
			% str(Follow.raw_orders(t, Order.CANCEL).map(func(e): return e["data"])),
	)
	var following := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return members.all(func(m): return Follow.act(m).begins_with("follow"))
	t.check(
		await t.until(following, FOLLOW_WITHIN),
		"both NPCs follow the human (acts %s)"
			% str(members.map(func(m): return [m.name, FollowWatch.acts_of(w, m)])),
	)
	var door := String(Entry.BACK["id"])
	for m: Node in members:
		t.check(
			Follow.first_call(t, m, "going_in", door) == INF
				and not w["moves"].get(m, []).any(func(mv): return mv[2] == "kitchen"),
			"%s never went into the kitchen (moves %s)" % [m.name, str(w["moves"].get(m, []))],
		)


## Whether a `cancel` reached `m` at or after `since`.
func _cancelled_since(t: TestContext, m: Node, since: float) -> bool:
	return Follow.raw_orders(t, Order.CANCEL).any(func(e): return (
		float(e["time"]) >= since and (e["data"].get("to", []) as Array).has(m)
	))
