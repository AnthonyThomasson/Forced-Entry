extends GameTest
## Performance guard for the thing a player watches: a 5v5 match in a generated downtown district
## (its centre tower the largest plan, `Perf.MATCH_PLAN`; `Perf.configure_match`), built as Main
## builds one (`s.declared_match`, `MatchBuilder.populate`): the defenders at clear spots in random
## rooms and the invader team in one group beside the front door, each side with its spec loadout
## (the invaders' helmet and steel plates front and back, a stun and a frag each; the defenders'
## plain clothes; a random gun each), styled and ranked, one squad per side (its members following
## their leader), every debug overlay off; nav re-baker, blood, debris, sound and team radio on,
## with Von scripted so no server is needed. After its warm-up the match runs on until the sides are
## in contact, a shot fired and some NPC knowing a hostile (`Perf.warm_until_contact`: a premise);
## then 300 frames are measured: the average frame must fit in one 60 fps frame, with no spike over
## two. Headless measures CPU only; rendering is not in these numbers.
## Baseline in the district on a loaded machine (load 4 to 7, three or more other Godot: no run was
## quiet enough to judge): avg 8 to 14 ms, p95 13 to 43, max 27 to 104 over a dozen runs; the house
## alone on that machine and load: avg 8.4, p95 11.9, max 27.3. Contact came at 18 to 30 s.
## Red on the district until #192 (avg 8.0, p95 21.3, max 65.4 ms on 2026-11-02: the AI's decisions
## in open combat). Green on 2026-11-07, #192, in two runs (not `--quiet`: the gate was bypassed,
## `perf-district.md`; load 3.2 to 5.6, six other Godot processes that were no test's): avg 7.07 and
## 6.44, p95 15.88 and 13.09, max 26.01 and 17.98 ms against 16.7, 20 and 33.4.
## #203: the match plays one fight per seed (seed 2 now, `perf_probe.gd`), contact at 7.7 s, no late
## nav bake; four runs (load 6 to 7.5, not `--quiet`): avg 6.69 to 6.91, p95 14.04 to 15.20, max
## 27.38 to 28.61 ms.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const PER_SIDE := 5
const MEASURE_FRAMES := 300
const NODE_GROWTH := 2500


func describe() -> Dictionary:
	return {
		"name": "A 5v5 match runs without frame loss",
		"description": "Five defenders and five invaders fight over a house in a downtown "
			+ "district, built as Main builds a match; the average frame stays under 16.7 ms and "
			+ "no frame takes over two.",
		"tags": ["match", "ai", "scripted", "crowd"],
		"timeout": 50.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var characters: Array = t.world.match_handle.get("combatants", [])
	if not t.require(
			characters.size() == PER_SIDE * 2,
			"ten combatants spawned (%d)" % characters.size(),
	):
		return
	Perf.record_fight(t, self, characters)
	if not await Perf.warm_until_contact(t, "5v5 match", characters):
		return
	var nodes_before := Perf.nodes()
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES)
	Perf.within_frames(t, "5v5 match", stats)
	t.check(
		not DecisionStub.requests.is_empty(),
		"the NPCs asked for decisions (%d asks)" % DecisionStub.requests.size(),
	)
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF 5v5 match node growth %d, %d decisions asked"
			% [grown, DecisionStub.requests.size()])
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])
