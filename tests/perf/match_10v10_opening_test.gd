extends GameTest
## Performance guard for the opening of the largest match the game means to carry: the same 10v10 as
## `perf/match_10v10_stress` (`Perf.configure_match`: the downtown district, the largest plan, the
## squads, scripted Von), but its window opens at the fight's first sign, the first shot or the
## first NPC knowing a hostile, whichever comes first, and runs `Perf.OPENING_FRAMES` (300, five
## seconds) from there. The stress guard opens its window only once a shot has been fired AND some
## NPC knows a hostile, 6 s of warm-up and the wait for contact in: at 8.8 s of test time in this
## match, where the first sighting comes at 4.2 s, so the first sightings, the first decisions of
## the NPCs that met, the first throws and the first escape searches were never in a window, and a
## player feels those as the stutter at a fight's start. This window ends at 9.2 s, so it overlaps
## the start of the stress window and nothing between them goes unmeasured. The frames are held to
## the same standard, with no looser tail: `Perf.within_frames` (avg 16.7, p95 20, max 33.4 ms). On
## a red run `--verbose` names the worst frames and what ran in each (`perf-opening.md`).
## The premises: the window opens at the first contact (at most `MOST_SHOTS_BEFORE` shots before
## it) and holds a shot and decisions asked.
## With the decisions sliced it still read red on p95 (22 to 24 ms against 20) at the last
## measurement: the worst frames and what ran in them are in `perf-opening.md`.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const PER_SIDE := 10
## The longest (s) the match is given to show its first sign: the invaders start in the street.
const FIRST_CONTACT_WITHIN := 30.0
const NODE_GROWTH := 5000
## The most shots (the first volley of one frame or two) a fight's opening may hold before its
## window: past that the window has missed the first contact.
const MOST_SHOTS_BEFORE := 3


func describe() -> Dictionary:
	return {
		"name": "The opening of a 10v10 match runs without frame loss",
		"description": "The 10v10 of the stress guard measured from the first shot or the first "
			+ "sighting for five seconds: the average frame stays under 16.7 ms, the 95th "
			+ "percentile under 20 and no frame takes over two.",
		"tags": ["match", "ai", "scripted", "crowd", "opening"],
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
	Perf.record_fight(t, self, characters)
	var cause := await Perf.await_first_contact(
		t, "10v10 opening", characters, FIRST_CONTACT_WITHIN,
	)
	if not t.require(
			cause != "",
			"premise: the fight shows a first sign, a shot or an NPC knowing a hostile, within "
				+ "%.0f s (%.1f s)" % [FIRST_CONTACT_WITHIN, t.time],
	):
		return
	var shots_before := t.events_of(&"shot").size()
	var asks_before := DecisionStub.requests.size()
	var nodes_before := Perf.nodes()
	if not t.require(
			shots_before <= MOST_SHOTS_BEFORE,
			"premise: the window opens at the first contact, at most %d shots before it (%d)"
				% [MOST_SHOTS_BEFORE, shots_before],
	):
		return
	Perf.mark_bakes()
	var stats := await Perf.frame_stats(t, Perf.OPENING_FRAMES)
	var shots := t.events_of(&"shot").size() - shots_before
	var asks := DecisionStub.requests.size() - asks_before
	GameLog.say(
		"PERF 10v10 opening window: opened by a %s, %d shots, %d decisions asked"
			% [cause, shots, asks]
	)
	if not t.require(shots > 0, "premise: a shot is fired in the opening window (%d)" % shots):
		return
	if not t.require(
			asks > 0,
			"premise: the NPCs ask for decisions in the opening window (%d)" % asks,
	):
		return
	Perf.within_frames(t, "10v10 opening", stats)
	var grown := Perf.nodes() - nodes_before
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])
