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
## one fight per seed, seed 2 now (`perf_probe.gd`).
## Where the viewed invader stands decides what the window shows of it, and the guard means the
## view of an invader while it fights, alive (the premise below). The match's nine invaders start
## in a pack in the street, the defenders in the house to the south. Placed 40 px east of each:
## beside the first, second, third, fourth, sixth or eighth the viewed invader is shot dead;
## beside the fifth and the ninth it lives but never fights (retreat, evade and investigate acts,
## never nearer than 255 px to a defender); beside the seventh the sides make no contact in 30 s.
## Beside the fourth, 40 px west, it lives through the window (health 26.7 of 50), engages in 243
## of the 300 frames (`engage/fire_east`, then `advance`), knows a hostile in all of them and
## comes within 97 px of a defender; contact is at 8.2 s, the window 8.2 to 13.2 s. So it stands
## `BESIDE` the invader `BESIDE_INVADER` of the match. Only where it stands is set here: the seed,
## `Perf.configure_match` and the budgets are those of every match guard.
## Three `--quiet` runs (load 3.7 to 4.4): avg 20.06, 20.06 and 20.11, p95 26.73, 26.74 and 26.62,
## max 33.86, 32.71 and 33.14 ms. The budgets stay red (accepted, #223).

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
const PER_SIDE := 10
const MEASURE_FRAMES := 300
const NODE_GROWTH := 5000
## The viewed invader stands this far (px) beside the invader `BESIDE_INVADER` of the match.
const BESIDE := Vector2(-40.0, 0.0)
## Which of the match's nine invaders (spawn order, from 0) it stands beside: the fourth.
const BESIDE_INVADER := 3


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
	var invaders := characters.filter(func(c): return c.get("faction") == &"invader")
	var beside: Node2D = invaders[BESIDE_INVADER]
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
