extends GameTest
## The nav bake reads the 3D twins (#194 del2d-c, ADR 0014: the floor-plan polygons their shapes
## stand on, `NavTwins`), where it read the 2D colliders, and the 2D colliders of the walls are gone
## (del2d-c2), so the old bake can no longer be run beside the new. What it read then was recorded
## at b2777f4b, where both could (`tests/_navigation/bake_baseline.gd`: the district of seed 7 and
## the house of seed 1, plan `garage_home`, with their tolerances), and this measures the bake from
## the twins against that record, and against the walls' own outlines, which need no record.
##
## What the record holds, and the bake from the twins reproduces (district seed 7: 341 holes, 277
## wall outlines; and the house): the walls are the same outlines (the same count, the same bounds
## and summed area, a lintel over a doorway left out, so the doorways stay open), as the world
## stands and after a wall is shot up; the holes are the same count and, but for a piece hung on a
## wall (a menu board, a mirror, a towel rail: its twin has about half its 2D collider's depth), the
## same area to a pixel (`_check_holes`), so the area is within `AREA_SHARE`; the navmesh has the
## recorded area to `MESH_SHARE` and a polygon more or fewer; and every one of the recorded 90
## routes the old map found, the new one finds, within `ROUTE_LONGER` and `ROUTE_SHORTER` of its
## length.
##
## What the record does not need (`_check_wall_truth`, from the walls' own outlines): each outline
## a `Wall` holds, in the house's frame, is one the bake has, and the bake has no other; the navmesh
## keeps the agent's radius from each; every doorway of a wall is open on it.

const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const Baseline := preload("res://tests/_navigation/bake_baseline.gd")
const WallScript := preload("res://scenes/objects/wall/wall.gd")
const SEED := 7
const RADIUS := NavBuilder.AGENT_RADIUS
## How far (px) a wall's corner may be from the record's or the wall's own: the twin's float
## rounding and the 1 px grid.
const WALL_GRID := 1.0
## The most the holes' area may differ (share of the recorded one's) and the most the navmesh's
## area may differ (share). The mesh is baked on a 4 px grid (#194 nav3d-a, D16): a cell is held or
## walkable by where its centre lies and the contours are simplified to 0.8 cells, so its edges
## stand up to a cell off the 1 px record's: measured +0.7% (district), +1.9% (house).
const AREA_SHARE := 0.02
const MESH_SHARE := 0.025
## How much longer and how much shorter than the recorded length a route may be (share). The record
## is of paths over the 2D baker's few large convex polygons, which the map's search takes through
## their edges' midpoints; the voxel baker's watershed regions give smaller polygons, a search that
## follows the floor more closely: measured longest +1.7%, shortest -7.3% (district), and no route
## is lost.
const ROUTE_LONGER := 0.03
const ROUTE_SHORTER := 0.08
## How many times the recorded polygon count the navmesh may hold (at least as many): the baker
## cuts the floor into regions and triangulates them (measured x2.9 district, x3.4 house).
const POLYGON_RATIO := 3.5
## What a pixel of area is: the summed areas of the same outlines agree to this.
const AREA_EPSILON := 1.0
## The walls of a district's shells (a tower's outside: scenery with no walkable inside), whose
## doorways open on nothing the navmesh holds.
const SCENERY_WALLS := "Partition"
## The pieces hung on a wall, whose twin is about half as deep as their 2D collider: the only ones
## whose hole is not the recorded one's (a name starts with one of these).
const HUNG: Array[String] = ["Menu Board", "Mirror", "Towel"]
## How far (px) under the agent's radius a navmesh vertex may be from a wall: the 1 px grid, and the
## weld that moves a vertex onto its neighbour.
const CLEARANCE_SLACK := 2.0
## How far (px) from a wall the navmesh's vertices are looked at: the bake's radius and margin.
const REACH := RADIUS + NavBuilder.WALL_MARGIN + CLEARANCE_SLACK
## How far (px) from a doorway's middle the navmesh must hold a point.
const DOORWAY_REACH := 2.0


