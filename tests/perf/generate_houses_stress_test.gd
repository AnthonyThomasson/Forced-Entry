extends GameTest
## Performance guard: generating and furnishing many houses stays fast, and a house's node count
## stays in a band (catches a runaway spawn or a leak). Budgets are wall-clock ms with headroom over
## the baseline.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const SEEDS := [101, 202, 303, 404, 505, 606, 707, 808, 909, 1010, 1111, 1212]
const FIXED_SEED := 424_242
# Baseline (cold caches, the slowest case): 12 houses ~1560 ms, worst ~355 ms, ~334 nodes. Budgets
# ~4x.
const TOTAL_BUDGET_MS := 6200.0
const WORST_HOUSE_BUDGET_MS := 1400.0
const NODE_BAND := [250, 420]
# A whole district (nine towers, streets, shells) from a fixed seed, built twice and each build held
# on its own: the first in a fresh process pays the caches (quiet machine, load 3 to 4, no other
# Godot: ~1855 ms, ~6650 nodes), the second is the steady cost (~147 ms) that a run after other
# tests also reads for the first (the whole perf domain: ~150 ms). Time budgets ~4x, the node band
# about +-25%.
# 2026-11-06, #192: the headless cold build runs without the art pre-warm (tests skip it), so the
# pre-warm does not move this number. Quiet machine, load 2.6 to 2.8, no other Godot, the test
# alone, twice: cold 1870 and 1873 ms, steady 152 and 153 ms (the whole perf domain: 157 and
# 160 ms for the first build). The base commit read 152 ms steady on the same machine. 7500 ms is
# 4.0x the cold build and 600 ms 3.9x the steady one, so neither is set again.
const DISTRICT_BUDGET_MS := 7500.0
const DISTRICT_WARM_BUDGET_MS := 600.0
const DISTRICT_NODE_BAND := [5200, 8700]


func describe() -> Dictionary:
	return {
		"name": "Generating many houses and a district stays fast",
		"description": "WorldGen.generate for a dozen seeds: total and worst-house wall time, and "
			+ "a fixed seed's node count, stay within budget; so do a district's time, built "
			+ "cold and again warm, and its nodes.",
		"tags": ["worldgen", "house"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func _house(house_seed: int, t: TestContext) -> void:
	var house := WorldGen.generate(house_seed, "", Vector2.ZERO, t.world)
	house.free()


func _district(t: TestContext, label: String, budget_ms: float) -> void:
	var before := Perf.nodes()
	var built: Array[Node2D] = []
	var ms := Perf.time_ms(
		func(): built.append(WorldGen.generate_district(FIXED_SEED, "", Vector2.ZERO, t.world)),
	)
	var count := Perf.nodes() - before
	GameLog.say("PERF district ms %.0f nodes %d" % [ms, count])
	Perf.within(t, label, ms, budget_ms)
	t.check(
		count >= DISTRICT_NODE_BAND[0] and count <= DISTRICT_NODE_BAND[1],
		"a district spawns %d nodes, expected %d..%d" % [
			count, DISTRICT_NODE_BAND[0], DISTRICT_NODE_BAND[1],
		],
	)
	built[0].free()


func run(t: TestContext) -> void:
	_district(t, "generate a district ms", DISTRICT_BUDGET_MS)
	_district(t, "generate a district again ms", DISTRICT_WARM_BUDGET_MS)
	var before := Perf.nodes()
	var worst := 0.0
	var total := 0.0
	for house_seed in SEEDS:
		var ms := Perf.time_ms(func(): _house(house_seed, t))
		worst = maxf(worst, ms)
		total += ms
	Perf.within(t, "generate %d houses total ms" % SEEDS.size(), total, TOTAL_BUDGET_MS)
	Perf.within(t, "generate worst house ms", worst, WORST_HOUSE_BUDGET_MS)

	var house := WorldGen.generate(FIXED_SEED, "", Vector2.ZERO, t.world)
	var count := Perf.nodes() - before
	GameLog.say("PERF house nodes %d" % count)
	t.trace("house nodes", count)
	t.check(
		count >= NODE_BAND[0] and count <= NODE_BAND[1],
		"a house spawns %d nodes, expected %d..%d" % [count, NODE_BAND[0], NODE_BAND[1]],
	)
	house.free()
	await t.frames(1)
	t.check(
		Perf.nodes() <= before + 2,
		"freeing a house frees its nodes (%d left over)" % (Perf.nodes() - before),
	)
