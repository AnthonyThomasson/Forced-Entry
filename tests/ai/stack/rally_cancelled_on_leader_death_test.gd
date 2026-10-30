extends GameTest
## D31 with LD26: a human leader's held rally dies with it. A puppet human leader rallies its two
## NPC teammates at the bare Terrace house's back door (`rally_held_until_leader_crosses`' world);
## once both stand ready, held for its go, the human is killed (`take_damage`). An NPC leads within
## the frame and the squad cancels both joins (one `cancel`): a rally goes in only on its leader's
## go, which a dead leader never gives, so it posts no go of its own (D12 is a held order's, not a
## rally's) and neither NPC goes in on the join. The new leader's next claim of its own then rallies
## the other, which holds no order (D24: the cancel freed it).
##
## Real Von, the whole pipeline; no switch. Premise: nobody but the human is ever killed.

const Rally := preload("res://tests/_ai/rally_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
## How long (s) the squad has, from the death, to cancel both joins.
const CANCEL_WITHIN := 1.0
## How long (s) the new leader has to make a claim of its own that rallies the other.
const RALLY_WITHIN := 60.0


func describe() -> Dictionary:
	return {
		"name": "A human leader's held rally is cancelled on its death",
		"description": "A puppet human leader rallies its two NPC teammates at the back door, "
			+ "held; it is killed: the squad cancels both joins and posts no go, neither goes in "
			+ "on the join, and the new leader's own claim rallies the other.",
		"tags": ["ai", "stack", "squad", "join", "leadership", "human", "von"],
		"requires_von": true,
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Rally.world(s, { "max_health": 1_000_000.0 })


func run(t: TestContext) -> void:
	var w := FollowWatch.new_watch()
	if not await Rally.rallied(t, w):
		return
	var members := Rally.members(t)
	var squad: Node = t.world.squad(&"invader")
	var nodes: Array = [t.actor(&"me")] + members

	t.actor(&"me").take_damage(1.0e9)
	var died_at := t.time
	await t.frames(1)
	var leader: Node = squad.leader()
	if not t.require(
			members.has(leader),
			"premise: an NPC leads within the frame (leader %s)" % Follow.name_of(leader),
	):
		return
	var other: Node = members[1] if leader == members[0] else members[0]
	var cancelled := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return not _cancels_since(t, died_at, members).is_empty()
	t.check(
		await t.until(cancelled, CANCEL_WITHIN),
		"the squad cancelled both joins in one order (cancels %s)"
			% str(Follow.raw_orders(t, Order.CANCEL).map(func(e): return e["data"])),
	)

	var rallied := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return not _rallies(t, leader, other, died_at).is_empty()
	var did := await t.until(rallied, RALLY_WITHIN)
	_check_never_went_in(t, members, died_at)
	t.check(
		did,
		"the new leader's next claim of its own rallied the other NPC (acts %s; joins %s)"
			% [
				FollowWatch.acts_of(w, leader),
				str(Follow.raw_joins(t).map(func(e): return e["data"])),
			],
	)


## Checks the squad posted no go once the human was dead, at `died_at`, and none of `members` went
## in on the human's join.
func _check_never_went_in(t: TestContext, members: Array, died_at: float) -> void:
	t.check(
		Follow.raw_orders(t, Order.GO).all(func(e): return float(e["time"]) < died_at),
		"the squad posted no go once the human was dead (gos %s)"
			% str(Follow.raw_orders(t, Order.GO).map(func(e): return e["data"])),
	)
	for m: Node in members:
		t.check(
			_join_crossings(t, m).is_empty(),
			"%s never went in on the human's join (crossings %s)"
				% [m.name, str(_join_crossings(t, m))],
		)


## The `cancel` orders posted at or after `since` that name every one of `members`.
func _cancels_since(t: TestContext, since: float, members: Array) -> Array:
	return Follow.raw_orders(t, Order.CANCEL).filter(func(e): return (
		float(e["time"]) >= since and members.all(func(m): return e["data"]["to"].has(m))
	))


## The joins `leader` issued to `other` at or after `since`, oldest first.
func _rallies(t: TestContext, leader: Node, other: Node, since: float) -> Array:
	return Follow.raw_joins(t).filter(func(e): return (
		float(e["time"]) >= since
			and e["data"].get("leader") == leader
			and (e["data"].get("to", []) as Array).has(other)
	))


## `m`'s `going_in` / `in` callouts radioed as a join's that is not its new leader's: the human's
## (each `[time, step, opening]`). A join's claims carry no order id (D30), so the leader they came
## from is read off the order the member held when it crossed: any crossing on a join before the
## new leader rallied it is the human's.
func _join_crossings(t: TestContext, m: Node) -> Array:
	var rallied_at := INF
	for e: Dictionary in Follow.raw_joins(t):
		if e["data"].get("leader") != t.actor(&"me") and (e["data"]["to"] as Array).has(m):
			rallied_at = minf(rallied_at, float(e["time"]))
	return (Follow.calls_of(t, m).filter(func(e): return (
		bool(e["data"].get("join", false))
			and String(e["data"].get("entry_step", "")) in ["going_in", "in"]
			and float(e["time"]) < rallied_at
	)).map(func(e): return [
		snappedf(float(e["time"]), 0.1), e["data"]["entry_step"], e["data"].get("opening"),
	]))
