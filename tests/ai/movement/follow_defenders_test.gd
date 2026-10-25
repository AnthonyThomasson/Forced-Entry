extends GameTest
## LD19 and LD21: defenders are a coordinated team the same way, from the start. Three defenders are
## placed in a pinned generated house the way Main places them, seeded with the house seed, and
## bound to their side's squad the way Main binds it (a match over the house,
## `tests/_ai/house_probe.gd`); the first spawned leads. The
## leader decides through Von as ever: gunfire heard inside the house, in the room farthest from it,
## sends it to investigate (a defender investigates gunfire inside,
## `ai/investigate/defender_investigates_gunfire_inside_von`), through the house's doorways. The
## crew follows it: within a band of it, through its doorways, asking Von nothing; and no follower
## stands more than `Follow.OFF_SPOT` off the follow spot the squad gives it for more than 8 s
## (LD21: a path that ends short of a spot it cannot reach counts as arrived); each follower's spot
## keeps to its place in the file or on the rings round a still leader.
##
## Real Von, the whole pipeline; no switch. The premise is the gunfire (a `hit` event nobody known
## fired, as `tests/_ai/investigate_probe.gd` posts it), heard by the whole crew: posted at the
## point of that room farthest from the crew, beyond every member's `hit_awareness_radius`, so it is
## heard and lands on nobody (a round striking within that radius puts a follower under fire, and
## the fight rules come before FOLLOW).

const Follow := preload("res://tests/_ai/follow_probe.gd")
const House := preload("res://tests/_ai/house_probe.gd")
const Investigate := preload("res://tests/_ai/investigate_probe.gd")
const SEED := 4
const CREW := 3
const WATCH_S := 90.0
## When (s) the gunfire is heard.
const GUNFIRE_AT := 2.0
## From when (s) the band and the spots are measured.
const SETTLE_S := 6.0
## How far (px) a follower's median spot may lie outside its place in the file and the ring (a
## snapped spot, a doorway's push back along the trail).
const SPOT_SLACK := 20.0


func describe() -> Dictionary:
	return {
		"name": "A defender crew follows its leader",
		"description": "Three defenders bound to a squad in a pinned house follow their first "
			+ "spawned leader as it investigates gunfire through the house: within a band of it, "
			+ "through its doorways, asking Von nothing, never 8 s off their spots.",
		"tags": ["ai", "movement", "squad", "follow", "leadership", "defender", "von"],
		"requires_von": true,
		"timeout": 140.0,
	}


func configure(s: TestSetup) -> void:
	House.house(s, SEED, CREW, 0)


