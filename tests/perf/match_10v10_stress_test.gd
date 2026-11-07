extends GameTest
## Performance guard for the largest match the game means to carry: a 10v10 in a generated downtown
## district (the largest plan, `Perf.MATCH_PLAN`; `Perf.configure_match`), built as Main builds one
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
## Baseline in the district on a loaded machine (load 4 to 7, three or more other Godot: no run was
## quiet enough to judge): avg 20 to 25 ms, p95 36 to 61, max 53 to 130; the house alone on that
## machine and load: avg 20.0, p95 35.2, max 61.3, so it misses the standard there too.
## Known red on the district. 2026-11-02: avg 19.4, p95 36.2, max 59.6 ms against 16.7, 20 and 33.4.
## 2026-11-07, #192, two runs (not `--quiet`: the gate was bypassed, `perf-district.md`; load 3.2 to
## 5.6, six other Godot processes that were no test's): avg 12.93 and 14.03, p95 27.07 and 25.90,
## max 56.08 and 37.93 ms. The average passes; the tail is the escape search a grenade's landing
## sets off in every NPC near it (`AgentThrow.escape`, reached through `react_to_grenades`, 5.7 to
## 6.4 ms a call, 32 to 40 calls in the 300 frames, in the 15 frames that make the p95; four of
## the five worst frames, 50 to 64 ms, spend 39 to 46 ms in that reflex). A snapshot builds in 4 ms
## on
## average and 8.4 at most. The budgets are not loosened and the test is
## neither skipped nor tagged.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Perf := preload("res://tests/_perf/perf_probe.gd")
const PER_SIDE := 10
const MEASURE_FRAMES := 300
const NODE_GROWTH := 5000


func describe() -> Dictionary:
	return {
		"name": "A 10v10 match runs without frame loss",
		"description": "Ten defenders and ten invaders, each side a squad following its leader, "
			+ "fight over a house in a downtown district, built as Main builds a match; once they "
			+ "are in contact the average frame stays under 16.7 ms and no frame takes over two.",
		"tags": ["match", "ai", "scripted", "crowd", "squad", "follow"],
		"timeout": 60.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var characters: Array = t.world.match_handle.get("combatants", [])
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
		not DecisionStub.requests.is_empty(),
		"the NPCs asked for decisions (%d asks)" % DecisionStub.requests.size(),
	)
	var grown := Perf.nodes() - nodes_before
	GameLog.say(
		"PERF 10v10 match node growth %d, %d decisions asked, %d following at the end"
			% [grown, DecisionStub.requests.size(), following],
	)
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])


## The premises the squads' cost rests on: one squad per side (the match's `squads`), handed to
## every NPC of that side, led by the rank rule's leader (the highest rank, the first spawned among
## equals), and every member but the leader following it (`Squad.follows`). False (the test ended)
## when one does not hold.
func _check_squads(t: TestContext, characters: Array) -> bool:
	var squads: Dictionary = t.world.match_handle.get("squads", {})
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
		var lead: Node = side.reduce(
			func(a, c): return c if int(c.wardrobe.rank) > int(a.wardrobe.rank) else a
		)
		if not t.require(
				squad.leader() == lead,
				"premise: the %s leader is the rank rule's (%s, rank %d; got %s)"
					% [faction, lead.name, int(lead.wardrobe.rank), Follow.name_of(squad.leader())],
		):
			return false
		if not t.require(
				side.all(func(c): return c == lead or squad.follows(c)),
				"premise: every %s member but the leader follows it (Squad.follows)" % faction,
		):
			return false
	return true
