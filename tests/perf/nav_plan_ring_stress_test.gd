extends GameTest
## Performance guard: the AI's planning queries inside the match building and its ring are cheap
## on a district (#182). The server scans every polygon of a map to place a query's two ends, so
## on the district's thousand-polygon map a route costs ~54 us and a snap ~15 us against a lone
## house's 11 us and 3.4 us, and a decision makes hundreds of them; the district has a planning
## ring, a map of the match building and its outdoor ring that these are answered from
## (`navigation/plan_ring_answers_like_the_district`). Baseline: ~16 ms for the 360 queries asked
## of the district map, ~4 ms from the ring. Budget 2x the ring's, half the district map's.
## 2026-11-06, #192 (quiet, load 3.5 to 3.9, two runs): 3.8 and 4.6 ms from the ring (the base
## commit, same machine: 3.5). The route cache would answer a repeat at once, so each round also
## nudges the route ends: the guard still measures the server's queries. The budget stands at 2x.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const ROUNDS := 30
## Each round nudges every point by this much (px) so neither a snap nor a route is one asked
## before: both remember exact repeats, and this guard measures the raw server queries.
const NUDGE := 0.37
const BUDGET_MS := 8.0


func describe() -> Dictionary:
	return {
		"name": "Planning in a district's match building is cheap",
		"description": "Routes between the match building's room centres and snaps of points "
			+ "round them are asked of the planning map; the wall time of all of them stays "
			+ "within budget.",
		"tags": ["navigation", "path", "perf"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.district(424_242)
	s.switch(&"nav.rebake", false)
	s.actor(&"p", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the first bake is applied a frame or two after the build
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var map := region.get_navigation_map()
	if not t.require(NavBuilder.ready(map), "premise: the planning map answers"):
		return
	var points: Array[Vector2] = []
	for room: Dictionary in WorldGen.get_rooms(t.world.house):
		points.append((room["rect"] as Rect2).get_center())
	if not t.require(points.size() >= 3, "the match building has rooms to plan between"):
		return
	if not t.require(
		NavRing.map_for(map, points) == NavRing.map_of(map),
		"premise: the rooms' centres are weighed on the planning ring",
	):
		return
	var ms := Perf.time_ms(func():
		for round_index in ROUNDS:
			var nudge := Vector2(NUDGE, NUDGE) * round_index
			for a in points:
				NavBuilder.snap(map, a + nudge)
				for b in points:
					NavBuilder.route(map, a + nudge, b + nudge))
	var asked := ROUNDS * points.size() * (points.size() + 1)
	Perf.within(t, "%d routes and snaps inside the ring" % asked, ms, BUDGET_MS)
