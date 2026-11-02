extends GameTest
## Performance guard: asking the same map the same point again is answered at once. A decision's
## snapshot snaps every room's centre and the same spots to the navmesh, again for each NPC and each
## decision of a match, and the server's answer scans every polygon of the map (a district's has ten
## times a house's): 15 us each, a third of a decision's nav time. The answer stands until the map
## is re-baked (`navigation/snap_follows_a_rebake`). Baseline: ~35 ms for 2000 snaps asked from the
## server each time (17 us), ~2 ms answered from the cache. Budget 4x the cached.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const ROUNDS := 50
const BUDGET_MS := 8.0


func describe() -> Dictionary:
	return {
		"name": "Snapping a point to a district's navmesh again is cheap",
		"description": "The centres of a district's rooms are snapped to its planning map 50 times "
			+ "each; the wall time of all of them stays within budget.",
		"tags": ["navigation", "path", "perf"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.district(424_242)
	s.switch(&"nav.rebake", false)
	s.actor(&"p", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the first bake is applied a frame or two after the build
	var rooms := WorldGen.district_rooms(t.world.district)
	if not t.require(rooms.size() >= 2, "the district has rooms to snap"):
		return
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var map := region.get_navigation_map()
	if not t.require(NavBuilder.ready(map), "premise: the planning map answers"):
		return
	var points: Array[Vector2] = []
	for room: Dictionary in rooms:
		points.append((room["rect"] as Rect2).get_center())
	var ms := Perf.time_ms(func():
		for _round in ROUNDS:
			for p in points:
				NavBuilder.snap(map, p))
	Perf.within(t, "%d snaps of %d points" % [ROUNDS * points.size(), points.size()], ms, BUDGET_MS)
