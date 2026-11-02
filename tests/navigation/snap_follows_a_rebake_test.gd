extends GameTest
## `NavBuilder.snap` answers the same point from what it learned while the map stands
## (`perf/nav_snap_repeat_stress`), and from the map afresh once it is re-baked: a point that
## snapped out of a chair's footprint stands where it is when the chair is gone.

const SPOT := Vector2(300, 200)


func describe() -> Dictionary:
	return {
		"name": "A snapped point follows a re-bake",
		"description": "A point in a chair's footprint snaps off it; with the chair moved away and "
			+ "the map re-baked the same point snaps to itself.",
		"tags": ["navigation", "path"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", SPOT)


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the first bake is applied a frame or two after the build
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var map := region.get_navigation_map()
	if not t.require(NavBuilder.ready(map), "premise: the map answers"):
		return
	var blocked := NavBuilder.snap(map, SPOT)
	if not t.require(
		blocked.distance_to(SPOT) > 5.0,
		"premise: the chair's footprint is carved (%s)" % blocked,
	):
		return
	t.expect_eq(
		NavBuilder.snap(map, SPOT),
		blocked,
		"the same point snaps the same while the map stands",
	)
	t.object(&"chair").global_position = Vector2(100, 100)
	NavBuilder.rebake(region, t.world.house, t.rooms)
	t.check(
		await t.until(func(): return NavBuilder.snap(map, SPOT).distance_to(SPOT) < 1.0, 2.0),
		"with the chair gone and the map re-baked the point snaps to itself",
	)
