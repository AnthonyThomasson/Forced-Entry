class_name NavQueryProbe
extends RefCounted
## #194 nav3d-b: asks a map's closest points and routes of the 2D server and of the 3D one
## (`navigation/nav3d_queries_match_2d*`).

## Probes a side of the grid laid over the map's bounds.
const GRID := 9
## The pairs' stride through the ordered pairs of probes.
const STRIDE := 37
## The most two answers may differ (px): none.
const SAME := 0.001


static func compare(t: TestContext, label: String, map: RID) -> void:
	if not t.require(NavBuilder.ready(map), "%s: the map is ready" % label):
		return
	var region := NavBuilder.planning_region(map)
	if not t.require(region != null, "%s: a planning region stands on the map" % label):
		return
	var bounds := _bounds(region)
	var probes: Array[Vector2] = []
	for i in GRID:
		for j in GRID:
			probes.append(bounds.position + bounds.size * Vector2(
				(i + 0.5) / GRID, (j + 0.5) / GRID,
			))
	var snaps := _worst_snap(map, probes)
	var routes := _worst_route(map, probes)
	t.check(
		snaps <= SAME,
		"%s: %d closest points agree (worst %.4f px)" % [label, probes.size(), snaps],
	)
	t.check(
		routes[0] <= SAME and routes[2] > 2,
		"%s: %d routes agree, some bent (worst %.4f px, longest %d points)"
			% [label, routes[1], routes[0], routes[2]],
	)


## The most the 3D server's closest point of a probe differs from the 2D server's.
static func _worst_snap(map: RID, probes: Array[Vector2]) -> float:
	var worst := 0.0
	for p in probes:
		var old := NavigationServer2D.map_get_closest_point(map, p)
		var now := _plan(NavigationServer3D.map_get_closest_point(map, _lift(p)))
		worst = maxf(worst, old.distance_to(now))
	return worst


## `[worst difference, routes asked, most points of a route]` over a stride of ordered pairs.
static func _worst_route(map: RID, probes: Array[Vector2]) -> Array:
	var worst := 0.0
	var asked := 0
	var longest := 0
	var pair := 0
	for a in probes:
		for b in probes:
			pair += 1
			if pair % STRIDE != 0:
				continue
			asked += 1
			var old := NavigationServer2D.map_get_path(map, a, b, true)
			var now := NavigationServer3D.map_get_path(map, _lift(a), _lift(b), true)
			longest = maxi(longest, old.size())
			if old.size() != now.size():
				worst = INF
				continue
			for k in old.size():
				worst = maxf(worst, old[k].distance_to(_plan(now[k])))
	return [worst, asked, longest]


static func _lift(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


static func _plan(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## The box of the region's mesh in world space.
static func _bounds(region: NavigationRegion2D) -> Rect2:
	var poly := region.navigation_polygon
	var box := Rect2(poly.vertices[0] + region.global_position, Vector2.ZERO)
	for v in poly.vertices:
		box = box.expand(v + region.global_position)
	return box
