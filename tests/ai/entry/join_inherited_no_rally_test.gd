extends GameTest
## LD24 and D30: a join's claims are never its holder's own. A puppet stands in for the human leader
## of a squad of two invader NPCs, built and bound the way Main builds it with "Lead the team" on
## (`s.squads` with the human, `MatchBuilder.build_squads`: its `PlayerStack` attached by
## `MatchBuilder.bind_player` and handed the squad by `MatchBuilder.bind_squad`), over
## the bare Terrace house. The human orders the trooper, outside the front door, to defend the
## living room, then walks up beside the back door: its own claim rallies the sergeant, far off in
## the garden north-west of the house (a `join`). Once the sergeant has claimed its slot there, and
## while it is still on its way, the human is killed (`take_damage`): the sergeant leads within the
## frame, holding the join, and the squad cancels the trooper's defend (LD26), so the trooper holds
## no order and follows it. The sergeant's claims at the back door are its join's, not its own: they
## rally nobody, though a member holding no order is there to rally. Once the join is over (the
## kitchen cleared, `done`), the sergeant's next claim of its own at a doorway rallies the trooper.
##
## Real Von, the whole pipeline; no switch. Premises: the sergeant starts far from the back door, so
## it is still radioing its claim when it takes over; nobody but the human is ever killed.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
## Where the human stands: against the wall north of the back door, a stack spot beside it.
const STEP_UP := Order.BACK_NORTH
## How long (s) the sergeant has, once the human has claimed, to claim its slot at the back door.
const CLAIM_WITHIN := 6.0
## How long (s) the sergeant's claims at the back door are watched once it leads: its claim's
## repeats (every 2 s), while it is still on its way.
const WATCH_CLAIMS := 5.0
## How long (s) the sergeant has, once it leads, to end the join and make a claim of its own.
const OWN_CLAIM_WITHIN := 150.0


