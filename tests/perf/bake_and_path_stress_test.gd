extends GameTest
## Performance guard: re-baking the nav map of a generated downtown district (nine towers, the
## streets out to the shells: ~6800 nodes, ~350 furniture footprints, ~800 navmesh polygons) and
## answering many path queries stay fast. Budgets are wall-clock ms with headroom over the baseline.
## A frame never pays for the planning bake on the worker thread, so the planning guards are the
## whole bake done at once (`rebake`, the test seam) and what the frame does to start one
## (`rebake_async`: the footprints, the walls, the union; the game's tick takes the walls from the
## per-tower cache and spreads its steps over frames); the steering guard is a re-bake after a
## character stops somewhere new, which a match pays every tick (`nav_updater.gd`): the one to four
## tiles round it (`nav_tiles.gd`), where the whole district in one region cost ~57 ms. Baseline on
## a loaded machine (load ~4, three other Godot): ~57 ms a sync planning re-bake (a house: ~2.5),
## ~20 ms to start an async one, ~5.5 ms a steering re-bake, ~24 ms for all
## 300 queries (a house: ~1.2; the map has ten times the polygons). Budgets ~2.5-3x.
## 2026-11-06, #192 (quiet machine, load 2.7 to 3.2, no other Godot, two runs; the base commit on
## the same machine in brackets): 58.8 and 57.8 ms a planning re-bake [58.0], 21.7 and 21.3 ms to
## start an async one [21.2], 5.6 and 5.1 ms a steering re-bake [5.3], 23.8 and 23.1 ms for the 300
## queries [22.9]. The tile binning and the route cache did not move what these four measure (the
## steering re-bake here is one to four tiles), so no budget was set again then.
## 2026-11-07, #192, after the furniture-hole cache and the sliced planning gather (two runs, not
## `--quiet`: the gate was bypassed, `perf-district.md`; load 4.1 and 5.4, six other Godot processes
## that were no test's): 55.8 and 53.6 ms a planning re-bake, 18.3 and 17.8 to start an async one,
## 2.52 and 2.58 ms a steering re-bake, 23.3 and 22.9 ms for the 300 queries. The steering re-bake
## moved from about 5.5 to about 2.5 ms (a tick cuts only the pieces that moved), so its budget is
## set again at about 4x: 10 ms. The other three read within 15 % of the base and keep theirs.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const REBAKES := 10
const QUERIES := 300
const REBAKE_BUDGET_MS := 150.0
const ASYNC_BUDGET_MS := 60.0
const STEERING_BUDGET_MS := 10.0
const QUERY_BUDGET_MS := 60.0


func describe() -> Dictionary:
	return {
		"name": "Nav re-bake and path queries stay fast",
		"description": "A generated house is re-baked ten times and 300 paths are queried between "
			+ "its rooms; per-bake and per-query wall time stay within budget.",
		"tags": ["navigation", "bake", "path"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.district(424_242)
	s.switch(&"nav.rebake", false)
	s.actor(&"p", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the first bake is applied a frame or two after the build
	var district: Node2D = t.world.district
	var rooms := WorldGen.district_rooms(district)
	if not t.require(rooms.size() >= 2, "the district has rooms to path between"):
		return
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var rebake_ms := Perf.time_ms(func():
		for i in REBAKES:
			NavBuilder.rebake(region, district, rooms))
	Perf.within(t, "nav rebake ms each", rebake_ms / REBAKES, REBAKE_BUDGET_MS)
	await t.frames(2)  # let the last bake apply
	var async_ms := Perf.time_ms(func():
		for i in REBAKES:
			NavBuilder.rebake_async(region, district, rooms))
	Perf.within(t, "nav async rebake main-thread ms each", async_ms / REBAKES, ASYNC_BUDGET_MS)
	await t.seconds(1.0)  # let the bakes on the worker thread land
	await _steering(t, region, district, rooms)
	_queries(t, rooms)


## A character stops somewhere new, then the steering map is re-baked, `REBAKES` times: what a
## re-bake tick costs a frame while the characters are about.
func _steering(
	t: TestContext,
	region: NavigationRegion2D,
	district: Node2D,
	rooms: Array,
) -> void:
	var streets := WorldGen.district_bounds(district)
	var puppet := t.actor(&"p")
	var total_ms := 0.0
	for i in REBAKES:
		puppet.global_position = streets.position + Vector2(200 + 150 * i, 200 + 90 * (i % 3))
		await t.frames(2)
		total_ms += Perf.time_ms(func(): NavBuilder.rebake_steering(region, district, rooms))
	Perf.within(t, "nav steering rebake ms each", total_ms / REBAKES, STEERING_BUDGET_MS)


## `QUERIES` path queries between the district's rooms: their total time and how many found a path.
func _queries(t: TestContext, rooms: Array) -> void:
	var map := t.world.get_world_2d().navigation_map
	var found := [0]  # a lambda captures ints by value
	var query_ms := Perf.time_ms(func():
		for i in QUERIES:
			var a: Rect2 = rooms[i % rooms.size()]["rect"]
			var b: Rect2 = rooms[(i * 7 + 3) % rooms.size()]["rect"]
			var path := NavigationServer2D.map_get_path(map, a.get_center(), b.get_center(), true)
			if not path.is_empty():
				found[0] += 1)
	Perf.within(t, "nav %d path queries total ms" % QUERIES, query_ms, QUERY_BUDGET_MS)
	t.check(
		found[0] > int(QUERIES / 2.0),
		"most room-to-room paths are found (%d of %d)" % [found[0], QUERIES],
	)
