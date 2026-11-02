extends GameTest
## A lone house (no district) keeps one planning map (#182): there is no ring region or ring map,
## and a query is weighed on the world's map wherever the point lies, as before the ring.


func describe() -> Dictionary:
	return {
		"name": "A lone house keeps one planning map",
		"description": "An arena has no ring map or region; a snap and a route are the world "
			+ "map's.",
		"tags": ["navigation", "path"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var map := region.get_navigation_map()
	if not t.require(NavBuilder.ready(map), "premise: the map answers"):
		return
	t.check(NavRing.region_of(region) == null, "no ring region")
	t.check(not NavRing.map_of(map).is_valid(), "no ring map")
	var a := Vector2(100, 100)
	var b := Vector2(500, 300)
	t.check(NavRing.map_for(map, [a, b]) == map, "a query is weighed on the world map")
	t.expect_eq(
		NavBuilder.route(map, a, b),
		NavigationServer2D.map_get_path(map, a, b, true),
		"a route is the world map's",
	)
