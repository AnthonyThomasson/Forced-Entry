extends GameTest
## LD24 and D10: a join stack is the member's own unordered entry joining the leader's, so E17's
## suspicion upgrade runs in it (`docs/tactical-entry.md`). Three invaders, ranked as Main ranks a
## unit, are a squad bound as Main binds it, in the back garden east of the bare Terrace house.
## Gunfire is heard in the kitchen first thing (the kitchen is suspect). The lead, which carries no
## stun, goes in by the back door; its own claim rallies the team (a `join` order to both others),
## and the sergeant carries a stun into the stack: the stack turns bang, radios it, and a stun goes
## off in the kitchen before anyone goes in. The contrast, the same rally into an unsuspected
## kitchen, is `join_unsuspected_quiet`.
##
## Scripted Von (one mechanism: the join stack's mode): whenever asked, SEARCH, ENTER, the back
## door (`Entry.rules`, its shared switches: no trespass hostility, no flyover). Armed the way Main
## arms a spawn, the lead with no grenade and the sergeant with one stun (the premise: the stun is
## the joiner's). The gunfire is a `hit` event nobody known fired, in the kitchen (as
## `tests/_ai/investigate_probe.gd` posts it), more than an awareness radius from the team.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
const Investigate := preload("res://tests/_ai/investigate_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A join stack into a suspect room goes in with a bang",
		"description": "The lead's claim on the back door rallies the team; the sergeant brings a "
			+ "stun and the kitchen is suspect, so the stack bangs before it goes in.",
		"tags": ["ai", "entry", "squad", "join", "grenade", "stun", "leadership", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK, [{ "pick": "search" }])
	s.actor(&"lead", &"invader", Vector2(960, 150), { "rank": 2 })
	s.actor(&"sergeant", &"invader", Vector2(1000, 100), { "rank": 1 })
	s.actor(&"trooper", &"invader", Vector2(1000, 250), { "rank": 0 })


func run(t: TestContext) -> void:
	var lead := t.actor(&"lead")
	var members: Array = [t.actor(&"sergeant"), t.actor(&"trooper")]
	var nodes: Array = [lead] + members
	Probe.arm(lead, 0, 0)
	Probe.arm(members[0], 1, 0)
	Probe.arm(members[1], 0, 0)
	var squad := Follow.team(t, [&"lead", &"sergeant", &"trooper"])
	if not t.require(squad != null, "the squad is built and bound (Squad.setup, bind_squad)"):
		return
	if not t.require(
			Probe.count(members[0], Probe.STUN) == 1 and Probe.count(lead, Probe.STUN) == 0,
			"premise: only the sergeant carries a stun (Character.item_count(7))",
	):
		return
	Investigate.gunfire(Maps.KITCHEN_CENTRE)
	var door := String(Entry.BACK["id"])
	var w := Follow.new_watch()
	var in_all := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return nodes.all(func(c): return Follow.first_call(t, c, "going_in", door) < INF)
	await t.until(in_all, 70.0)
	if not t.require(
			Follow.own_claims(t, lead).any(
				func(e): return String(e["data"].get("opening", "")) == door,
			),
			"premise: the lead claimed the back door of its own (acts %s)" % Follow.acts_of(
				w,
				lead,
			),
	):
		return

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
		members.all(func(m): return Follow.asked(w, m) == 0),
		"the members asked Von nothing: they joined by the order (asks %s)"
			% str(members.map(func(m): return Follow.asked(w, m))),
	)
	var going: Array = nodes.map(func(c): return Follow.first_call(t, c, "going_in", door))
	if not t.check(
			going.all(func(g): return g < INF),
			"all three went in by the back door (going_in at %s)" % str(going),
	):
		return
	var first_in := float(going.min())
	var bang_claims := nodes.any(func(c): return Follow.calls_of(t, c, "claim").any(
		func(e): return (
			String(e["data"].get("opening", "")) == door
				and e["data"].get("bang") == true
				and float(e["time"]) < first_in
		),
	))
	t.check(bang_claims, "the stack's claims turned bang before anyone went in")
	var called: Array = nodes.map(func(c): return Follow.first_call(t, c, "bang", door))
	t.check(
		float(called.min()) < first_in,
		"the stack radioed the bang before it went in (bang at %s, first going_in %.2f s)"
			% [str(called), first_in],
	)
	var booms := Probe.booms(t, &"stun")
	t.check(
		not booms.is_empty()
			and Maps.HOUSE_KITCHEN.has_point(booms[0]["data"]["position"])
			and float(booms[0]["time"]) <= first_in,
		"a stun went off in the kitchen before anyone went in (bursts %s, first going_in %.2f s)"
			% [
				str(booms.map(
					func(b): return [snappedf(float(b["time"]), 0.01), b["data"]["position"]],
				)),
				first_in,
			],
	)
