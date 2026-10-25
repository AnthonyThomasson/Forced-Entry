extends GameTest
## LD19 to LD21: members follow their leader. Three invaders are a squad, bound the way Main binds
## one (`s.squads`, `MatchBuilder.build_squads`); the first, ranked the unit's lead, leads. The
## leader decides through Von as ever and searches the Terrace house from the back garden, walking
## into the rooms (it makes no tactical entry of its own); the two others pick no goal of their own:
## they follow it (the root leaf FOLLOW, taken without asking Von) in a file on its trail, through
## each doorway after it, and stay within a band of it (`Follow.band_p50`). While no hostile is
## known the followers put no question to Von at all (counted per NPC from each one's decision
## walks).
##
## Real Von, the whole pipeline: nothing is scripted; the one prop set is the leader's
## `entry_enabled` (below). The house is the furnished Terrace house and nobody is in it, so no
## hostile is ever known.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const IDS := [&"lead", &"m1", &"m2"]
## How long (s) the search is watched at most: the leader is through two doorways well within it.
const WATCH_S := 110.0
## How long (s) after the start the band is measured from (the members walk up to the leader first).
const SETTLE_S := 5.0


func describe() -> Dictionary:
	return {
		"name": "Members follow their leader through the house",
		"description": "Three invaders bound to a squad: while the leader searches the house its "
			+ "members stay within a band of it, follow it through two doorways and ask Von "
			+ "nothing while no hostile is known.",
		"tags": ["ai", "movement", "squad", "follow", "leadership", "von"],
		"requires_von": true,
		"timeout": 160.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	# Ranked as Main ranks a unit: the lead, the sergeant, a trooper (the leader by the rank rule).
	s.actor(&"lead", &"invader", Vector2(930, 40), { "rank": 2 })
	# Premise: the leader searches by walking into the rooms, with no tactical entry of its own
	# (`entry_enabled` off: no ENTER, no stack claim), so this is LD21's file behind a leader that
	# walks through doorways. A leader's own stack rallying its team (LD24) is the join
	# tests' (`tests/ai/entry/join_*`).
	s.set_props(&"lead", "GoalController", { "entry_enabled": false })
	s.actor(&"m1", &"invader", Vector2(975, 75), { "rank": 1 })
	s.actor(&"m2", &"invader", Vector2(985, 125), { "rank": 0 })
	s.squads()


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	var lead := t.actor(&"lead")
	var members: Array = [t.actor(&"m1"), t.actor(&"m2")]
	if not t.require(squad.leader() == lead, "the lead leads (premise: the rank rule)"):
		return
	if not t.require(
			members.all(func(m): return squad.follows(m)),
			"premise: both members follow (Squad.follows: alive, not the leader)",
	):
		return
	var nodes: Array = [lead] + members
	var done := func(rec: Dictionary) -> bool:
		var moves: Array = rec["moves"].get(lead, [])
		return moves.size() >= 2 and t.time > float(moves[1][0]) + 15.0
	var w: Dictionary = await Follow.watch(t, nodes, squad, WATCH_S, { "stop": done })

	if not t.require(
			Follow.took(w, lead, "search"),
			"the leader searched the house through Von (acts %s)" % Follow.acts_of(w, lead),
	):
		return
	var lead_moves: Array = w["moves"].get(lead, [])
	if not t.require(
			lead_moves.size() >= 2,
			"the leader went through two doorways (moves %s; acts %s)"
				% [str(lead_moves), Follow.acts_of(w, lead)],
	):
		return
	for i in members.size():
		var m: Node = members[i]
		t.check(
			Follow.took(w, m, "follow"),
			"%s carried out FOLLOW (acts %s)" % [m.name, Follow.acts_of(w, m)],
		)
		var gaps := Follow.gaps(w, m, SETTLE_S)
		var p50 := Follow.percentile(gaps, 0.5)
		var p90 := Follow.percentile(gaps, 0.9)
		t.trace("%s gap p50" % m.name, p50)
		t.check(
			p50 <= Follow.band_p50(i) and p90 <= Follow.BAND_P90,
			"%s stays within a band of the leader (p50 %.0f px, most %.0f; p90 %.0f, most %.0f)"
				% [m.name, p50, Follow.band_p50(i), p90, Follow.BAND_P90],
		)
		for k in 2:
			t.check(
				Follow.went_through(w, m, lead_moves[k]),
				"%s went through the leader's doorway %d (%s -> %s at %.1f s) with it (moves %s)"
					% [
						m.name,
						k + 1,
						lead_moves[k][1],
						lead_moves[k][2],
						lead_moves[k][0],
						str(w["moves"].get(m, [])),
					],
			)
		t.expect_eq(
			Follow.asked(w, m),
			0,
			"%s asked Von nothing while no hostile was known (acts %s)"
				% [m.name, Follow.acts_of(w, m)],
		)
	t.check(Follow.asked(w, lead) > 0, "the leader decided through Von as ever")
