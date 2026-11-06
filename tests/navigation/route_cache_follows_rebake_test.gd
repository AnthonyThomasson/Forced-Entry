extends GameTest
## `NavBuilder.route` keeps an exact answer only while every map that can supply it stands. A
## repeated route equals the original ring-and-fallback query and does not ask the server again;
## changing either the district or its ring starts that answer afresh. Freeing a world drops its
## remembered routes with it (#192 AC11).

const MainProbe := preload("res://tests/_main/main_probe.gd")
const ROUTES_SCRIPT := "res://scenes/navigation/nav_routes.gd"
const WAIT := 5.0


func describe() -> Dictionary:
	return {
		"name": "Cached routes follow every supplying map's re-bake",
		"description": "Exact route repeats equal the plain query without another server query; "
			+ "district and ring iterations each invalidate, including a fallback answer, and a "
			+ "destroyed map leaves no cache entry.",
		"tags": ["navigation", "path", "rebake", "district"],
		"timeout": 30.0,
	}


func run(t: TestContext) -> void:
	if not t.require(ResourceLoader.exists(ROUTES_SCRIPT), "the exact route memo exists"):
		return
	var routes := load(ROUTES_SCRIPT) as GDScript
	await _plain_map(t, routes)
	await _ring_fallback(t, routes)


## A lone house: the world map alone supplies the answer.
func _plain_map(t: TestContext, routes: GDScript) -> void:
	var fixture := await _fixture(t, Rect2(), Vector2(400, 300), Vector2(80, 200))
	var map: RID = fixture["map"]
	var from := Vector2(200, 300)
	var to := Vector2(600, 300)
	var expected := _plain_route(map, from, to)
	var before := _queries(routes)
	t.expect_eq(NavBuilder.route(map, from, to), expected, "the first plain route is uncached")
	t.check(_queries(routes) > before, "the first plain route asks the server")
	before = _queries(routes)
	t.expect_eq(NavBuilder.route(map, from, to), expected, "the repeated plain route is identical")
	t.expect_eq(_queries(routes), before, "the repeated plain route does not ask the server again")

	var region := fixture["region"] as NavigationRegion2D
	var house := fixture["house"] as Node2D
	(fixture["obstacle"] as Node2D).position = Vector2(400, 100)
	NavBuilder.rebake(region, house, fixture["rooms"])
	await t.seconds(0.3)
	var moved := _plain_route(map, from, to)
	t.check(moved != expected, "premise: moving the divider changes the plain route")
	before = _queries(routes)
	t.expect_eq(NavBuilder.route(map, from, to), moved, "a district re-bake is answered afresh")
	t.check(_queries(routes) > before, "the re-baked route asks the server again")
	await _destroyed(t, fixture["viewport"], routes, map)


## A district and ring: the divider spans the ring, so the district supplies the first answer.
func _ring_fallback(t: TestContext, routes: GDScript) -> void:
	var fixture := await _fixture(
		t, Rect2(0, 0, 1000, 1000), Vector2(400, 400), Vector2(800, 40),
	)
	var map: RID = fixture["map"]
	var ring := NavRing.map_of(map)
	var from := Vector2(400, 300)
	var to := Vector2(400, 500)
	if not t.require(
		not NavRing.keeps(ring, NavigationServer2D.map_get_path(ring, from, to, true), to),
		"premise: the divider makes the local route fall back to the district",
	):
		return
	var region := fixture["region"] as NavigationRegion2D
	var small := NavRing.region_of(region)
	fixture["old_district"] = region.navigation_polygon
	fixture["old_ring"] = small.navigation_polygon
	var expected := _plain_route(map, from, to)
	t.expect_eq(NavBuilder.route(map, from, to), expected, "the fallback's final route is cached")
	var before := _queries(routes)
	t.expect_eq(NavBuilder.route(map, from, to), expected, "the repeated fallback is identical")
	t.expect_eq(_queries(routes), before, "the repeated fallback asks neither map again")

	(fixture["obstacle"] as Node2D).position = Vector2(400, 550)
	NavBuilder.rebake(region, fixture["house"], fixture["rooms"])
	await t.seconds(0.3)
	var moved := _plain_route(map, from, to)
	t.check(moved != expected, "premise: opening the divider changes the fallback route")
	before = _queries(routes)
	t.expect_eq(NavBuilder.route(map, from, to), moved, "the re-baked fallback is answered afresh")
	t.check(_queries(routes) > before, "the re-baked fallback asks its supplying map again")

	# Put back only the district, then only the ring. Either iteration alone must miss the memo.
	region.navigation_polygon = fixture["old_district"]
	await t.frames(3)
	_fresh(t, routes, map, [from, to], "a district-only iteration")
	small.navigation_polygon = fixture["old_ring"]
	await t.frames(3)
	_fresh(t, routes, map, [from, to], "a ring-only iteration")
	await _destroyed(t, fixture["viewport"], routes, map)


## One changed map iteration: the answer still equals the plain query, asked of the server afresh.
func _fresh(
	t: TestContext, routes: GDScript, map: RID, ends: Array, label: String,
) -> void:
	var before := _queries(routes)
	t.expect_eq(
		NavBuilder.route(map, ends[0], ends[1]), _plain_route(map, ends[0], ends[1]), label,
	)
	t.check(_queries(routes) > before, "%s invalidates the route" % label)


## Build one divided house, with a district footprint and planning ring when `bounds` has area.
func _fixture(
	t: TestContext,
	bounds: Rect2,
	obstacle_at: Vector2,
	obstacle_size: Vector2,
) -> Dictionary:
	var viewport := MainProbe.viewport(t)
	var root := Node2D.new()
	viewport.add_child(root)
	var house := Node2D.new()
	root.add_child(house)
	var obstacle := RigidBody2D.new()
	obstacle.freeze = true
	obstacle.position = obstacle_at
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = obstacle_size
	collider.shape = shape
	obstacle.add_child(collider)
	house.add_child(obstacle)
	var rooms: Array = [{
		"key": "room", "type": "room", "rect": Rect2(200, 200, 400, 400),
	}]
	var region := NavBuilder.build(house, rooms, root, NavBuilder.AGENT_RADIUS, bounds)
	if bounds.has_area():
		NavBuilder.plan_ring(region, house, rooms)
	var map := region.get_navigation_map()
	t.require(
		await t.until(func(): return NavBuilder.ready(map), WAIT),
		"the fixture's maps answer",
	)
	return {
		"viewport": viewport, "house": house, "rooms": rooms, "region": region,
		"obstacle": obstacle, "map": map,
	}


## The route algorithm before exact memoization: ring first, district when the ring cannot keep it.
func _plain_route(map: RID, from: Vector2, to: Vector2) -> PackedVector2Array:
	var asked := NavRing.map_for(map, [from, to])
	var path := NavigationServer2D.map_get_path(asked, from, to, true)
	if asked != map and not NavRing.keeps(asked, path, to):
		path = NavigationServer2D.map_get_path(map, from, to, true)
	return path if path.size() >= 2 else PackedVector2Array([from, to])


func _queries(routes: GDScript) -> int:
	return int(routes.get("server_queries"))


func _destroyed(t: TestContext, viewport: SubViewport, routes: GDScript, map: RID) -> void:
	viewport.queue_free()
	await t.frames(2)
	var answers: Dictionary = routes.get("_answers")
	t.check(not answers.has(map), "the destroyed map leaves no remembered route")
