extends GameTest
## LD19 and LD21: a human leader gets the same rule. A puppet stands in for the human leader of a
## squad of two invader NPCs, built and bound the way Main builds it with "Lead the team" on (the
## human handed to `Squad.setup` as `human`, `MatchSpawner.bind_squad`). The human walks a route
## along the back garden north of the Terrace house, west, and stops facing west. The NPCs follow
## it in a file on its trail while it walks (each spot `FOLLOW_GAP` + `FOLLOW_STEP` x its place
## behind the human, the walk re-aimed only once the spot has moved `FOLLOW_RETARGET`), and once it
## has stood `FOLLOW_STILL_TIME` they take spots on a ring round it (`FOLLOW_RING` 80 px), behind
## its facing, and face outward. Mid-walk the squad's `view()` (what the leader overlay draws,
## LD28) holds the trail, the leash and each member's own follow spot.
##
## Real Von, the whole pipeline; no switch. The house is the bare Terrace house, so there is a house
## to search: left to themselves the NPCs go in and search it.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
## The human's route: along the garden north of the house (its north wall is y 0), westward.
const ROUTE := [Vector2(700, -80), Vector2(400, -80), Vector2(150, -80)]
## Where the human looks once it stops: on west along the garden.
const LOOK := Vector2(-200, -80)
## How long (s) the followers have to take their ring spots once the human stands still.
const RING_WITHIN := 6.0
## How far (px) off the ring's radius a follower may stand (a snapped spot, a body's give).
const RING_SLACK := 35.0
## How far (px) a follower's spot may lie off its place in the file, at the median over the walk
## (the trail's `TRAIL_STEP` points, a snapped spot).
const FILE_SLACK := 15.0


