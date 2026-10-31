extends GameTest
## LD24 and D30: a join's claims are never its holder's own. Three invader NPCs, ranked as Main
## ranks a unit, are a squad bound as Main binds it (`s.squads`), over the bare Terrace house: the
## lead in the back garden by the back door, the sergeant far off in the garden north-west of the
## house, the trooper outside the front door, ordered to defend the living room. The lead decides
## through Von and claims a doorway of its own: its claim rallies the sergeant (a `join`; the
## trooper holds its defend, D24). Once the sergeant has claimed its slot there, and while it is
## still on its way, the lead is killed (`take_damage`): the sergeant leads within the frame,
## holding the join (an AI leader's rally holds for no go, so its joins stand, D38), and the
## trooper's defend is cancelled, so it holds no order and follows it. The sergeant's claims at that
## doorway are its join's, not its own: they rally nobody, though a member holding no order is there
## to rally. Once the join is over (the room cleared, `done`), the sergeant's next claim of its own
## at a doorway rallies the trooper.
##
## Real Von, the whole pipeline; no switch. Premises: the sergeant starts far from the house, so it
## is still radioing its claim when it takes over; the trooper's defend is issued, and later
## cancelled, through the squad (`Squad.issue`), standing in for the orders a leader gives (an NPC
## leader gives none of its own); nobody but the lead is ever killed. The lead is an NPC: a human
## leader's rally is cancelled on its death (D38, `rally_cancelled_on_leader_death`), so a join is
## inherited only from an AI leader's rally.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
## How long (s) the lead has to claim a doorway of its own.
const LEAD_CLAIM_WITHIN := 40.0
## How long (s) the sergeant has, once the lead has claimed, to claim its slot at that doorway.
const CLAIM_WITHIN := 6.0
## How long (s) the sergeant's claims at that doorway are watched once it leads: its claim's
## repeats (every 2 s), while it is still on its way.
const WATCH_CLAIMS := 5.0
## How long (s) the sergeant has, once it leads, to end the join and make a claim of its own.
const OWN_CLAIM_WITHIN := 150.0


func describe() -> Dictionary:
	return {
		"name": "A follower that takes over holding a join does not rally on it",
		"description": "The lead rallies the sergeant to a doorway and dies while the sergeant is "
			+ "on its way: the sergeant leads holding the join, and its claims there rally "
			+ "nobody; its next claim of its own, once the join is over, rallies the trooper.",
		"tags": ["ai", "entry", "squad", "join", "leadership", "von"],
		"requires_von": true,
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"lead", &"invader", Vector2(960, 150))
	s.set_props(&"lead", "Wardrobe", { "rank": 2 })
	s.actor(&"sergeant", &"invader", Vector2(100, -120), { "max_health": 1_000_000.0 })
	s.set_props(&"sergeant", "Wardrobe", { "rank": 1 })
	# The trooper stands outside the front door, so its way to the living room is its own (front
	# door, hall) and never the back garden's.
	s.actor(
		&"trooper",
		&"invader",
		Maps.DOOR_FRONT + Vector2(-90, 0),
		{ "max_health": 1_000_000.0 },
	)
	s.set_props(&"trooper", "Wardrobe", { "rank": 0 })
	s.squads()


func run(t: TestContext) -> void:
	var lead := t.actor(&"lead")
	var sergeant := t.actor(&"sergeant")
	var trooper := t.actor(&"trooper")
	var squad: Node = t.world.squad(&"invader")
	if not _lead_leads(t, lead, squad, trooper):
		return
	var nodes: Array = [lead, sergeant, trooper]
	var w := FollowWatch.new_watch()
	var join := await _rally_sergeant(t, w, nodes, squad)
	if join.is_empty():
		return

	lead.take_damage(1.0e9)
	var died_at := t.time
	await t.frames(1)
	if not _sergeant_takes_over(t, squad, sergeant, trooper):
		return
	var door := String(join["opening"])
	if not await _join_claims_rally_nobody(t, w, nodes, died_at, door):
		return

	await _own_claim_rallies(t, w, nodes, join)


## The premises: the lead leads, and the trooper holds a defend of the living room. False when one
## does not hold.
func _lead_leads(t: TestContext, lead: Node, squad: Node, trooper: Node) -> bool:
	if not t.require(squad.leader() == lead, "premise: the lead leads (the highest rank)"):
		return false
	var defend := Order.issue(
		squad,
		{ "kind": Order.DEFEND, "to": [trooper], "room": "living_room" },
	)
	return t.require(
		String(defend.get("kind", "")) == Order.DEFEND,
		"premise: the trooper holds a defend of the living room (%s)" % str(defend),
	)