func describe() -> Dictionary:
	return {
		"name": "A bake from the twins matches the recorded bake from the colliders (district)",
		"description": "The district's walls, holes, navmesh and routes baked from the twins "
			+ "against what the 2D colliders gave at b2777f4b, and the walls against their own "
			+ "outlines: the same walls, doorways open, a navmesh within a fraction of a percent "
			+ "of the area, every route found and within a few percent of its length.",
		"tags": ["navigation", "bake", "district", "twins"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)
	# The record is of the bare world the old colliders baked (before items stood on tops and
	# floors, D20): its figures are that world's, and it cannot be re-recorded from the colliders
	# any more.
	s.switch(&"worldgen.items", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var root := _root(t)
	var site := _site(t, root)
	var record := _record()
	var walls := NavSource.walls_of(root)
	_check_walls(t, walls["obstruction"], record["walls"], "as the world stands")
	_check_wall_truth(t, root, walls["obstruction"], "as the world stands")
	var holes := NavBuilder.furniture_holes(root)
	var chars := NavBuilder.character_holes(root.get_parent())
	_check_holes(t, root, holes + chars, record["holes"])
	var poly := NavSource.bake(NavSource.job(site, holes, chars, walls), root.position)
	_check_mesh(t, poly, record["mesh"])
	_check_clearance(t, poly, walls["obstruction"])
	var map := _map_of(poly, root.position)
	_check_routes(t, map, record["routes"])
	_free_map(map)
	var bare := _map_of(
		NavSource.bake(NavSource.job(site, [], [], walls), root.position),
		root.position,
	)
	_check_doorways(t, root, bare)
	_free_map(bare)
	await _extras(t, root)


## What a world adds to the comparison beyond its own pieces: a wall shot up (its twin is cut from
## the dents), the walls as the record has them after it.
func _extras(t: TestContext, root: Node2D) -> void:
	var wall: Node2D = null
	for node in NavTwins.walls_under(root):
		wall = node
		break
	if not t.require(wall != null, "premise: the world has a wall"):
		return
	var seg: PackedVector2Array = wall.wall_segments()[0]
	for k in 4:
		var hit := HitInfo.new()
		hit.position = wall.to_global(seg[0].lerp(seg[1], 0.2 + 0.15 * k))
		hit.normal = (seg[1] - seg[0]).normalized().orthogonal()
		hit.direction = -hit.normal
		hit.damage = 40.0
		hit.speed_factor = 1.0
		wall.take_hit(hit)
	await t.frames(3)  # the wall's twin is rebuilt from the dents
	var walls := NavSource.walls_of(root)
	_check_walls(t, walls["obstruction"], _record()["shot"], "after a wall is shot up")
	_check_wall_truth(t, root, walls["obstruction"], "after a wall is shot up")


## The recorded figures of this world.
func _record() -> Dictionary:
	return Baseline.DISTRICT


## The node the bake parses: the district, or the house.
func _root(t: TestContext) -> Node2D:
	return t.world.get("district") as Node2D


func _site(_t: TestContext, root: Node2D) -> NavSite:
	return NavSite.new(
		root, WorldGen.district_rooms(root), RADIUS, WorldGen.district_bounds(root),
	)


## The walls against the record: as many outlines, with the recorded bounds and summed area.
func _check_walls(t: TestContext, now: Array, recorded: Dictionary, when: String) -> void:
	var box := Rect2()
	for i in now.size():
		var outline_box := NavSource.outline_bounds(now[i])
		box = outline_box if i == 0 else box.merge(outline_box)
	var bounds: Array = recorded["bounds"]
	var want := Rect2(bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1])
	t.check(
		now.size() == recorded["count"]
			and absf(_area(now) - float(recorded["area"])) <= AREA_EPSILON
			and box.position.distance_to(want.position) <= WALL_GRID
			and box.end.distance_to(want.end) <= WALL_GRID,
		("the walls are the 2D parse's, %s (%d outlines, %d recorded; area %.1f, %.1f recorded; "
			+ "bounds %s, %s recorded)") % [
				when, now.size(), recorded["count"], _area(now), recorded["area"], box, want,
			],
	)


## The walls against their own outlines, which no record holds: each outline a wall holds (its
## segments' pieces, in the house's frame) is one of the bake's within `WALL_GRID` corner by
## corner, and the bake has no other. A dented segment is cut into pieces the twin may cut
## otherwise, so the pieces without a partner on either side must cover the same ground: what only
## one covers is under a grid's width round their edges (`_unshared_area`).
func _check_wall_truth(t: TestContext, root: Node2D, now: Array, when: String) -> void:
	var truth := _wall_outlines(root)
	var buckets := {}
	for outline: PackedVector2Array in now:
		var key := _bucket(outline)
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(outline)
	var used := {}
	var lone_truth: Array = []
	for outline: PackedVector2Array in truth:
		var partner := _partner(outline, buckets, used)
		if partner.is_empty():
			lone_truth.append(outline)
		else:
			used[partner] = true
	var lone_bake: Array = now.filter(
		func(ring: PackedVector2Array) -> bool: return not used.has(ring)
	)
	var unshared := _unshared_area(lone_truth, lone_bake)
	var slack := WALL_GRID * 0.5 * (_perimeter(lone_truth) + _perimeter(lone_bake))
	t.require(truth.size() > 5, "premise: the walls hold outlines (%d)" % truth.size())
	t.check(
		truth.size() - lone_truth.size() == used.size() and unshared <= slack,
		("the bake's walls are the walls' own outlines, %s (%d outlines, %d in the bake; %d and "
			+ "%d left without a partner, which cover %.1f px² on one side only, of %.1f allowed)")
			% [
				when,
				truth.size(),
				now.size(),
				lone_truth.size(),
				lone_bake.size(),
				unshared,
				slack,
			],
	)
	t.check(
		truth.size() == now.size(),
		"as many outlines in the bake as the walls hold (%d, %d)" % [now.size(), truth.size()],
	)


## The ring among `buckets` (by `_bucket`) that is `outline`'s partner and is not `used`, else an
## empty one.
func _partner(
	outline: PackedVector2Array,
	buckets: Dictionary,
	used: Dictionary,
) -> PackedVector2Array:
	var key := _bucket(outline)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for ring: PackedVector2Array in buckets.get(key + Vector2i(dx, dy), []):
				if not used.has(ring) and _same_corners(outline, ring):
					return ring
	return PackedVector2Array()


## The area covered by the outlines `a` or by the outlines `b`, but not by both.
func _unshared_area(a: Array, b: Array) -> float:
	var union_a := _union(a)
	var union_b := _union(b)
	return _area(_minus(union_a, union_b)) + _area(_minus(union_b, union_a))


## `rings` merged into the outlines of the ground they cover.
func _union(rings: Array) -> Array:
	var out: Array = []
	for ring: PackedVector2Array in rings:
		var merged := ring
		var rest: Array = []
		for other: PackedVector2Array in out:
			var both := Geometry2D.merge_polygons(merged, other)
			if both.size() == 1 and not Geometry2D.is_polygon_clockwise(both[0]):
				merged = both[0]
			else:
				rest.append(other)
		rest.append(merged)
		out = rest
	return out


## The ground of `from` that `taken` does not cover.
func _minus(from: Array, taken: Array) -> Array:
	var left: Array = from.duplicate()
	for ring: PackedVector2Array in taken:
		var next: Array = []
		for piece: PackedVector2Array in left:
			next.append_array(Geometry2D.clip_polygons(piece, ring))
		left = next
	return left.filter(
		func(ring: PackedVector2Array) -> bool: return not Geometry2D.is_polygon_clockwise(ring)
	)


func _perimeter(rings: Array) -> float:
	var sum := 0.0
	for ring: PackedVector2Array in rings:
		for i in ring.size():
			sum += ring[i].distance_to(ring[(i + 1) % ring.size()])
	return sum


## The outline of every segment of every wall under `root`, in `root`'s frame.
func _wall_outlines(root: Node2D) -> Array:
	var out: Array = []
	var into := root.global_transform.affine_inverse()
	for wall in NavTwins.walls_under(root):
		var frame: Transform2D = into * (wall as Node2D).global_transform
		for outlines: Array in (wall.segment_shapes() as Dictionary).values():
			for outline: PackedVector2Array in outlines:
				out.append(frame * outline)
	return out


## The navmesh keeps the agent's radius off every wall: no vertex of it is nearer an outline than
## the radius (less the grid's slack), a vertex inside one least of all.
func _check_clearance(t: TestContext, poly: NavigationPolygon, walls: Array) -> void:
	var near := 0
	var least := INF
	var grown: Array[Rect2] = []
	for outline: PackedVector2Array in walls:
		grown.append(NavSource.outline_bounds(outline).grow(REACH))
	for vertex in poly.get_vertices():
		for i in walls.size():
			if not grown[i].has_point(vertex):
				continue
			var gap := _distance(vertex, walls[i])
			least = minf(least, gap)
			if gap < RADIUS - CLEARANCE_SLACK:
				near += 1
	t.require(least < INF, "premise: navmesh vertices stand within the radius of the walls")
	t.check(
		near == 0,
		("the navmesh keeps the agent's radius off the walls (%d of its vertices nearer; nearest "
			+ "%.1f px, radius %.0f)") % [near, least, RADIUS],
	)


## Every doorway a wall owns is open on a map baked from the walls alone (no furniture to stand in
## one): it holds the doorway's middle.
func _check_doorways(t: TestContext, root: Node2D, map: RID) -> void:
	NavigationServer2D.map_force_update(map)
	var shut: Array[String] = []
	var doorways := 0
	for wall in NavTwins.walls_under(root):
		if String(wall.name).begins_with(SCENERY_WALLS):
			continue
		for gap: Dictionary in wall.openings:
			if wall.opening_is_shared(gap):
				continue
			doorways += 1
			var at := _doorway_middle(wall, gap)
			var held := NavigationServer2D.map_get_closest_point(map, at)
			if held.distance_to(at) > DOORWAY_REACH:
				shut.append("%s at %s" % [wall.name, at])
	t.require(doorways > 0, "premise: the world has doorways (%d)" % doorways)
	t.expect_eq(shut.size(), 0, "every doorway is open on the navmesh: %s shut" % [shut])


## The world point of the middle of the doorway `gap` of `wall`.
func _doorway_middle(wall: Node2D, gap: Dictionary) -> Vector2:
	var offset: float = gap["offset"]
	var size: Vector2 = wall.size
	var local := Vector2.ZERO
	match int(gap["side"]):
		WallScript.Side.TOP:
			local = Vector2(offset, 0.0)
		WallScript.Side.BOTTOM:
			local = Vector2(offset, size.y)
		WallScript.Side.LEFT:
			local = Vector2(0.0, offset)
		_:
			local = Vector2(size.x, offset)
	return wall.to_global(local)


## The bucket (a grid of 32 px) the middle of the corners of `outline` is in.
func _bucket(outline: PackedVector2Array) -> Vector2i:
	var sum := Vector2.ZERO
	for p in outline:
		sum += p
	return Vector2i((sum / outline.size() / 32.0).floor())


## Whether every corner of `a` has a corner of `b` within `WALL_GRID` and the other way: the
## corners proper, a vertex on the line between its neighbours being no corner (a dented wall's
## outline keeps such vertices, its twin's hull does not).
func _same_corners(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var ca := _corners(a)
	var cb := _corners(b)
	for p in ca:
		if _gap(p, cb) > WALL_GRID:
			return false
	for p in cb:
		if _gap(p, ca) > WALL_GRID:
			return false
	return true


## `ring` without the vertices that lie (to the grid's pixel) on the line between their neighbours.
func _corners(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in ring.size():
		var before := ring[(i - 1 + ring.size()) % ring.size()]
		var after := ring[(i + 1) % ring.size()]
		var along := before.distance_to(after)
		if along < 0.001 or absf((ring[i] - before).cross(after - before)) / along > WALL_GRID:
			out.append(ring[i])
	return out


func _gap(point: Vector2, ring: PackedVector2Array) -> float:
	var least := INF
	for q in ring:
		least = minf(least, point.distance_to(q))
	return least


## The distance from `point` to the polygon `ring` (0 inside it).
func _distance(point: Vector2, ring: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, ring):
		return 0.0
	var least := INF
	for i in ring.size():
		var closest := Geometry2D.get_closest_point_to_segment(
			point, ring[i], ring[(i + 1) % ring.size()],
		)
		least = minf(least, point.distance_to(closest))
	return least


## The holes: the same number as the record's, within `AREA_SHARE` of its area, and the pieces not
## hung on a wall the same to a pixel (the whole difference is the hung pieces' shallower twins).
func _check_holes(t: TestContext, root: Node2D, now: Array, recorded: Dictionary) -> void:
	var before: float = recorded["area"]
	var after := _area(now)
	t.check(
		now.size() == recorded["count"],
		"as many holes as recorded (%d recorded, %d now)" % [recorded["count"], now.size()],
	)
	t.check(
		absf(after - before) <= before * AREA_SHARE,
		"the holes' area is within %d%% of the record (%.0f px² recorded, %.0f px² now)"
			% [int(AREA_SHARE * 100.0), before, after],
	)
	var hung := 0
	var hung_area := 0.0
	for body: Node2D in PlanProbe.pieces_under(root):
		if HUNG.any(func(prefix: String) -> bool: return String(body.name).begins_with(prefix)):
			hung += 1
			hung_area += _area([NavHoles.cut(body)])
	var rest_before: float = before - float(recorded["hung_area"])
	var rest_after := after - hung_area
	t.check(
		hung == recorded["hung_count"] and absf(rest_after - rest_before) <= AREA_EPSILON,
		("but for the %d hung pieces the holes are the recorded ones (%.1f px² recorded, %.1f now; "
			+ "the hung pieces' %.0f px² were %.0f)") % [
				hung, rest_before, rest_after, hung_area, recorded["hung_area"],
			],
	)


func _area(rings: Array) -> float:
	var sum := 0.0
	for ring: PackedVector2Array in rings:
		sum += absf(_signed(ring))
	return sum


func _signed(ring: PackedVector2Array) -> float:
	var sum := 0.0
	for i in ring.size():
		sum += ring[i].cross(ring[(i + 1) % ring.size()])
	return sum * 0.5


## The navmesh: its area within `MESH_SHARE` of the record's, and up to `POLYGON_RATIO` times its
## polygons.
func _check_mesh(t: TestContext, poly: NavigationPolygon, recorded: Dictionary) -> void:
	var before: float = recorded["area"]
	var after := _mesh_area(poly)
	t.check(
		absf(after - before) <= before * MESH_SHARE,
		"the navmesh's area is within %.1f%% of the record (%.0f px² recorded, %.0f px² now)"
			% [MESH_SHARE * 100.0, before, after],
	)
	t.check(
		(
			poly.get_polygon_count() >= int(recorded["polygons"])
			and poly.get_polygon_count() <= float(recorded["polygons"]) * POLYGON_RATIO
		),
		"the navmesh has from 1 to %.1f times the recorded polygons (%d recorded, %d now)"
			% [POLYGON_RATIO, recorded["polygons"], poly.get_polygon_count()],
	)


func _mesh_area(poly: NavigationPolygon) -> float:
	var vertices := poly.get_vertices()
	var sum := 0.0
	for i in poly.get_polygon_count():
		var ring := PackedVector2Array()
		for index in poly.get_polygon(i):
			ring.append(vertices[index])
		sum += absf(_signed(ring))
	return sum


## The recorded routes (`[from.x, from.y, to.x, to.y, length]`, on the old map) on the new map:
## each is found, within `ROUTE_LONGER` / `ROUTE_SHORTER` of its recorded length.
func _check_routes(t: TestContext, map: RID, routes: Array) -> void:
	NavigationServer2D.map_force_update(map)
	var missing := 0
	var longest := -INF
	var shortest := INF
	for route: Array in routes:
		var from := Vector2(route[0], route[1])
		var to := Vector2(route[2], route[3])
		var after := _length(map, from, to)
		if after <= 0.0:
			missing += 1
			continue
		var share: float = (after - float(route[4])) / float(route[4])
		longest = maxf(longest, share)
		shortest = minf(shortest, share)
	t.require(routes.size() >= 40, "premise: routes are recorded (%d)" % routes.size())
	t.check(
		missing == 0 and longest <= ROUTE_LONGER and shortest >= -ROUTE_SHORTER,
		("every recorded route is found, no more than %d%% longer and %d%% shorter (%d routes: "
			+ "%d missing, longest %+.1f%%, shortest %+.1f%%)") % [
				int(ROUTE_LONGER * 100.0), int(ROUTE_SHORTER * 100.0), routes.size(), missing,
				longest * 100.0, shortest * 100.0,
			],
	)


## Free a map `_map_of` made and its region.
func _free_map(map: RID) -> void:
	NavigationServer2D.free_rid(NavigationServer2D.map_get_regions(map)[0])
	NavigationServer2D.free_rid(map)


## A map of its own holding the navmesh `poly` at `origin`.
func _map_of(poly: NavigationPolygon, origin: Vector2) -> RID:
	var map := NavSource.new_map()
	var region := NavigationServer2D.region_create()
	NavigationServer2D.region_set_map(region, map)
	NavigationServer2D.region_set_transform(region, Transform2D(0.0, origin))
	NavigationServer2D.region_set_navigation_polygon(region, poly)
	return map


## The length of the path from `from` to `to` on `map` (the ends moved onto it), 0 for none.
func _length(map: RID, from: Vector2, to: Vector2) -> float:
	var start := NavigationServer2D.map_get_closest_point(map, from)
	var end := NavigationServer2D.map_get_closest_point(map, to)
	var path := NavigationServer2D.map_get_path(map, start, end, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length
