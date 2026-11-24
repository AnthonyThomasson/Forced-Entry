class_name NavQueryProbe
extends RefCounted
## #194 nav3d-b: the same plan polygon on two scratch maps, one through the 2D API (a
## `NavigationServer2D` region on map A) and one through the nav's own path (`NavPlan.assign` on a
## `NavigationRegion3D` on map B, queried through `NavPlan`), and their closest points and routes
## compared (`navigation/nav3d_plan_polygon_matches_2d*`). The two servers share an engine
## underneath, so what is under test is what the nav adds: the mesh `NavPlan.mesh_of` makes of a
## plan polygon (its vertices lifted to the floor, its cell, its polygons), the region and the map's
## settings.

## Probes a side of the grid laid over the polygon's bounds.
const GRID := 9
## The pairs' stride through the ordered pairs of probes.
const STRIDE := 37
## The most two answers may differ (px): none.
const SAME := 0.001


## Lay `map`'s planning region's polygon on two scratch maps, wait for both, compare, free them.
static func compare(t: TestContext, label: String, map: RID) -> void:
	var region := NavBuilder.planning_region(map)
	if not t.require(region != null, "%s: a planning region stands on the map" % label):
		return
	var poly := NavPlan.polygon_of(region)
	var a := NavigationServer2D.map_create()  # a 2D map, on the 2D server's cell height
	NavigationServer2D.map_set_cell_size(a, NavSource.CELL_SIZE)
	NavigationServer2D.map_set_active(a, true)
	var region_a := NavigationServer2D.region_create()
	NavigationServer2D.region_set_map(region_a, a)
	NavigationServer2D.region_set_navigation_polygon(region_a, poly)
	var b := NavSource.new_map()
	var region_b := NavigationRegion3D.new()
	region_b.set_navigation_map(b)
	t.world.add_child(region_b)
	NavPlan.assign(region_b, poly)
	var synced := await t.until(
		func(): return (
			NavigationServer2D.map_get_iteration_id(a) != 0 and NavPlan.iteration(b) != 0
		),
		3.0,
	)
	if t.require(synced, "%s: both scratch maps took the polygon in" % label):
		_check(t, label, a, b, _probes(poly))
	region_b.queue_free()
	NavigationServer2D.free_rid(region_a)
	NavigationServer2D.free_rid(a)
	NavigationServer3D.free_rid(b)


static func _check(
	t: TestContext, label: String, a: RID, b: RID, probes: Array[Vector2],
) -> void:
	var worst_snap := 0.0
	for p in probes:
		var old := NavigationServer2D.map_get_closest_point(a, p)
		worst_snap = maxf(worst_snap, old.distance_to(NavPlan.closest(b, p)))
	var routes := _worst_route(a, b, probes)
	t.check(
		worst_snap <= SAME,
		"%s: %d closest points agree (worst %.4f px)" % [label, probes.size(), worst_snap],
	)
	t.check(
		routes[0] <= SAME and routes[2] > 2,
		"%s: %d routes agree, some bent (worst %.4f px, longest %d points)"
			% [label, routes[1], routes[0], routes[2]],
	)


## `[worst difference, routes asked, most points of a route]` over a stride of ordered pairs.
static func _worst_route(a: RID, b: RID, probes: Array[Vector2]) -> Array:
	var worst := 0.0
	var asked := 0
	var longest := 0
	var pair := 0
	for from in probes:
		for to in probes:
			pair += 1
			if pair % STRIDE != 0:
				continue
			asked += 1
			var old := NavigationServer2D.map_get_path(a, from, to, true)
			var now := NavPlan.path(b, from, to)
			longest = maxi(longest, old.size())
			if old.size() != now.size():
				worst = INF
				continue
			for k in old.size():
				worst = maxf(worst, old[k].distance_to(now[k]))
	return [worst, asked, longest]


## A grid of probe points over the polygon's box.
static func _probes(poly: NavigationPolygon) -> Array[Vector2]:
	var box := Rect2(poly.vertices[0], Vector2.ZERO)
	for v in poly.vertices:
		box = box.expand(v)
	var out: Array[Vector2] = []
	for i in GRID:
		for j in GRID:
			out.append(box.position + box.size * Vector2((i + 0.5) / GRID, (j + 0.5) / GRID))
	return out
