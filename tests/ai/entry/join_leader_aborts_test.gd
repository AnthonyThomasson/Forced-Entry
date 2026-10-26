extends GameTest
## LD25 and D25: the leader gives its stack up, and the squad cancels the joins. Three invaders,
## ranked as Main ranks a unit, are a squad bound as Main binds it: the lead in the back garden by
## the bare Terrace house's back door, the sergeant and the trooper far off in the garden north-west
## of the house. The lead decides through Von and claims a doorway of its own: the squad rallies the
## others (a `join` order). Then the lead comes under fire (a hit on it): its forced decision
## replaces the entry and it radios `abort`. The squad cancels those join orders, and the sergeant
## and the trooper stop their entries and follow the lead again.
##
## Real Von, the whole pipeline; no switch. Premises: the hit (a `hit` event on the lead, nobody
## known firing, as `tests/_ai/order_probe.gd`'s `gunfire_near` posts one) lands while the others
## are still far from the doorway, more than an awareness radius off, so only the lead is under
## fire; the lead is never killed (`max_health`).

const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
## How long (s) after the lead's claim the hit lands: the join order is out and taken.
const HIT_AFTER := 1.0
## How long (s) the members have, from the cancel, to drop their entries and follow.
const FOLLOW_WITHIN := 3.0


func describe() -> Dictionary:
	return {
		"name": "When the leader aborts its stack the joins are cancelled",
		"description": "The lead's claim rallies its team; the lead comes under fire and gives its "
			+ "stack up: the squad cancels the join orders and the members follow it again.",
		"tags": ["ai", "entry", "squad", "join", "leadership", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"lead", &"invader", Vector2(960, 150), { "max_health": 1_000_000.0 })
	s.set_props(&"lead", "Wardrobe", { "rank": 2 })
	s.actor(&"sergeant", &"invader", Vector2(100, -120))
	s.set_props(&"sergeant", "Wardrobe", { "rank": 1 })
	s.actor(&"trooper", &"invader", Vector2(40, -80))
	s.set_props(&"trooper", "Wardrobe", { "rank": 0 })
	s.squads()


func run(t: TestContext) -> void:
	var squad: Node = t.world.squad(&"invader")
	var lead := t.actor(&"lead")
	var members: Array = [t.actor(&"sergeant"), t.actor(&"trooper")]
	var nodes: Array = [lead] + members
	var own := func(_rec: Dictionary) -> bool: return not Follow.own_claims(t, lead).is_empty()
	var w: Dictionary = await FollowWatch.watch(t, nodes, squad, 40.0, { "stop": own })
	var claims := Follow.own_claims(t, lead)
	if not t.require(
			not claims.is_empty(),
			"premise: the lead made its own entry claim (acts %s)" % FollowWatch.acts_of(w, lead),
	):
		return
	var opening := String(claims[0]["data"].get("opening", ""))
	if not await _others_still_far(t, w, nodes, squad):
		return
	_hit(lead)
	if not await _lead_aborts(t, w, nodes, opening):
		return
	var abort_at := Follow.first_call(t, lead, "abort", opening)

	_check_rallied(t, opening)
	await _settle(t, w, nodes, abort_at)
	for m: Node in members:
		_check_member(t, w, m, opening, abort_at)


## Watches `HIT_AFTER` s more, then requires the others (all of `nodes` but the lead, the first)
## still far from the lead. False when they are not.
func _others_still_far(t: TestContext, w: Dictionary, nodes: Array, squad: Node) -> bool:
	var lead: Node = nodes[0]
	var keep := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return false
	await t.until(keep, HIT_AFTER)
	var far: Array = nodes.slice(1).map(
		func(m): return m.global_position.distance_to(lead.global_position),
	)
	return t.require(
		far.all(func(d): return d > 200.0),
		"premise: the others are still far from the lead when it is hit (%s px)"
			% str(far.map(func(d): return roundi(d))),
	)


## A hit on the lead, by nobody known.
func _hit(lead: Node) -> void:
	EventBus.post(
		&"hit",
		{
			"position": lead.global_position,
			"direction": Vector2.LEFT,
			"damage": 10.0,
			"attacker": null,
			"victim": lead,
		},
	)


## Waits (5 s at most) for the lead (the first of `nodes`) to give its stack on `opening` up.
## False when it never did.
func _lead_aborts(t: TestContext, w: Dictionary, nodes: Array, opening: String) -> bool:
	var lead: Node = nodes[0]
	var squad: Node = t.world.squad(&"invader")
	var aborted := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return Follow.first_call(t, lead, "abort", opening) < INF
	return t.require(
		await t.until(aborted, 5.0),
		"premise: under fire, the lead gives its stack on %s up (abort; acts %s)"
			% [opening, FollowWatch.acts_of(w, lead)],
	)


## Checks the lead's claim on `opening` rallied the team.
func _check_rallied(t: TestContext, opening: String) -> void:
	var joins := Follow.raw_joins(t)
	t.check(
		not joins.is_empty() and String(joins[0]["data"].get("opening", "")) == opening,
		"the lead's claim on %s rallied the team (joins %s)"
			% [opening, str(joins.map(func(e): return e["data"]))],
	)


## Watches until every member (all of `nodes` but the lead) has its join cancelled, has dropped its
## entry and follows (`FOLLOW_WITHIN` s and 1 more at most).
func _settle(t: TestContext, w: Dictionary, nodes: Array, abort_at: float) -> void:
	var squad: Node = t.world.squad(&"invader")
	var members: Array = nodes.slice(1)
	var settled := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return members.all(func(m): return (
			_cancel_at(t, m, abort_at) < INF and Follow.entry(m).is_empty() and Follow.following(m)
		))
	await t.until(settled, FOLLOW_WITHIN + 1.0)


## Checks the squad cancelled `m`'s join order, and it dropped its entry, follows and never went in.
func _check_member(
	t: TestContext,
	w: Dictionary,
	m: Node,
	opening: String,
	abort_at: float,
) -> void:
	var at: float = _cancel_at(t, m, abort_at)
	t.check(
		at < INF,
		"the squad cancelled %s's join order after the abort at %.2f s" % [m.name, abort_at],
	)
	t.check(
		Follow.entry(m).is_empty() and Follow.following(m),
		"%s dropped its entry and follows the lead again (entry %s; acts %s)"
			% [m.name, str(Follow.entry(m).get("phase", "none")), FollowWatch.acts_of(w, m)],
	)
	t.check(
		Follow.first_call(t, m, "going_in", opening) == INF,
		"%s never went in by %s" % [m.name, opening],
	)


## The time the squad cancelled `m`'s order at or after `abort_at` (`INF`: never).
func _cancel_at(t: TestContext, m: Node, abort_at: float) -> float:
	for e: Dictionary in Follow.raw_orders(t, Follow.Order.CANCEL):
		if float(e["time"]) >= abort_at and (e["data"].get("to", []) as Array).has(m):
			return float(e["time"])
	return INF
