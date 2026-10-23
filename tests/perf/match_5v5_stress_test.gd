extends GameTest
## Performance guard for the thing a player watches: a 5v5 match in a generated house (the largest
## plan, `PLAN`), built as Main builds one (`s.match`, `MatchBuilder.populate`): the defenders at
## clear spots in random rooms and the invader team in one group beside the front door, each side
## with its spec loadout (the invaders' helmet and steel plates front and back, a stun and a frag
## each; the defenders' plain clothes; a random gun each), styled and ranked, one squad per side
## (its members following their leader), every debug overlay off; nav re-baker, blood, debris,
## sound and team radio on, with Von scripted so no server is needed. After `WARMUP_S` the warm-up
## runs on until the sides are in contact, a shot fired and some NPC knowing a hostile
## (`Perf.await_contact`, at most `CONTACT_WITHIN` s more: a premise); then 300 frames are
## measured: the average frame must fit in one 60 fps frame, with no spike over two. Headless
## measures CPU only; rendering is not in these numbers.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const SEED := 7
## The house is the largest plan by floor area (garage_home: five rooms, 760k px²), pinned rather
## than drawn from the seed: the match is measured in a full-size house whatever the catalogue
## holds, and a plan added or dropped changes no seed's load. A small flat would put both sides in
## each other's sight from the start, which is a different load.
const PLAN := "garage_home"
const PER_SIDE := 5
const WARMUP_S := 6.0
## The most (s) the warm-up runs on past `WARMUP_S` for the sides to make contact (a shot fired,
## and some NPC knowing a hostile).
const CONTACT_WITHIN := 20.0
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
		# A real match re-bakes the navmesh while furniture is shoved around, and now and then the
		# bake of overlapping footprints is rejected by the engine (about one run in five). That is
		# a nav bug this test is not about; the bake's cost is part of what it measures, so the two
		# lines are allowed rather than the re-bake switched off.
		"allowed_logs": [
			"Navigation map synchronization error",
			"NavigationPolygon polygon convex partition failed",
		],
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, PLAN)
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", true)
	s.switch(&"ai.vision", true)
	s.switch(&"ai.pursuit", true)
	s.match({ "defenders": { "count": PER_SIDE }, "invaders": { "count": PER_SIDE } })


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var characters: Array = t.match().get("combatants", [])
	if not t.require(
			characters.size() == PER_SIDE * 2,
			"ten combatants spawned (%d)" % characters.size(),
	):
		return
	await t.seconds(WARMUP_S)
	if not t.require(
			await Perf.await_contact(t, "5v5 match", characters, CONTACT_WITHIN),
			("premise: the fight is on within %.0f s of the warm-up, a shot fired and some NPC "
					+ "knowing a hostile (%.1f s)")
				% [CONTACT_WITHIN, t.time],
	):
		return
	var nodes_before := Perf.nodes()
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES)
	Perf.within_frames(
		t, "5v5 match", stats, Perf.SMOOTH_AVG_MS, Perf.SMOOTH_P95_MS, Perf.SMOOTH_MAX_MS,
	)
	t.check(
		not t.von_requests().is_empty(),
		"the NPCs asked for decisions (%d asks)" % t.von_requests().size(),
	)
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF 5v5 match node growth %d, %d decisions asked"
			% [grown, t.von_requests().size()])
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])
