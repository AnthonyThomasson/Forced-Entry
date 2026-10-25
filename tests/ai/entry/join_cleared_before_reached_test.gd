extends GameTest
## LD25 and D26: a member whose join order ends follows again, also while it is still on its way to
## the stack. Three invaders, ranked as Main ranks a unit, are a squad bound as Main binds it: the
## lead and the sergeant in the back garden by the bare Terrace house's back door, the trooper far
## off west of the house. The lead claims a doorway of its own and rallies the others (a `join`
## order); the stack waits for the trooper (the joiner's ready wait) and then the lead and the
## sergeant go in and clear the room before the trooper has reached its slot. The trooper's join is
## over: it follows the lead at once, and never goes in.
##
## Real Von, the whole pipeline; no switch. Premise: the trooper walks slowly (`movement:speed` 60,
## as `entry_waits_for_stack`'s straggler), so the room is cleared before it reaches the stack; the
## test requires that it had not radioed ready (nor given its entry up) by the clear.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
## How long (s) the trooper has, from the clear, to follow.
const FOLLOW_WITHIN := 1.0


func describe() -> Dictionary:
	return {
		"name": "A joiner that never reached the stack follows once the room is cleared",
		"description": "The lead's stack rallies a slow trooper; the room is cleared before it "
			+ "reaches its slot, and it follows the lead at once instead of going in.",
		"tags": ["ai", "entry", "squad", "join", "follow", "leadership", "von"],
		"requires_von": true,
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"lead", &"invader", Vector2(960, 150))
	s.set_props(&"lead", "Wardrobe", { "rank": 2 })
	s.actor(&"sergeant", &"invader", Vector2(1000, 100))
	s.set_props(&"sergeant", "Wardrobe", { "rank": 1 })
	s.actor(&"trooper", &"invader", Vector2(-110, 300), { "movement:speed": 60.0 })
	s.set_props(&"trooper", "Wardrobe", { "rank": 0 })
	s.squads()


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	var lead := t.actor(&"lead")
	var trooper := t.actor(&"trooper")
	var nodes: Array = [lead, t.actor(&"sergeant"), trooper]
	var own := func(_rec: Dictionary) -> bool: return not Follow.own_claims(t, lead).is_empty()
	var w: Dictionary = await Follow.watch(t, nodes, squad, 40.0, { "stop": own })
	var claims := Follow.own_claims(t, lead)
	if not t.require(
			not claims.is_empty(),
			"premise: the lead made its own entry claim (acts %s)" % Follow.acts_of(w, lead),
	):
		return
	var opening := String(claims[0]["data"].get("opening", ""))
	var into := String(claims[0]["data"].get("into", ""))
	if not await _room_cleared(t, w, nodes, squad, into):
		return
	var clear_at := _clear_time(t, into)
	if not t.require(
			Follow.first_call(t, trooper, "ready", opening) == INF
				and Follow.first_call(t, trooper, "abort", opening) == INF,
			"premise: the trooper had not reached its slot (nor given up) by the clear (%s)"
				% str(Follow.entry(trooper).get("phase", "no entry")),
	):
		return

	_check_join(t, w, trooper, opening)
	await _follows_at_once(t, w, nodes, squad, clear_at)
	await t.seconds(3.0)
	t.check(
		Follow.first_call(t, trooper, "going_in", opening) == INF,
		"the trooper never went in by %s" % opening,
	)


## Waits (60 s at most) for the lead's stack to clear `into`. False when it never did.
func _room_cleared(
		t: TestContext,
		w: Dictionary,
		nodes: Array,
		squad: Node,
		into: String,
) -> bool:
	var cleared := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return not Follow.clears(t, into).is_empty()
	return t.require(
		await t.until(cleared, 60.0),
		"premise: the %s is cleared (acts %s / %s)"
			% [into, Follow.acts_of(w, nodes[0]), Follow.acts_of(w, nodes[1])],
	)


## The sim time of the first `clear` radioed for `into`.
func _clear_time(t: TestContext, into: String) -> float:
	return float(
		t.events.filter(func(e): return (
			e["topic"] == &"callout"
				and String(e["data"].get("entry_step", "")) == "clear"
				and String(e["data"].get("cleared_room", "")) == into
		))[0]["time"]
	)


## Checks the lead's claim gave the trooper a join order and it went to the stack by it.
func _check_join(t: TestContext, w: Dictionary, trooper: Node, opening: String) -> void:
	var joins := Follow.raw_joins(t)
	t.check(
		joins.any(func(e): return (e["data"].get("to", []) as Array).has(trooper)),
		"the lead's claim on %s gave the trooper a join order (joins %s)"
			% [opening, str(joins.map(func(e): return e["data"]))],
	)
	t.check(
		Follow.took(w, trooper, "order"),
		"the trooper was on its way to the stack by the order (acts %s)" % Follow.acts_of(
			w,
			trooper,
		),
	)


## Checks the trooper (the third of `nodes`) follows the lead within `FOLLOW_WITHIN` s of the clear.
func _follows_at_once(
		t: TestContext,
		w: Dictionary,
		nodes: Array,
		squad: Node,
		clear_at: float,
) -> void:
	var trooper: Node = nodes[2]
	var follows := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return Follow.following(trooper) and Follow.entry(trooper).is_empty()
	var followed := await t.until(follows, FOLLOW_WITHIN)
	t.check(
		followed,
		"the trooper follows the lead within %.1f s of the clear (%.2f s on; entry %s; acts %s)"
			% [
				FOLLOW_WITHIN,
				t.time - clear_at,
				str(Follow.entry(trooper).get("phase", "none")),
				Follow.acts_of(w, trooper),
			],
	)