func describe() -> Dictionary:
	return {
		"name": "A follower that takes over holding a join does not rally on it",
		"description": "The human leader rallies the sergeant to the back door and dies while the "
			+ "sergeant is on its way: the sergeant leads holding the join, and its claims there "
			+ "rally nobody; its next claim of its own, once the join is over, rallies the "
			+ "trooper.",
		"tags": ["ai", "entry", "squad", "join", "leadership", "human", "von"],
		"requires_von": true,
		"timeout": 220.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Stack.human(s, &"me", Vector2(930, 40), { "movement:aim_point": STEP_UP })
	s.set_props(&"me", "Wardrobe", { "rank": 2 })
	s.actor(&"sergeant", &"invader", Vector2(100, -120), { "max_health": 1_000_000.0 })
	s.set_props(&"sergeant", "Wardrobe", { "rank": 1 })
	# The trooper stands outside the front door, so its way to the living room is its own (front
	# door, hall) and never the back door the human rallies at.
	s.actor(
		&"trooper",
		&"invader",
		Maps.DOOR_FRONT + Vector2(-90, 0),
		{ "max_health": 1_000_000.0 },
	)
	s.set_props(&"trooper", "Wardrobe", { "rank": 0 })
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var me := t.actor(&"me")
	var sergeant := t.actor(&"sergeant")
	var trooper := t.actor(&"trooper")
	var squad := t.squad(&"invader")
	if not _human_leads(t, me, squad, trooper):
		return
	var nodes: Array = [me, sergeant, trooper]
	var w := Follow.new_watch()
	var join := await _rally_sergeant(t, w, nodes, squad)
	if join.is_empty():
		return

	me.take_damage(1.0e9)
	var died_at := t.time
	await t.frames(1)
	if not _sergeant_takes_over(t, squad, sergeant, trooper, died_at):
		return
	if not await _join_claims_rally_nobody(t, w, nodes, died_at):
		return

	await _own_claim_rallies(t, w, nodes, join)


## The premises: the human has a stack radio, leads, and has ordered the trooper to defend the
## living room. False when one does not hold.
func _human_leads(t: TestContext, me: Node, squad: Node, trooper: Node) -> bool:
	var stack := t.player_stack()
	if not t.require(stack != null, "the human has a stack radio (MatchBuilder.bind_player)"):
		return false
	if not t.require(squad.leader() == me, "premise: the human leads (Lead the team)"):
		return false
	var defend := Order.issue(
		squad,
		{ "kind": Order.DEFEND, "to": [trooper], "room": "living_room" },
	)
	return t.require(
		String(defend.get("kind", "")) == Order.DEFEND,
		"premise: the human ordered the trooper to defend the living room (%s)" % str(defend),
	)


## The human walks up beside the back door; its claim rallies the sergeant (the second of
## `nodes`) alone, which claims its slot there. Returns the join order's data, empty when a premise
## does not hold.
func _rally_sergeant(t: TestContext, w: Dictionary, nodes: Array, squad: Node) -> Dictionary:
	var sergeant: Node = nodes[1]
	var puppet := t.puppet(&"me")
	puppet.walk_to(STEP_UP)
	var door := String(Entry.BACK["id"])
	var joined := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return Follow.first_call(t, sergeant, "claim", door) < INF
	if not t.require(
			await t.until(joined, 8.0 + CLAIM_WITHIN),
			"premise: the human's own claim at the back door rallied the sergeant, which claimed "
				+ "its slot there (joins %s)"
				% str(Follow.raw_joins(t).map(func(e): return e["data"])),
	):
		return {}
	var join: Dictionary = Follow.raw_joins(t)[0]["data"]
	if not t.require(
			(join.get("to", []) as Array) == [sergeant],
			"premise: the join went to the sergeant alone (the trooper holds its defend, D24)",
	):
		return {}
	return join


## The premises once the human is dead: the sergeant leads within the frame, and the squad
## cancelled the trooper's defend. False when one does not hold.
func _sergeant_takes_over(
		t: TestContext,
		squad: Node,
		sergeant: Node,
		trooper: Node,
		died_at: float,
) -> bool:
	if not t.require(
			squad.leader() == sergeant,
			"premise: the sergeant leads within the frame (leader %s)"
				% Follow.name_of(squad.leader()),
	):
		return false
	return t.require(
		Follow.raw_orders(t, Order.CANCEL).any(func(e): return (
			float(e["time"]) >= died_at and (e["data"].get("to", []) as Array).has(trooper)
		)),
		"premise: the squad cancelled the trooper's defend (LD26): it holds no order",
	)


## Watches the sergeant (the second of `nodes`), leading, radio its join's claim at the back door
## again, and checks those claims rallied nobody. False when it radioed none.
func _join_claims_rally_nobody(t: TestContext, w: Dictionary, nodes: Array, died_at: float) -> bool:
	var squad := t.squad(&"invader")
	var sergeant: Node = nodes[1]
	var door := String(Entry.BACK["id"])
	var watch_claims := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return false
	await t.until(watch_claims, WATCH_CLAIMS)
	var claims_led: Array = Follow.calls_of(t, sergeant, "claim").filter(func(e): return (
		float(e["time"]) > died_at and String(e["data"].get("opening", "")) == door
	))
	if not t.require(
			not claims_led.is_empty(),
			"premise: the sergeant, leading, radioed its join's claim at the back door again "
				+ "(steps %s)"
				% str(Follow.calls_of(t, sergeant).map(func(e): return [
					snappedf(float(e["time"]), 0.1), e["data"].get("entry_step"),
				])),
	):
		return false
	t.check(
		_led_joins(t, sergeant).is_empty(),
		"the sergeant's join claims at the back door rallied nobody (joins %s)"
			% str(_led_joins(t, sergeant).map(func(e): return e["data"])),
	)
	return true


## Once the join is over, checks the sergeant's next claim of its own rallied the trooper (the
## second and third of `nodes`).
func _own_claim_rallies(t: TestContext, w: Dictionary, nodes: Array, join: Dictionary) -> void:
	var squad := t.squad(&"invader")
	var sergeant: Node = nodes[1]
	var trooper: Node = nodes[2]
	var join_done := func() -> float:
		for e: Dictionary in t.events:
			if (e["topic"] == &"callout"
					and e["data"].get("speaker") == sergeant
					and String(e["data"].get("order_step", "")) == "done"
					and str(e["data"].get("order_id", "")) == str(join.get("id", ""))):
				return float(e["time"])
		return INF
	var own_after := func() -> Array:
		var since: float = join_done.call()
		return Follow.own_claims(t, sergeant).filter(func(e): return float(e["time"]) > since)
	var rallied := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return not own_after.call().is_empty() and not _led_joins(t, sergeant).is_empty()
	await t.until(rallied, OWN_CLAIM_WITHIN)
	if not t.require(
			join_done.call() < INF and not own_after.call().is_empty(),
			"premise: the sergeant's join ended done and it then made a claim of its own (acts %s)"
				% Follow.acts_of(w, sergeant),
	):
		return
	var opening := String(own_after.call()[0]["data"].get("opening", ""))
	var joins: Array = _led_joins(t, sergeant).filter(
		func(e): return String(e["data"].get("opening", "")) == opening,
	)
	t.check(
		not joins.is_empty() and (joins[0]["data"].get("to", []) as Array).has(trooper),
		"the sergeant's next claim of its own, at %s, rallied the trooper (joins %s)"
			% [opening, str(_led_joins(t, sergeant).map(func(e): return e["data"]))],
	)


## The join orders the sergeant has issued as leader.
func _led_joins(t: TestContext, sergeant: Node) -> Array:
	return Follow.raw_joins(t).filter(func(e): return e["data"].get("leader") == sergeant)
