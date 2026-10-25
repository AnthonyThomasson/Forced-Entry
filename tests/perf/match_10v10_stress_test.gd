extends GameTest
## Performance guard for the largest match the game means to carry: a 10v10 in a generated house
## (the largest plan, `Perf.MATCH_PLAN`; `Perf.configure_match`), built as Main builds one
## (`s.declared_match`, `MatchBuilder.populate`): the defenders at clear spots in random rooms and
## the invader team in one group beside the front door, each side with its spec loadout (the
## invaders' helmet and steel plates front and back, a stun and a frag each; the defenders' plain
## clothes; a random gun each), styled and ranked (the invaders' police unit: its lead, its
## sergeant, then troopers), one squad per side, every debug overlay off; nav re-baker, blood,
## debris, sound and team radio on, with Von scripted so no server is needed. Twenty NPCs sense,
## decide, path and fight; the house's walls hide most hostiles from each, which is what keeps it
## within reach of the standard where an open arena of twenty is not (perf/npc_crowd_stress). Each
## squad's members but its leader follow it (`docs/leadership.md` LD19 to LD23), so what a squad
## costs (the leader's trail, the follow spots, the follow primitive, the leash) is in the frame;
## every member but the leader following is a premise. The sides are in contact before the window
## opens: after its warm-up the match runs on until a shot has been fired and some NPC knows a
## hostile at once (`Perf.warm_until_contact`), so the frames cost the teams' fight (the leash
## filter, combat within the leash, the leash break) and not only a walking crowd. Then 300 frames
## are measured to the same standard as the 5v5 match: the average frame fits in one 60 fps frame,
## with no spike over two. It logs when contact came, how many knew a hostile as the window opened,
## the shots in the window and how many members were following at the end. Headless measures CPU
## only; rendering is not in these numbers. Its max (and p95) miss the standard on a quiet machine:
## an invader's decision that weighs its grenades (the throw spots and the escape from the burst, in
## its decision snapshot) spikes in one frame (#98).

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Perf := preload("res://tests/_perf/perf_probe.gd")
const PER_SIDE := 10
const MEASURE_FRAMES := 300
const NODE_GROWTH := 5000


func describe() -> Dictionary:
	return {
		"name": "A 10v10 match runs without frame loss",
		"description": "Ten defenders and ten invaders, each side a squad following its leader, "
			+ "fight in a generated house, built as Main builds a match; once they are in contact "
			+ "the average frame stays under 16.7 ms and no frame takes over two.",
		"tags": ["match", "ai", "scripted", "crowd", "squad", "follow"],
		"timeout": 60.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var characters: Array = t.match_handle().get("combatants", [])
	if not t.require(
			characters.size() == PER_SIDE * 2,
			"twenty combatants spawned (%d)" % characters.size(),
	):
		return
	if not _check_squads(t, characters):
		return
	if not await Perf.warm_until_contact(t, "10v10 match", characters):
		return
	var aware := characters.filter(func(c): return Perf.knows_hostile(c)).size()
	var nodes_before := Perf.nodes()
	var shots_before := t.events_of(&"shot").size()
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES)
	var shots := t.events_of(&"shot").size() - shots_before
	var following := characters.filter(func(c): return Follow.following(c)).size()
	GameLog.say(
		"PERF 10v10 match window: %d knowing a hostile as it opened, %d shots in it"
			% [aware, shots],
	)
	Perf.within_frames(t, "10v10 match", stats)
	t.check(
		not t.von_requests().is_empty(),
		"the NPCs asked for decisions (%d asks)" % t.von_requests().size(),
	)
	var grown := Perf.nodes() - nodes_before
	GameLog.say(
		"PERF 10v10 match node growth %d, %d decisions asked, %d following at the end"
			% [grown, t.von_requests().size(), following],
	)
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])


## The premises the squads' cost rests on: one squad per side (the match's `squads`), handed to
## every NPC of that side, led by the rank rule's leader (the highest rank, the first spawned among
## equals), and every member but the leader following it (`Squad.follows`). False (the test ended)
## when one does not hold.
func _check_squads(t: TestContext, characters: Array) -> bool:
	var squads: Dictionary = t.match_handle().get("squads", {})
	if not t.require(
		squads.size() == 2,
		"premise: one squad per side is built (%d)" % squads.size(),
	):
		return false
	for faction: StringName in squads:
		var squad: Node = squads[faction]
		var side: Array = characters.filter(func(c): return c.get("faction") == faction)
		if not t.require(
				side.all(func(c): return Follow.brain_of(c).get("squad") == squad),
				"premise: every %s NPC's controller has its side's squad" % faction,
		):
			return false
		var lead: Node = side.reduce(func(a, c): return c if int(c.rank) > int(a.rank) else a)
		if not t.require(
				squad.leader() == lead,
				"premise: the %s leader is the rank rule's (%s, rank %d; got %s)"
					% [faction, lead.name, int(lead.rank), Follow.name_of(squad.leader())],
		):
			return false
		if not t.require(
				side.all(func(c): return c == lead or squad.follows(c)),
				"premise: every %s member but the leader follows it (Squad.follows)" % faction,
		):
			return false
	return true
