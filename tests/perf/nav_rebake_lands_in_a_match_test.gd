extends GameTest
## Performance guard: a planning re-bake landing in a match costs no frame over two. The match is
## the 5v5 guard's (`Perf.configure_match`); once the sides are in contact a re-bake of the
## district (planning map and ring: `NavBuilder.rebake_async`, the updater's own bakes go on
## beside it) is started and the frames from the one after the start to a few past its landing are
## measured: the landing's weld and assignment, on the fixed frame `NavBakeConfig.district_frames`
## after the start, fit under `Perf.SMOOTH_MAX_MS` when its thread is on time (a late thread holds
## the frame, by design, so a late attempt is tried again, up to `ATTEMPTS`).
## Headless measures CPU only.
## No budget is set here: the standard is the frame standard.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const PER_SIDE := 5
const ATTEMPTS := 4
## Frames measured past the landing's.
const TAIL := 4


func describe() -> Dictionary:
	return {
		"name": "A re-bake lands in a match without a frame over two",
		"description": "In a 5v5 match, a district re-bake lands on its fixed frame with its "
			+ "thread on time and no frame of the window takes over 33.4 ms.",
		"tags": ["match", "navigation", "bake", "scripted"],
		"timeout": 80.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var characters: Array = t.world.match_handle.get("combatants", [])
	if not t.require(characters.size() == PER_SIDE * 2, "ten combatants spawned"):
		return
	if not await Perf.warm_until_contact(t, "re-bake match", characters):
		return
	var district: Node2D = t.world.district
	var rooms := WorldGen.district_rooms(district)
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	for attempt in ATTEMPTS:
		var started := Engine.get_physics_frames()
		var landed_at := [-1]  # a lambda captures an int by value
		var bakes := NavBuilder.rebake_async(
			region, district, rooms, NavBuilder.AGENT_RADIUS,
			func() -> void: landed_at[0] = Engine.get_physics_frames(),
		)
		var stats := await Perf.frame_stats(t, NavBakeConfig.district_frames + TAIL)
		if not t.require(landed_at[0] >= 0, "attempt %d: the re-bake has landed" % attempt):
			return
		t.check(
			landed_at[0] - started == NavBakeConfig.district_frames,
			"attempt %d: it landed on its frame (%d on)" % [attempt, landed_at[0] - started],
		)
		# This attempt's own bakes (the planning region's and the ring's), not the updater's.
		if bakes.any(func(b: NavBake) -> bool: return b.was_late):
			GameLog.say("PERF re-bake match attempt %d: the thread was late" % attempt)
			continue
		Perf.within(t, "re-bake match max ms/frame", stats["max_ms"], Perf.SMOOTH_MAX_MS)
		return
	t.check(false, "premise: a thread on time within %d attempts" % ATTEMPTS)