## The lead claims a doorway of its own (through Von); its claim rallies the sergeant (the second of
## `nodes`) alone, which claims its slot there. Returns the join order's data, empty when a premise
## does not hold.
func _rally_sergeant(t: TestContext, w: Dictionary, nodes: Array, squad: Node) -> Dictionary:
	var lead: Node = nodes[0]
	var sergeant: Node = nodes[1]
	var claimed := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return not Follow.own_claims(t, lead).is_empty()
	if not t.require(
			await t.until(claimed, LEAD_CLAIM_WITHIN),
			"premise: the lead made its own entry claim (acts %s)" % FollowWatch.acts_of(w, lead),
	):
		return {}
	var door := String(Follow.own_claims(t, lead)[0]["data"].get("opening", ""))
	var joined := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return Follow.first_call(t, sergeant, "claim", door) < INF
	if not t.require(
			await t.until(joined, CLAIM_WITHIN),
			"premise: the lead's own claim at %s rallied the sergeant, which claimed " % door
				+ "its slot there (joins %s)" % _joins_data(Follow.raw_joins(t)),
	):
		return {}
	var join: Dictionary = Follow.raw_joins(t)[0]["data"]
	if not t.require(
			(join.get("to", []) as Array) == [sergeant] and String(join["opening"]) == door,
			"premise: the join went to the sergeant alone (the trooper holds its defend, D24)",
	):
		return {}
	return join


## The premises once the lead is dead: the sergeant leads within the frame, and the trooper's defend
## is cancelled through the squad, so it holds no order. False when one does not hold.
func _sergeant_takes_over(t: TestContext, squad: Node, sergeant: Node, trooper: Node) -> bool:
	if not t.require(
			squad.leader() == sergeant,
			"premise: the sergeant leads within the frame (leader %s)"
				% Follow.name_of(squad.leader()),
	):
		return false
	var cancel := Order.issue(squad, { "kind": Order.CANCEL, "to": [trooper] })
	return t.require(
		String(cancel.get("kind", "")) == Order.CANCEL,
		"premise: the trooper's defend is cancelled: it holds no order (%s)" % str(cancel),
	)


## Watches the sergeant (the second of `nodes`), leading, radio its join's claim at `door` again,
## and checks those claims rallied nobody. False when it radioed none.
func _join_claims_rally_nobody(
		t: TestContext,
		w: Dictionary,
		nodes: Array,
		died_at: float,
		door: String,
) -> bool:
	var squad: Node = t.world.squad(&"invader")
	var sergeant: Node = nodes[1]
	var watch_claims := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return false
	await t.until(watch_claims, WATCH_CLAIMS)
	var claims_led: Array = Follow.calls_of(t, sergeant, "claim").filter(func(e): return (
		float(e["time"]) > died_at and String(e["data"].get("opening", "")) == door
	))
	if not t.require(
			not claims_led.is_empty(),
			"premise: the sergeant, leading, radioed its join's claim at %s again " % door
				+ "(steps %s)" % _steps(t, sergeant),
	):
		return false
	t.check(
		_led_joins(t, sergeant).is_empty(),
		"the sergeant's join claims at %s rallied nobody (joins %s)"
			% [door, _joins_data(_led_joins(t, sergeant))],
	)
	return true


## Once the join is over, checks the sergeant's next claim of its own rallied the trooper (the
## second and third of `nodes`).
func _own_claim_rallies(t: TestContext, w: Dictionary, nodes: Array, join: Dictionary) -> void:
	var squad: Node = t.world.squad(&"invader")
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
		FollowWatch.tick(w, t, nodes, squad)
		return not own_after.call().is_empty() and not _led_joins(t, sergeant).is_empty()
	await t.until(rallied, OWN_CLAIM_WITHIN)
	if not t.require(
			join_done.call() < INF and not own_after.call().is_empty(),
			"premise: the sergeant's join ended done and it then made a claim of its own (acts %s)"
				% FollowWatch.acts_of(w, sergeant),
	):
		return
	var opening := String(own_after.call()[0]["data"].get("opening", ""))
	var joins: Array = _led_joins(t, sergeant).filter(
		func(e): return String(e["data"].get("opening", "")) == opening,
	)
	t.check(
		not joins.is_empty() and (joins[0]["data"].get("to", []) as Array).has(trooper),
		"the sergeant's next claim of its own, at %s, rallied the trooper (joins %s)"
			% [opening, _joins_data(_led_joins(t, sergeant))],
	)


## The join orders the sergeant has issued as leader.
func _led_joins(t: TestContext, sergeant: Node) -> Array:
	return Follow.raw_joins(t).filter(func(e): return e["data"].get("leader") == sergeant)


## `who`'s entry steps radioed, each `[time, step]`, for a failure message.
func _steps(t: TestContext, who: Node) -> String:
	return str(Follow.calls_of(t, who).map(func(e): return [
		snappedf(float(e["time"]), 0.1), e["data"].get("entry_step"),
	]))


## The data of the order events `joins`, for a failure message.
func _joins_data(joins: Array) -> String:
	return str(joins.map(func(e): return e["data"]))
