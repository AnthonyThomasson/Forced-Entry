extends RefCounted
## Shared helper for the performance tests (domain `perf`, tests/perf/). Load it with
## `const Perf := preload("res://tests/_perf/perf_probe.gd")`. Not a test (no `_test.gd` suffix).
##
## A frame's cost is the wall time of the main-loop iteration it ran in (`frame_stats`): headless
## runs use `--fixed-fps 60`, which outruns the wall clock, so that is the wall time between two
## physics frames, the real CPU cost of a frame. Budgets are wall-clock limits: the `SMOOTH_*`
## standard below for a frame loop, or (for one-shot work) a multiple of the baseline stated in the
## test.

## The standard a running match must meet, for every frame-based stress test: the average frame fits
## in one 60 fps frame (16.7 ms, the Performance overlay's target), the 95th percentile stays near
## it, and no frame takes over two.
const SMOOTH_AVG_MS := 16.7
const SMOOTH_P95_MS := 20.0
const SMOOTH_MAX_MS := 33.4
const OverlayRegistry := preload("res://scenes/ui/overlays/overlay_registry.gd")
const MatchSpawner := preload("res://scenes/match_spawner.gd")


## A match's NPC `npc` with its debug overlays at their defaults (off), as Main's `_configure_debug`
## leaves them: an overlay left on (the vision cone's export defaults to on) would be costed as if
## a player were watching it.
static func overlays_off(npc: Node) -> void:
	for child in npc.get_children():
		for flag in OverlayRegistry.defaults():
			if not OverlayRegistry.is_global(flag) and flag in child:
				child.set(flag, false)


## The test world's generated house's front entrance (world px), or the origin when it has none:
## where a match guard's spread invaders are placed from, as Main places them.
static func front_entrance(t: TestContext) -> Vector2:
	for o in WorldGen.get_openings(t.world.get("house")):
		if o["front"]:
			return o["pos"]
	return Vector2.ZERO


## Place a match guard's `per_side` a side as Main does, from `seed_value`: the defenders in random
## rooms, the invaders spread round the house heading for its front entrance (`spawn_invader`, so
## the match guards' frames compare), each armed from the default (random gun) loadout drawn from
## one seeded rng, with its debug overlays off (`overlays_off`). Returns the combatants in spawn
## order.
static func spawn_match(t: TestContext, seed_value: int, per_side: int) -> Array:
	var spawner = MatchSpawner.new()
	spawner.world = t.world
	spawner.openings = t.world.openings
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var entrance := front_entrance(t)
	for i in per_side:
		spawner.spawn_defender(t.rooms, rng, i)
	for i in per_side:
		spawner.spawn_invader(t.rooms, rng, i, per_side, entrance)
	var loadout_rng := RandomNumberGenerator.new()
	loadout_rng.seed = seed_value
	for c in spawner.combatants:
		LoadoutConfig.apply(c, {}, loadout_rng)
		overlays_off(c)
	return spawner.combatants


## Render every sound the way the game's background pre-warm has by the time a match is fought.
## Headless runs skip that pre-warm, so a test that plays sound would otherwise pay each variant's
## first synthesis (9 to 35 ms) mid-measurement.
static func warm_sounds() -> void:
	for pair: Array in Sound.library():
		SoundBank.sound(pair[0], pair[1])


## Wall-clock milliseconds one synchronous `work.call()` takes.
static func time_ms(work: Callable) -> float:
	var start := Time.get_ticks_usec()
	work.call()
	return (Time.get_ticks_usec() - start) / 1000.0


## Wall-clock cost of `frames` physics frames of the running test: `{ avg_ms, p95_ms, max_ms }`.
## `each`, if valid, is called with the frame index at the start of every measured frame (to keep
## applying load). A frame costs the main-loop iteration it ran in. Under `--fixed-fps`
## (tools/run_tests.sh) every iteration steps physics once and the next one follows at once, so
## that is the wall time from one physics frame to the next. A run paced to the clock (the editor's
## GdUnit panel, which gdUnit starts without `--fixed-fps`) also runs iterations that step no
## physics while it waits for the next step: a frame followed by one ends where that iteration's
## process frame begins, so a budget measures the work and not the 60 Hz pace.
static func frame_stats(t: TestContext, frames: int, each := Callable()) -> Dictionary:
	var tree := t.world.get_tree()
	# Main-loop iteration (`Engine.get_process_frames()`) -> usec of its process frame.
	var processed := {}
	var mark := func() -> void: processed[Engine.get_process_frames()] = Time.get_ticks_usec()
	var stop := func() -> void:
		if tree.process_frame.is_connected(mark):
			tree.process_frame.disconnect(mark)
	tree.process_frame.connect(mark)
	t.world.tree_exiting.connect(stop)  # a test that ends mid-measurement
	var samples: Array[float] = []
	await t.frames(1)
	var last := Time.get_ticks_usec()
	var last_iteration := Engine.get_process_frames()
	for i in frames:
		if each.is_valid():
			each.call(i)
		await t.frames(1)
		var now := Time.get_ticks_usec()
		var iteration := Engine.get_process_frames()
		var ended := now
		if iteration > last_iteration + 1:
			ended = processed.get(last_iteration + 1, now)
		samples.append((ended - last) / 1000.0)
		last = now
		last_iteration = iteration
	stop.call()
	if samples.is_empty():
		return { "avg_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0 }
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in samples:
		total += s
	return {
		"avg_ms": total / samples.size(),
		"p95_ms": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))],
		"max_ms": sorted[sorted.size() - 1],
	}


## Live nodes in the whole scene tree (and detached trees), for leak checks.
static func nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


## Record `value` as the measurement `label` (printed as `PERF label value`, traced, kept in the
## failure bundle) and check it stays within `limit`. Returns whether it did.
static func within(t: TestContext, label: String, value: float, limit: float) -> bool:
	GameLog.say("PERF %s %.2f (budget %.2f)" % [label, value, limit])
	t.trace(label, value)
	return t.check(value <= limit, "%s: %.2f is over its budget of %.2f" % [label, value, limit])


## `within` for each of a `frame_stats` result's average, 95th percentile and worst frame (ms).
static func within_frames(
	t: TestContext,
	label: String,
	stats: Dictionary,
	avg_limit: float,
	p95_limit: float,
	max_limit: float,
) -> void:
	within(t, label + " avg ms/frame", stats["avg_ms"], avg_limit)
	within(t, label + " p95 ms/frame", stats["p95_ms"], p95_limit)
	within(t, label + " max ms/frame", stats["max_ms"], max_limit)