func describe() -> Dictionary:
	return {
		"name": "Members follow a human leader and ring it when it stops",
		"description": "A puppet human leader walks a route along the garden: its two NPC "
			+ "teammates follow it in a file, and ring it behind its facing, facing out, once it "
			+ "stops.",
		"tags": ["ai", "movement", "squad", "follow", "leadership", "human", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Stack.human(s, &"me", Vector2(900, -80), { "aim_point": Vector2(700, -80) })
	s.actor(&"m1", &"invader", Vector2(960, -40))
	s.actor(&"m2", &"invader", Vector2(975, -120))


func run(t: TestContext) -> void:
	var squad := Follow.team(t, [&"me", &"m1", &"m2"], &"me")
	if not t.require(squad != null, "the squad is built and bound (Squad.setup, bind_squad)"):
		return
	var me := t.actor(&"me")
	if not t.require(squad.leader() == me, "the human leads (premise: Lead the team)"):
		return
	var members: Array = [t.actor(&"m1"), t.actor(&"m2")]
	if not t.require(
			members.all(func(m): return squad.follows(m)),
			"premise: both NPCs follow the human (Squad.follows)",
	):
		return
	await t.seconds(1.5)
	var nodes: Array = [me] + members
	var w := Follow.new_watch()
	var puppet := t.puppet(&"me")
	# Per follower: how far its spot lies behind the human on the straight legs, and how far each
	# re-aim of its walk moved where it was going.
	var spacing := {}
	var reaims := {}
	var aimed := {}
	var viewed := {}  # `squad.view()` mid-walk, with each member's `follow_spot` beside it.
	for m: Node in members:
		spacing[m] = []
		reaims[m] = []
	for leg in ROUTE.size():
		var point: Vector2 = ROUTE[leg]
		puppet.aim_at(point)
		puppet.walk_to(point)
		while not puppet.has_arrived() and t.time < 60.0:
			Follow.tick(w, t, nodes, squad)
			if leg == 1 and viewed.is_empty():
				viewed = {
					"view": squad.view(),
					"spots": members.map(func(m): return squad.follow_spot(m)),
				}
			for m: Node in members:
				if leg > 0:
					spacing[m].append(squad.follow_spot(m).distance_to(me.global_position))
				var to := Follow.walk_target(m)
				if Follow.following(m) and to != Vector2.INF:
					if aimed.has(m) and to.distance_to(aimed[m]) > 0.0:
						reaims[m].append(to.distance_to(aimed[m]))
					aimed[m] = to
			await t.frames(1)
	puppet.stop()
	puppet.aim_at(LOOK)
	var stopped_at := t.time
	var walked := Follow.new_watch()
	walked["samples"] = w["samples"].duplicate()
	var ringed := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return members.all(func(m): return _on_ring(me, m))
	var rang := await t.until(ringed, Follow.FOLLOW_STILL_TIME + RING_WITHIN)
	await t.seconds(1.0)

	for m: Node in members:
		t.check(
			Follow.took(w, m, "follow"),
			"%s follows the human (FOLLOW; acts %s)" % [m.name, Follow.acts_of(w, m)],
		)
		var off: Vector2 = m.global_position - me.global_position
		var facing: Vector2 = (LOOK - me.global_position).normalized()
		t.check(
			_on_ring(me, m),
			"%s stands on the ring round the human (%.0f px off it, ring %.0f +- %.0f; %.1f s on)"
				% [m.name, off.length(), Follow.FOLLOW_RING, RING_SLACK, t.time - stopped_at],
		)
		t.check(
			off.dot(facing) < 0.0,
			"%s stands behind the human's facing (offset %s, facing %s)"
				% [m.name, str(off.round()), str(facing)],
		)
		t.check(
			(m.get("facing") as Vector2).dot(off.normalized()) > 0.5,
			"%s faces outward from the human (facing %s, offset %s)"
				% [m.name, str(m.get("facing")), str(off.round())],
		)
	for i in members.size():
		var m: Node = members[i]
		var gaps := Follow.gaps(walked, m, 2.5)
		var band := Follow.percentile(gaps, 0.5)
		var p90 := Follow.percentile(gaps, 0.9)
		t.check(
			band <= Follow.band_p50(i) and p90 <= Follow.BAND_P90,
			"%s walks within a band of the human (p50 %.0f px, most %.0f; p90 %.0f, most %.0f)"
				% [m.name, band, Follow.band_p50(i), p90, Follow.BAND_P90],
		)
		var behind := Follow.FOLLOW_GAP + Follow.FOLLOW_STEP * i
		var p50 := Follow.percentile(spacing[m], 0.5)
		t.check(
			absf(p50 - behind) <= FILE_SLACK,
			"%s's spot keeps %.0f px behind the walking human, follower %d of the file (median "
				% [m.name, behind, i + 1]
				+ "%.0f px, within %.0f; %d samples)" % [p50, FILE_SLACK, spacing[m].size()],
		)
		var least: float = reaims[m].min() if not reaims[m].is_empty() else INF
		t.check(
			reaims[m].size() >= 3 and least >= Follow.FOLLOW_RETARGET - 1.0,
			"%s re-aims its walk only once its spot moved %.0f px (%d re-aims, the least %.1f px)"
				% [m.name, Follow.FOLLOW_RETARGET, reaims[m].size(), least],
		)
	t.check(rang, "both rang the human within %.1f s of its stopping" % RING_WITHIN)
	var tuned := {
		"follow_gap": Follow.FOLLOW_GAP, "follow_step": Follow.FOLLOW_STEP,
		"follow_ring": Follow.FOLLOW_RING, "follow_still_time": Follow.FOLLOW_STILL_TIME,
		"follow_retarget": Follow.FOLLOW_RETARGET, "leash": Follow.LEASH,
		"leash_break": Follow.LEASH_BREAK,
	}
	var off_spec: Array = tuned.keys().filter(
		func(k): return not is_equal_approx(float(squad.get(k)), float(tuned[k])),
	)
	t.check(
		off_spec.is_empty(),
		"the squad's follow tunables are LD21 to LD23's (off: %s)"
			% str(off_spec.map(func(k): return "%s %s, not %s" % [k, squad.get(k), tuned[k]])),
	)
	var view: Dictionary = viewed.get("view", {})
	var rows: Array = view.get("members", [])
	var trail: Array = view.get("trail", [])
	t.check(
		trail.size() >= 2 and is_equal_approx(float(view.get("leash", 0.0)), Follow.LEASH),
		"mid-walk the view holds the human's trail and the leash (%d trail points, leash %s)"
			% [trail.size(), str(view.get("leash"))],
	)
	var mismatched: Array = members.filter(func(m):
		var row: Array = rows.filter(func(r): return r["node"] == m)
		return row.size() != 1 or row[0]["follow_spot"] != viewed["spots"][members.find(m)])
	t.check(
		not rows.is_empty() and mismatched.is_empty(),
		"each member's view row carries its own follow spot (Squad.follow_spot; rows %s)"
			% str(rows.map(func(r): return [Follow.name_of(r["node"]), r["follow_spot"]])),
	)
	t.check(
		members.all(func(m): return Follow.asked(w, m) == 0),
		"the followers asked Von nothing (%s)"
			% str(members.map(func(m): return Follow.asked(w, m))),
	)


## Whether `m` stands on the ring round `lead` (`FOLLOW_RING` px, within `RING_SLACK`).
func _on_ring(lead: Node, m: Node) -> bool:
	var d: float = m.global_position.distance_to(lead.global_position)
	return absf(d - Follow.FOLLOW_RING) <= RING_SLACK
