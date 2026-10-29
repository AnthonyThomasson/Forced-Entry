extends GameTest
## LD19 and LD21: defenders are a coordinated team the same way, from the start. Three defenders are
## placed in a pinned generated house the way Main places them, seeded with the house seed, and
## bound to their side's squad the way Main binds it (a match over the house,
## `tests/_ai/house_probe.gd`); the first spawned leads. The
## leader decides through Von as ever: with no hostile known, the crew's own search takes it from
## room to room, through the house's doorways. The crew follows it: within a band of it, through
## its doorways, asking Von nothing; and no follower stands more than `Follow.OFF_SPOT` off the
## follow spot the squad gives it for more than 8 s (LD21: a path that ends short of a spot it
## cannot reach counts as arrived); each follower's spot keeps to its place in the file or on the
## rings round a still leader.
##
## Real Von, the whole pipeline; no switch, no premise but the house. (Gunfire heard in another
## room used to send the leader through the house; since the defenders' ambush rule (#128) a heard
## threat posts the crew at its room's doorway instead, so the leader's search walks it.)

const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const House := preload("res://tests/_ai/house_probe.gd")
## The pinned house: one whose search offers the leader a choice of rooms (in house 4 every level
## of it was a lone option, taken without asking Von).
const SEED := 1
const CREW := 3
const WATCH_S := 90.0
## From when (s) the band and the spots are measured.
const SETTLE_S := 6.0
## How far (px) a follower's median spot may lie outside its place in the file and the ring (a
## snapped spot, a doorway's push back along the trail).
const SPOT_SLACK := 20.0


func describe() -> Dictionary:
	return {
		"name": "A defender crew follows its leader",
		"description": "Three defenders bound to a squad in a pinned house follow their first "
			+ "spawned leader as it searches the house: within a band of it, "
			+ "through its doorways, asking Von nothing, never 8 s off their spots.",
		"tags": ["ai", "movement", "squad", "follow", "leadership", "defender", "von"],
		"requires_von": true,
		"timeout": 140.0,
	}


func configure(s: TestSetup) -> void:
	House.house(s, SEED, CREW, 0)


func run(t: TestContext) -> void:
	var crew := House.side(t, &"household")
	var squad := _squad_of(t, crew)
	if squad == null:
		return
	var lead: Node = crew[0]
	var members: Array = crew.slice(1)
	# What the watch keeps per member (`clocks`: its off-spot clock, `spots`: its follow spot's
	# distance from the leader).
	var track := { "clocks": {}, "spots": {} }
	for m in members:
		track["clocks"][m] = {}
		track["spots"][m] = []
	var each := _each(t, squad, crew, track)
	var done := _done(t, lead)
	var w: Dictionary = await FollowWatch.watch(
		t,
		crew,
		squad,
		WATCH_S,
		{ "stop": done, "each": each },
	)
	var lead_moves: Array = w["moves"].get(lead, [])
	if not t.require(
			lead_moves.size() >= 2,
			"the leader went through two doorways (moves %s; acts %s)"
				% [str(lead_moves), FollowWatch.acts_of(w, lead)],
	):
		return
	for i in members.size():
		var m: Node = members[i]
		_check_follows(t, w, m, i, lead_moves)
		_check_spot(t, m, i, track)
		t.expect_eq(
			FollowWatch.asked(w, m),
			0,
			"%s asked Von nothing while no hostile was known (acts %s)"
				% [m.name, FollowWatch.acts_of(w, m)],
		)
	t.check(FollowWatch.asked(w, lead) > 0, "the leader decided through Von as ever")


## The match's squad of `crew`, once its premises hold (three placed, the first spawned leading,
## both others following); null when one fails.
func _squad_of(t: TestContext, crew: Array) -> Node:
	if not t.require(crew.size() == CREW, "three defenders placed as Main places them"):
		return null
	var squad: Node = t.world.squad(&"household")
	if not t.require(squad != null, "premise: the match built the defenders' squad"):
		return null
	var lead: Node = crew[0]
	if not t.require(squad.leader() == lead, "the first spawned leads (premise: LD3)"):
		return null
	var members: Array = crew.slice(1)
	if not t.require(
			members.all(func(m): return squad.follows(m)),
			"premise: both members follow (Squad.follows: alive, not the leader)",
	):
		return null
	return squad


