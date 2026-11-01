extends GameTest
## Performance guard for the player's view on an NPC in the largest match the game means to carry
## (`docs/player-vision.md`, Perf): the 10v10 of `perf/match_10v10_stress` (a generated house of
## `Perf.MATCH_PLAN`, `Perf.configure_match`, built as Main builds one), but with the view drawn of
## one invader (`TestSetup.view`) while it fights, the cone rebuilt whenever its inputs changed
## (`ViewWatch`), the capture and the memory painted and the composite drawn. The viewed invader is
## the tenth: a declared invader beside the nine of the match (the match's own NPCs are no test
## actors for the view to name), moved to stand with the invaders' group before the warm-up. After
## the warm-up the match runs on until the sides are in contact (`Perf.warm_until_contact`), then
## 300 frames are measured to the standard every frame-based guard holds: the average frame fits in
## one 60 fps frame (16.7 ms), the 95th percentile stays under 20 ms and no frame takes over 33.4
## ms. Headless measures CPU only (the cone's physics queries and its polygons, the painters' work);
## the GPU cost is measured by hand, windowed (`docs/lighting.md`, "Measured cost").

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
const PER_SIDE := 10
const MEASURE_FRAMES := 300
const NODE_GROWTH := 5000
## The viewed invader stands this far (px) beside the first invader of the match.
const BESIDE := Vector2(40.0, 0.0)


func describe() -> Dictionary:
	return {
		"name": "A 10v10 match runs without frame loss with the view on an NPC",
		"description": "Ten defenders and ten invaders fight in a generated house, the view drawn "
			+ "of one invader; once they are in contact the average frame stays under 16.7 ms "
			+ "and no frame takes over two.",
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
	var beside: Node2D = characters.filter(func(c): return c.get("faction") == &"invader")[0]
	viewed.global_position = beside.global_position + BESIDE
	characters.append(viewed)
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
