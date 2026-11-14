extends GameTest
## Performance guard for the player's view on an NPC in the largest match the game means to carry
## (`docs/player-vision.md`, Perf): the 10v10 of `perf/match_10v10_stress` (a generated downtown
## district whose centre house is the largest plan, `Perf.MATCH_PLAN`, `Perf.configure_match`, built
## as Main builds one), but with the view drawn of
## one invader (`TestSetup.view`) while it fights, the cone rebuilt whenever its inputs changed
## (`ViewWatch`), the capture and the memory painted and the composite drawn. The viewed invader is
## the tenth: a declared invader beside the nine of the match (the match's own NPCs are no test
## actors for the view to name), moved to stand with the invaders' group before the warm-up. After
## the warm-up the match runs on until the sides are in contact (`Perf.warm_until_contact`), then
## 300 frames are measured to the standard every frame-based guard holds: the average frame fits in
## one 60 fps frame (16.7 ms), the 95th percentile stays under 20 ms and no frame takes over 33.4
## ms. Headless measures CPU only (the cone's physics queries and its polygons, the painters' work);
## the GPU cost is measured by hand, windowed (`docs/lighting.md`, "Measured cost").
## Known red on the district. 2026-11-02: avg 25.0, p95 48.7, max 70.1 ms against 16.7, 20 and 33.4.
## It was red with `perf/match_10v10_stress` on a house (#98). 2026-11-07, #192, two runs (not
## `--quiet`: the gate was bypassed, `perf-district.md`; load 3.2 to 5.6, six other Godot processes
## that were no test's): avg 22.53 and 20.13, p95 35.97 and 31.25, max 46.69 and 42.67 ms. What it
## adds to the 10v10's own tail (the grenades' escape search, `match_10v10_stress_test.gd`) is the
## view's cone rebuilt almost every frame while its viewer moves (about 11 ms a frame in
## `perf/match_npc_vision_relative`'s moving rounds): a follow-up. The budgets are not loosened and
## the test is neither skipped nor tagged.
## #203: the numbers above are seed 7's fight, another fight than this guard plays now (not a
## baseline to read a change by, nor a sign of the guard getting faster or slower). The match plays
## one fight per seed, seed 2 now (`perf_probe.gd`), contact at 6.0 s every run, so the window is
## 6.0 to 11.0 s of the fight.
## Where the viewed invader stands decides whether the window sees the viewer alive (the premise
## below). The match's nine invaders start in a pack in the street, the defenders in the house to
## the south. Beside the first, the third or the eighth invader the viewed one is shot dead (and
## its fight reaches contact later, at 9.4 s); beside the last it is not hit at all (health 50.0
## through the window), the fight reaches contact at 6.0 s and the window is 6.0 to 11.0 s. So it
## stands `BESIDE` the last invader of the match. Only where it stands is set here: the seed,
## `Perf.configure_match` and the budgets are those of every match guard.
## Three `--quiet` runs (load 4.3 to 6.7): avg 19.32, 19.50 and 19.05, p95 28.50,
## 28.82 and 28.35, max 33.85, 34.21 and 33.51 ms. The budgets stay red (accepted, #223).

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
const PER_SIDE := 10
const MEASURE_FRAMES := 300
const NODE_GROWTH := 5000
## The viewed invader stands this far (px) beside the last invader of the match.
const BESIDE := Vector2(40.0, 0.0)


func describe() -> Dictionary:
	return {
		"name": "A 10v10 match runs without frame loss with the view on an NPC",
		"description": "Ten defenders and ten invaders fight in a generated downtown district, the "
			+ "view drawn of one invader; once they are in contact the average frame stays under "
			+ "16.7 ms and no frame takes over two.",
		"tags": ["match", "ai", "scripted", "crowd", "vision"],
		"timeout": 60.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)
	# Nine invaders in the match and the viewed one beside them: ten a side.
	s.declared_match({
		"defenders": { "count": PER_SIDE },
		"invaders": { "count": PER_SIDE - 1 },
	})
	s.switch(&"vision.enabled", true)
	s.actor(&"viewed", &"invader", Vector2.ZERO)
	s.view(&"viewed")


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var viewed: Node2D = t.actor(&"viewed")
	var characters: Array = t.world.match_handle.get("combatants", []).duplicate()
	if not t.require(
			characters.size() == PER_SIDE * 2 - 1,
			"nineteen combatants spawned beside the viewed one (%d)" % characters.size(),
	):
		return
	var views := Probe.views(t)
	if not t.require(
			views.size() == 1 and views[0].viewer() == viewed,
			"premise: one view, of the viewed invader (%d views)" % views.size(),
	):
		return
	var beside: Node2D = characters.filter(func(c): return c.get("faction") == &"invader")[-1]
	viewed.global_position = beside.global_position + BESIDE
	characters.append(viewed)
	Perf.record_fight(t, self, characters)
	if not await Perf.warm_until_contact(t, "10v10 match, viewed NPC", characters):
		return
	var nodes_before := Perf.nodes()
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES)
	GameLog.say(
		"PERF 10v10 viewed NPC match window: the view alive %s, the viewed NPC dead %s"
			% [is_instance_valid(views[0]), viewed.is_dead],
	)
	t.check(not viewed.is_dead, "premise: the viewed invader lived through the window")
	Perf.within_frames(t, "10v10 match, viewed NPC", stats)
	var grown := Perf.nodes() - nodes_before
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])
