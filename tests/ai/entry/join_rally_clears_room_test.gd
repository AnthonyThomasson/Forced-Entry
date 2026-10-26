extends GameTest
## LD24 and LD25: an AI leader's stack brings its team in. Three invaders, ranked as Main ranks a
## unit (lead, sergeant, trooper), are a squad bound as Main binds it, in the back garden east of
## the bare Terrace house, the back door the nearest way in. The lead decides through Von and goes
## in: its own entry claim at a doorway (no order behind it) makes the squad issue one `stack` order
## with mode `join` to both others, on that doorway. All three cross as one stack and the room is
## cleared.
##
## Real Von, the whole pipeline; no switch. The premise is the leader's own claim: what doorway it
## picks is Von's, and the test reads it off the radio.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
## How long (s) the team has, from the lead's first claim, to be in and the room called clear.
const CLEAR_WITHIN := 60.0
## The most (s) between the first and the last of the three going in: one stack, not one at a time.
const ONE_STACK_S := 15.0


func describe() -> Dictionary:
	return {
		"name": "An AI leader's stack rallies its team and they clear the room",
		"description": "Three invaders in a squad: the lead's own claim at a doorway gives both "
			+ "others a join order there, all three cross as one stack and clear the room.",
		"tags": ["ai", "entry", "squad", "join", "leadership", "von"],
		"requires_von": true,
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"lead", &"invader", Vector2(960, 150))
	s.set_props(&"lead", "Wardrobe", { "rank": 2 })
	s.actor(&"sergeant", &"invader", Vector2(1000, 100))
	s.set_props(&"sergeant", "Wardrobe", { "rank": 1 })
	s.actor(&"trooper", &"invader", Vector2(1000, 250))
	s.set_props(&"trooper", "Wardrobe", { "rank": 0 })
	s.squads()


func run(t: TestContext) -> void:
	var squad: Node = t.world.squad(&"invader")
	var lead := t.actor(&"lead")
	var members: Array = [t.actor(&"sergeant"), t.actor(&"trooper")]
	var nodes: Array = [lead] + members
	if not t.require(squad.leader() == lead, "the lead leads (the rank rule)"):
		return
	var own_claim := func(_rec: Dictionary) -> bool:
		return not Follow.own_claims(t, lead).is_empty()
	var w: Dictionary = await Follow.watch(t, nodes, squad, 40.0, { "stop": own_claim })
	var claims := Follow.own_claims(t, lead)
	if not t.require(
			not claims.is_empty(),
			"premise: the lead made its own entry claim at a doorway (acts %s)"
				% Follow.acts_of(w, lead),
	):
		return
	var opening := String(claims[0]["data"].get("opening", ""))
	var into := String(claims[0]["data"].get("into", ""))
	var claimed_at := float(claims[0]["time"])
	await _wait_clear(t, w, nodes, opening, into)

	_check_join(t, nodes, opening, claimed_at)
	for m: Node in members:
		t.check(
			Follow.took(w, m, "order"),
			"%s carried out the join order (ORDER; acts %s)" % [m.name, Follow.acts_of(w, m)],
		)
	_check_one_stack(t, nodes, opening)
	t.check(
		not Follow.clears(t, into).is_empty(),
		"the %s was called clear (cleared_room) within %.0f s of the lead's claim"
			% [into, CLEAR_WITHIN],
	)


## Watches (`CLEAR_WITHIN` s at most) until `into` is called clear and all of `nodes` went in.
func _wait_clear(
	t: TestContext,
	w: Dictionary,
	nodes: Array,
	opening: String,
	into: String,
) -> void:
	var squad: Node = t.world.squad(&"invader")
	var cleared := func(rec: Dictionary) -> bool:
		Follow.tick(rec, t, nodes, squad)
		return not Follow.clears(t, into).is_empty() and nodes.all(
			func(c): return Follow.first_call(t, c, "going_in", opening) < INF,
		)
	await t.until(cleared.bind(w), CLEAR_WITHIN)


## Checks the squad issued one join order, to both others (all of `nodes` but the lead, the first),
## on the lead's doorway after its claim.
func _check_join(t: TestContext, nodes: Array, opening: String, claimed_at: float) -> void:
	var lead: Node = nodes[0]
	var members: Array = nodes.slice(1)
	var joins := Follow.raw_joins(t)
	t.check(
		joins.size() == 1,
		"the squad issued one join order (%d: %s)"
			% [joins.size(), str(joins.map(func(e): return e["data"]))],
	)
	if not joins.is_empty():
		var order: Dictionary = joins[0]["data"]
		var to: Array = order.get("to", [])
		t.check(
			members.all(func(m): return to.has(m)) and not to.has(lead),
			"the join order went to both others, not the lead (to %s)"
				% str(to.map(func(n): return Follow.name_of(n))),
		)
		t.check(
			String(order.get("opening", "")) == opening and float(joins[0]["time"]) >= claimed_at,
			"on the lead's doorway %s, after its claim at %.2f s (order on %s at %.2f s)"
				% [opening, claimed_at, order.get("opening", ""), float(joins[0]["time"])],
		)


## Checks all of `nodes` went in by `opening`, as one stack.
func _check_one_stack(t: TestContext, nodes: Array, opening: String) -> void:
	var going: Array = nodes.map(func(c): return Follow.first_call(t, c, "going_in", opening))
	t.check(
		going.all(func(g): return g < INF),
		"all three went in by %s (going_in at %s)" % [opening, str(going)],
	)
	if going.all(func(g): return g < INF):
		t.check(
			float(going.max()) - float(going.min()) <= ONE_STACK_S,
			"as one stack: the first and the last went in %.1f s apart (most %.0f)"
				% [float(going.max()) - float(going.min()), ONE_STACK_S],
		)
