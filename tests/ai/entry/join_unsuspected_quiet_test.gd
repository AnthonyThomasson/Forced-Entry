extends GameTest
## LD24 and D10: a join stack is the member's own unordered entry joining the leader's, and `bang`
## is false by itself: into a room nobody suspects it goes in quietly. Three invaders, ranked as
## Main ranks a unit, are a squad bound as Main binds it, in the back garden east of the bare
## Terrace house. Nothing is heard. The lead goes in by the back door; its own claim rallies the
## team (a `join` order to both others), the sergeant carrying a stun: each joiner's state reads the
## join's order sentence (LD24), no claim says bang, no bang is radioed, no stun goes off, and all
## three go in. The contrast, the same rally into a suspect kitchen, is `join_suspect_room_bangs`.
##
## Scripted Von (one mechanism: the join stack's mode): whenever asked, SEARCH, ENTER, the back
## door (`Entry.rules`, its shared switches: no trespass hostility, no flyover). Armed the way Main
## arms a spawn, the lead with no grenade and the sergeant with one stun (the premise: the stun is
## the joiner's, so the stack carries one and only the room's suspicion is missing).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
## The join's order sentence (`docs/leadership.md` LD24), the back door's room filled in.
const JOIN_ORDER := "Your leader ordered you to go into the kitchen by its doorway with them."


func describe() -> Dictionary:
	return {
		"name": "A join stack into an unsuspected room goes in quietly",
		"description": "The lead's claim on the back door rallies the team; the sergeant brings a "
			+ "stun but nothing points at the kitchen, so the stack goes in quietly.",
		"tags": ["ai", "entry", "squad", "join", "quiet", "leadership", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK, [{ "pick": "search" }])
	s.actor(&"lead", &"invader", Vector2(960, 150))
	s.set_props(&"lead", "Wardrobe", { "rank": 2 })
	s.actor(&"sergeant", &"invader", Vector2(1000, 100))
	s.set_props(&"sergeant", "Wardrobe", { "rank": 1 })
	s.actor(&"trooper", &"invader", Vector2(1000, 250))
	s.set_props(&"trooper", "Wardrobe", { "rank": 0 })
	s.squads()


func run(t: TestContext) -> void:
	var lead := t.actor(&"lead")
	var members: Array = [t.actor(&"sergeant"), t.actor(&"trooper")]
	var nodes: Array = [lead] + members
	Probe.arm(lead, 0, 0)
	Probe.arm(members[0], 1, 0)
	Probe.arm(members[1], 0, 0)
	var squad: Node = t.world.squad(&"invader")
	if not t.require(
			Probe.count(members[0], Probe.STUN) == 1 and Probe.count(lead, Probe.STUN) == 0,
			"premise: only the sergeant carries a stun (Character.inventory.item_count(7))",
	):
		return
	var door := String(Entry.BACK["id"])
	var w := FollowWatch.new_watch()
	var read := await _wait_all_in(t, w, nodes, squad, door)
	if not t.require(
			Follow.own_claims(t, lead).any(
				func(e): return String(e["data"].get("opening", "")) == door,
			),
			"premise: the lead claimed the back door of its own (acts %s)" % FollowWatch.acts_of(
				w,
				lead,
			),
	):
		return

	_check_joined(t, w, members, door, read)
	_check_quiet(t, nodes, door)


## Watches (70 s at most) until all of `nodes` went in by `door`; returns every `order` section the
## members' (all but the lead, the first) decision snapshots held, by member.
func _wait_all_in(
		t: TestContext,
		w: Dictionary,
		nodes: Array,
		squad: Node,
		door: String,
) -> Dictionary:
	var members: Array = nodes.slice(1)
	var read := {}  # Member -> every `order` section its decision snapshots held.
	var in_all := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		for m in members:
			var b := Follow.brain_of(m)
			var said := String(b.debug_state().get("sections", {}).get("order", "")) if b else ""
			if said != "" and not (read.get(m, []) as Array).has(said):
				read[m] = (read.get(m, []) as Array) + [said]
		return nodes.all(func(c): return Follow.first_call(t, c, "going_in", door) < INF)
	await t.until(in_all, 70.0)
	return read


## Checks the lead's claim gave both `members` a join order on the back door, each read its order
## sentence, and they asked Von nothing.
func _check_joined(
		t: TestContext,
		w: Dictionary,
		members: Array,
		door: String,
		read: Dictionary,
) -> void:
	var joins := Follow.raw_joins(t)
	var to: Array = joins[0]["data"].get("to", []) if not joins.is_empty() else []
	t.check(
		not joins.is_empty()
			and String(joins[0]["data"].get("opening", "")) == door
			and members.all(func(m): return to.has(m)),
		"the lead's claim gave both others a join order on the back door (joins %s)"
			% str(joins.map(func(e): return e["data"])),
	)
	t.check(
		members.all(func(m): return (read.get(m, []) as Array).has(JOIN_ORDER)),
		"each joiner's state read the join's order sentence verbatim (read %s)"
			% str(members.map(func(m): return read.get(m, []))),
	)
	t.check(
		members.all(func(m): return FollowWatch.asked(w, m) == 0),
		"the members asked Von nothing: they joined by the order (asks %s)"
			% str(members.map(func(m): return FollowWatch.asked(w, m))),
	)


## Checks all of `nodes` went in quietly: no bang claimed or radioed, no stun off, and the sergeant
## (the second) still carries its stun.
func _check_quiet(t: TestContext, nodes: Array, door: String) -> void:
	var going: Array = nodes.map(func(c): return Follow.first_call(t, c, "going_in", door))
	if not t.check(
			going.all(func(g): return g < INF),
			"all three went in by the back door (going_in at %s)" % str(going),
	):
		return
	var first_in := float(going.min())
	var bangs := nodes.filter(func(c): return Follow.calls_of(t, c, "claim").any(
		func(e): return (
			String(e["data"].get("opening", "")) == door and e["data"].get("bang") == true
		),
	))
	t.check(
		bangs.is_empty(),
		"no claim on the back door said bang (%s)" % str(bangs.map(func(c): return c.name)),
	)
	var called: Array = nodes.filter(func(c): return Follow.first_call(t, c, "bang", door) < INF)
	t.check(
		called.is_empty(),
		"nobody radioed a bang (%s)" % str(called.map(func(c): return c.name)),
	)
	var booms := Probe.booms(t, &"stun")
	t.check(
		booms.is_empty(),
		"no stun went off (bursts %s; first going_in %.2f s)"
			% [str(booms.map(func(b): return b["data"]["position"])), first_in],
	)
	t.check(
		Probe.count(nodes[1], Probe.STUN) == 1,
		"the sergeant still carries its stun (%d)" % Probe.count(nodes[1], Probe.STUN),
	)