func run(t: TestContext) -> void:
	var crew := House.side(t, &"household")
	if not t.require(crew.size() == CREW, "three defenders placed as Main places them"):
		return
	var squad := t.squad(&"household")
	if not t.require(squad != null, "premise: the match built the defenders' squad"):
		return
	var lead: Node = crew[0]
	if not t.require(squad.leader() == lead, "the first spawned leads (premise: LD3)"):
		return
	var members: Array = crew.slice(1)
	if not t.require(
			members.all(func(m): return squad.follows(m)),
			"premise: both members follow (Squad.follows: alive, not the leader)",
	):
		return
	var clocks := {}
	var spots := {}
	for m in members:
		clocks[m] = {}
		spots[m] = []
	var heard := [false]
	var clear := [INF]
	var each := func(_rec: Dictionary) -> void:
		if not heard[0] and t.time >= GUNFIRE_AT:
			heard[0] = true
			var at := _far_point(_farthest_room(t, lead.global_position), crew)
			clear[0] = _nearest(at, crew)
			Investigate.gunfire(at)
		for m: Node in members:
			Follow.off_spot_tick(t, squad, m, clocks[m])
			var spot: Vector2 = squad.follow_spot(m)
			if spot != Vector2.INF and t.time >= SETTLE_S:
				spots[m].append(spot.distance_to(lead.global_position))
	var done := func(rec: Dictionary) -> bool:
		var moves: Array = rec["moves"].get(lead, [])
		return moves.size() >= 2 and t.time > float(moves[1][0]) + 15.0
	var w: Dictionary = await Follow.watch(t, crew, squad, WATCH_S, { "stop": done, "each": each })
	var radius: float = Follow.brain_of(lead).hit_awareness_radius
	if not t.require(
			clear[0] > radius,
			"premise: the gunfire landed beyond the crew's hit awareness (%.0f px off, radius %.0f)"
				% [clear[0], radius],
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
			"%s follows its leader (FOLLOW; acts %s)" % [m.name, Follow.acts_of(w, m)],
		)
		var gaps := Follow.gaps(w, m, SETTLE_S)
		var p50 := Follow.percentile(gaps, 0.5)
		var p90 := Follow.percentile(gaps, 0.9)
		t.check(
			p50 <= Follow.band_p50(i) and p90 <= Follow.BAND_P90,
			"%s stays within a band of the leader (p50 %.0f px, most %.0f; p90 %.0f, most %.0f)"
				% [m.name, p50, Follow.band_p50(i), p90, Follow.BAND_P90],
		)
		for k in 2:
			t.check(
				Follow.went_through(w, m, lead_moves[k]),
				"%s went through the leader's doorway %d (%s -> %s at %.1f s) (moves %s)"
					% [
						m.name,
						k + 1,
						lead_moves[k][1],
						lead_moves[k][2],
						lead_moves[k][0],
						str(w["moves"].get(m, [])),
					],
			)
		# The spot itself is LD21's: its place in the file while the leader walks, a slot on one
		# of the rings round it once it stands (the first ring is often out of the leader's sight
		# indoors), the median between the two (D28's step aside is rare).
		var place := Follow.FOLLOW_GAP + Follow.FOLLOW_STEP * i
		var outer := Follow.FOLLOW_RING + Follow.FOLLOW_STEP * (Follow.FOLLOW_RINGS - 1)
		var spot_p50 := Follow.percentile(spots[m], 0.5)
		t.check(
			spot_p50 >= minf(place, Follow.FOLLOW_RING) - SPOT_SLACK
				and spot_p50 <= maxf(place, outer) + SPOT_SLACK,
			"%s's follow spot keeps to its place by the leader: %.0f px back in the file or on the "
				% [m.name, place]
				+ "rings %.0f to %.0f px (median %.0f px off the leader, within %.0f; %d samples)"
				% [Follow.FOLLOW_RING, outer, spot_p50, SPOT_SLACK, spots[m].size()],
		)
		t.check(
			float(clocks[m].get("longest", 0.0)) <= Follow.STUCK_S,
			"%s was never more than %.0f s off its spot (longest %.1f s)"
				% [m.name, Follow.STUCK_S, float(clocks[m].get("longest", 0.0))],
		)
		t.expect_eq(
			Follow.asked(w, m),
			0,
			"%s asked Von nothing while no hostile was known (acts %s)"
				% [m.name, Follow.acts_of(w, m)],
		)
	t.check(Follow.asked(w, lead) > 0, "the leader decided through Von as ever")


## The house room (its rect) whose centre is farthest from `p`.
func _farthest_room(t: TestContext, p: Vector2) -> Rect2:
	var best := Rect2(p, Vector2.ZERO)
	for r in t.rooms:
		var rect: Rect2 = r["rect"]
		if rect.get_center().distance_to(p) > best.get_center().distance_to(p):
			best = rect
	return best


## The point of `rect` (on a grid, a body's width in from its walls) farthest from the nearest of
## `crew`.
func _far_point(rect: Rect2, crew: Array) -> Vector2:
	var inner := rect.grow(-30.0)
	var best := inner.get_center()
	for i in 11:
		for j in 11:
			var p := inner.position + inner.size * Vector2(i / 10.0, j / 10.0)
			if _nearest(p, crew) > _nearest(best, crew):
				best = p
	return best


## How far `p` is from the nearest of `crew`.
func _nearest(p: Vector2, crew: Array) -> float:
	var out := INF
	for c: Node2D in crew:
		out = minf(out, p.distance_to(c.global_position))
	return out
