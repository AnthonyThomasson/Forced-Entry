extends GameTest
## Performance guard for the thing a player watches: a 5v5 match in a generated house (the largest
## plan, `Perf.MATCH_PLAN`; `Perf.configure_match`), built as Main builds one (`s.declared_match`,
## `MatchBuilder.populate`): the defenders at clear spots in random rooms and the invader team in
## one group beside the front door, each side with its spec loadout (the invaders' helmet and steel
## plates front and back, a stun and a frag each; the defenders' plain clothes; a random gun each),
## styled and ranked, one squad per side (its members following their leader), every debug overlay
## off; nav re-baker, blood, debris, sound and team radio on, with Von scripted so no server is
## needed. After its warm-up the match runs on until the sides are in contact, a shot fired and some
## NPC knowing a hostile (`Perf.warm_until_contact`: a premise); then 300 frames are measured: the
## average frame must fit in one 60 fps frame, with no spike over two. Headless measures CPU only;
## rendering is not in these numbers.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const PER_SIDE := 5
const MEASURE_FRAMES := 300
const NODE_GROWTH := 2500


func describe() -> Dictionary:
	return {
		"name": "A 5v5 match runs without frame loss",
		"description": "Five defenders and five invaders fight in a generated house, built as "
			+ "Main builds a match; the average frame stays under 16.7 ms and no frame takes over "
			+ "two.",
		"tags": ["match", "ai", "scripted", "crowd"],
		"timeout": 40.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var characters: Array = t.match_handle().get("combatants", [])
	if not t.require(
			characters.size() == PER_SIDE * 2,
			"ten combatants spawned (%d)" % characters.size(),
	):
		return
	if not await Perf.warm_until_contact(t, "5v5 match", characters):
		return
	var nodes_before := Perf.nodes()
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES)
	Perf.within_frames(t, "5v5 match", stats)
	t.check(
		not t.von_requests().is_empty(),
		"the NPCs asked for decisions (%d asks)" % t.von_requests().size(),
	)
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF 5v5 match node growth %d, %d decisions asked"
			% [grown, t.von_requests().size()])
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])