## The watch's per-frame step: each member's off-spot clock and follow spot into `track`.
func _each(t: TestContext, squad: Node, crew: Array, track: Dictionary) -> Callable:
	var lead: Node = crew[0]
	var members: Array = crew.slice(1)
	var clocks: Dictionary = track["clocks"]
	var spots: Dictionary = track["spots"]
	return func(_rec: Dictionary) -> void:
		for m: Node in members:
			FollowWatch.off_spot_tick(t, squad, m, clocks[m])
			var spot: Vector2 = squad.follow_spot(m)
			if spot != Vector2.INF and t.time >= SETTLE_S:
				spots[m].append(spot.distance_to(lead.global_position))


## The watch's end: 15 s after the leader's second doorway.
func _done(t: TestContext, lead: Node) -> Callable:
	return func(rec: Dictionary) -> bool:
		var moves: Array = rec["moves"].get(lead, [])
		return moves.size() >= 2 and t.time > float(moves[1][0]) + 15.0


## Member `m` (the `i`th) follows: FOLLOW taken, within a band of the leader, through the leader's
## first two doorways `lead_moves`.
func _check_follows(t: TestContext, w: Dictionary, m: Node, i: int, lead_moves: Array) -> void:
	t.check(
		FollowWatch.took(w, m, "follow"),
		"%s follows its leader (FOLLOW; acts %s)" % [m.name, FollowWatch.acts_of(w, m)],
	)
	var gaps := FollowWatch.gaps(w, m, SETTLE_S)
	var p50 := FollowWatch.percentile(gaps, 0.5)
	var p90 := FollowWatch.percentile(gaps, 0.9)
	t.check(
		p50 <= Follow.band_p50(i) and p90 <= Follow.BAND_P90,
		"%s stays within a band of the leader (p50 %.0f px, most %.0f; p90 %.0f, most %.0f)"
			% [m.name, p50, Follow.band_p50(i), p90, Follow.BAND_P90],
	)
	for k in 2:
		t.check(
			FollowWatch.went_through(w, m, lead_moves[k]),
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


## Member `m`'s (the `i`th) follow spot keeps to its place by the leader, and it was never long off
## it, as `track` holds them.
func _check_spot(t: TestContext, m: Node, i: int, track: Dictionary) -> void:
	var spots: Array = track["spots"][m]
	var clock: Dictionary = track["clocks"][m]
	# The spot itself is LD21's: its place in the file while the leader walks, a slot on one
	# of the rings round it once it stands (the first ring is often out of the leader's sight
	# indoors), the median between the two (D28's step aside is rare).
	var place := Follow.FOLLOW_GAP + Follow.FOLLOW_STEP * i
	var outer := Follow.FOLLOW_RING + Follow.FOLLOW_STEP * (Follow.FOLLOW_RINGS - 1)
	var spot_p50 := FollowWatch.percentile(spots, 0.5)
	t.check(
		spot_p50 >= minf(place, Follow.FOLLOW_RING) - SPOT_SLACK
			and spot_p50 <= maxf(place, outer) + SPOT_SLACK,
		"%s's follow spot keeps to its place by the leader: %.0f px back in the file or on the "
			% [m.name, place]
			+ "rings %.0f to %.0f px (median %.0f px off the leader, within %.0f; %d samples)"
			% [Follow.FOLLOW_RING, outer, spot_p50, SPOT_SLACK, spots.size()],
	)
	t.check(
		float(clock.get("longest", 0.0)) <= Follow.STUCK_S,
		"%s was never more than %.0f s off its spot (longest %.1f s)"
			% [m.name, Follow.STUCK_S, float(clock.get("longest", 0.0))],
	)
