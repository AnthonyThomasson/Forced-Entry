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
## The match the match guards measure (`perf/match_5v5_stress`, `perf/match_10v10_stress`,
## `perf/grenade_match_stress`, through `configure_match`): a generated house of seed `MATCH_SEED`
## on the largest plan by floor area, `MATCH_PLAN` (garage_home: five rooms, 760k px²), pinned
## rather than drawn from the seed: the match is measured in a full-size house whatever the
## catalogue holds, and a plan added or dropped changes no seed's load. A small flat would put both
## sides in each other's sight from the start, which is a different load.
const MATCH_SEED := 7
const MATCH_PLAN := "garage_home"
## Test seconds a match guard's warm-up runs before it waits for contact (`warm_until_contact`).
const MATCH_WARMUP_S := 6.0
## The most (s) the warm-up runs on past `MATCH_WARMUP_S` for the sides to make contact (a shot
## fired, and some NPC knowing a hostile).
const MATCH_CONTACT_WITHIN := 20.0
## The engine lines a match guard allows (`allowed_logs`): a real match re-bakes the navmesh while
## furniture is shoved around, and now and then the bake of overlapping footprints is rejected by
## the engine (about one run in five). That is a nav bug no guard is about; the bake's cost is part
## of what each measures, so the lines are allowed rather than the re-bake switched off.
const MATCH_LOGS := [
	"Navigation map synchronization error",
	"NavigationPolygon polygon convex partition failed",
]


## Declare a match guard's match in `s`: the house `MATCH_SEED` on `MATCH_PLAN`, `per_side`
## defenders and as many invaders built as Main builds a match (`s.match`), scripted Von (combat,
## engage) and the callouts, vision and pursuit on.
static func configure_match(s: TestSetup, per_side: int) -> void:
	s.house(MATCH_SEED, MATCH_PLAN)
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", true)
	s.switch(&"ai.vision", true)
	s.switch(&"ai.pursuit", true)
	s.match({ "defenders": { "count": per_side }, "invaders": { "count": per_side } })


## A match guard's warm-up: `MATCH_WARMUP_S` s, then on until its sides are in contact
## (`await_contact` over `characters`, at most `MATCH_CONTACT_WITHIN` s more), `require`d as the
## guard's premise. Returns whether it held (false: the test has ended).
static func warm_until_contact(t: TestContext, label: String, characters: Array) -> bool:
	await t.seconds(MATCH_WARMUP_S)
	return t.require(
		await await_contact(t, label, characters, MATCH_CONTACT_WITHIN),
		("premise: the fight is on within %.0f s of the warm-up, a shot fired and some NPC "
				+ "knowing a hostile (%.1f s)")
			% [MATCH_CONTACT_WITHIN, t.time],
	)


## Run a match guard's warm-up on until its sides are in contact: a shot has been fired and some
## NPC among `characters` knows a hostile (`knows_hostile`) at once, at most `limit_s` s of test
## time more. Logs when contact came (`PERF <label> contact at <s> s`). Returns whether it came; the
## caller `require`s it as its premise.
static func await_contact(t: TestContext, label: String, characters: Array, limit_s: float) -> bool:
	var on := func() -> bool:
		return t.happened(&"shot") and characters.any(func(c): return knows_hostile(c))
	if not await t.until(on, limit_s):
		return false
	GameLog.say("PERF %s contact at %.1f s" % [label, t.time])
	return true


## Whether character `c` (an NPC) knows a hostile now (`known_contacts_for_display()`, interface 7);
## false for a dead or freed one and for a character with no AI controller.
static func knows_hostile(c: Node) -> bool:
	if not is_instance_valid(c) or c.get("is_dead") == true:
		return false
	var brain := TestContext.controller_of(c, &"known_contacts_for_display")
	if brain == null:
		return false
	return brain.known_contacts_for_display().any(func(k): return k.get("hostile", false))


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
	return _stats_of(samples)


## Live nodes in the whole scene tree (and detached trees), for leak checks.
static func nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


## Record `value` as the measurement `label` (printed as `PERF label value`, traced, kept in the
## failure bundle) and check it stays within `limit`. Returns whether it did.
static func within(t: TestContext, label: String, value: float, limit: float) -> bool:
	GameLog.say("PERF %s %.2f (budget %.2f)" % [label, value, limit])
	t.trace(label, value)
	return t.check(value <= limit, "%s: %.2f is over its budget of %.2f" % [label, value, limit])


## `within` for each of a `frame_stats` result's average, 95th percentile and worst frame (ms),
## against the frame standard every frame-based test holds: `SMOOTH_AVG_MS`, `SMOOTH_P95_MS`,
## `SMOOTH_MAX_MS`.
static func within_frames(t: TestContext, label: String, stats: Dictionary) -> void:
	within(t, label + " avg ms/frame", stats["avg_ms"], SMOOTH_AVG_MS)
	within(t, label + " p95 ms/frame", stats["p95_ms"], SMOOTH_P95_MS)
	within(t, label + " max ms/frame", stats["max_ms"], SMOOTH_MAX_MS)


## The `{ avg_ms, p95_ms, max_ms }` of the frame times `samples` (ms), zeros for none.
static func _stats_of(samples: Array[float]) -> Dictionary:
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
