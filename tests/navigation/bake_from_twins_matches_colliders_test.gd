extends GameTest
## The nav bake reads the 3D twins (#194 del2d-c, ADR 0014: the floor-plan polygons their shapes
## stand on, `NavTwins`), where it read the 2D colliders. The two are not the same outlines: a
## piece's hole is the hull of its parts' footprints (a piece hung on a wall has the depth of its
## twin), and a dent changes the 2D collider but not the twin. This
## measures what that moves on a district (this test) and on houses (the subclasses): the new bake
## against the old on the same world, the old one made from the 2D colliders as they were read
## (`tests/_navigation/collider_reference.gd`).
##
## What moves, measured on a district (seed 7: 341 holes) and a house: the walls are the same
## outlines (the same count, each within a pixel of one the 2D parse found; a lintel over a doorway
## is left out, so the doorways stay open); the holes are the same count and, but for a piece hung
## on a wall (a menu board, a mirror, a towel rail), the same outlines (a round piece is the bake's
## 10-sided polygon, as the 2D circle was): a hung piece carves the depth its twin has, about half
## its 2D collider's, so the holes' area is 0.9% under (the house's 0.3%); the navmesh has the same
## area (+0.1%) and a polygon fewer (889 old, 888 new); and every route the old map found, the new
## one finds, within `ROUTE_SHARE` of its length (measured over 90 routes: none lost, none over 3%,
## the longest +0.0% and the shortest -2.6%, all of them the hung pieces' holes:
## `_check_hung_account_for_routes`).

const Reference := preload("res://tests/_navigation/collider_reference.gd")
const SEED := 7
const RADIUS := NavBuilder.AGENT_RADIUS
## How far (px) a wall's corner may be from the 2D parse's: the twin's float rounding and the 1 px
## grid.
const WALL_GRID := 1.0
## The most the holes' area may differ (share of the old one's), and the most a route may differ
## in length (share of the old one's), on the routes below.
const AREA_SHARE := 0.02
## The most the navmesh's area may differ, share of the old one's (measured +0.1%, the house
## +0.06%).
const MESH_SHARE := 0.005
const ROUTE_SHARE := 0.03
## How many routes are measured.
const ROUTES := 90
## The pieces hung on a wall, whose twin is about half as deep as their 2D collider: the only ones
## whose hole is not the old one's (a name starts with one of these).
const HUNG: Array[String] = ["Menu Board", "Mirror", "Towel"]
## What `_shares` reports for a route the new map does not find.
const MISSING := -1000.0


func describe() -> Dictionary:
	return {
		"name": "A bake from the twins matches a bake from the colliders (district)",
		"description": "The district's walls, holes, navmesh and routes baked from the twins "
			+ "against the 2D colliders': the same walls, a navmesh within a few percent of the "
			+ "area, every route found and within a few percent of its length.",
		"tags": ["navigation", "bake", "district", "twins"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var root := _root(t)
	var site := _site(t, root)
	var old_walls := Reference.walls(root, RADIUS)
	var new_walls := NavSource.walls_of(root)
	_check_walls(t, old_walls["obstruction"], new_walls["obstruction"])
	var old_holes := Reference.furniture(root)
	var new_holes := NavBuilder.furniture_holes(root)
	var old_chars := Reference.characters(root.get_parent())
	var new_chars := NavBuilder.character_holes(root.get_parent())
	_check_holes(t, old_holes + old_chars, new_holes + new_chars)
	_check_each_piece(t, root)
	var old_poly := NavSource.bake(
		NavSource.job(site, old_holes, old_chars, old_walls), root.position,
	)
	var new_poly := NavSource.bake(
		NavSource.job(site, new_holes, new_chars, new_walls), root.position,
	)
	_check_mesh(t, old_poly, new_poly)
	_check_routes(t, root, site, old_poly, new_poly)
	_check_hung_account_for_routes(t, root, site, old_poly, [new_holes, new_chars, new_walls])
	await _extras(t, root)


## What a world adds to the comparison beyond its own pieces: a wall shot up (its twin is cut from
## the same dents as its 2D collider, so the walls stay the 2D parse's).
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
	await t.frames(3)  # the wall's collider, and its twin, are rebuilt from the dents
	_check_walls(
		t, Reference.walls(root, RADIUS)["obstruction"], NavSource.walls_of(root)["obstruction"],
	)


## The node the bake parses: the district, or the house.
func _root(t: TestContext) -> Node2D:
	return t.world.get("district") as Node2D


func _site(_t: TestContext, root: Node2D) -> NavSite:
	return NavSite.new(
		root, WorldGen.district_rooms(root), RADIUS, WorldGen.district_bounds(root),
	)


## The walls: as many outlines, each of the old ones matched by a new one within `WALL_GRID` of
## it corner by corner (found by the bucket of its centre).
func _check_walls(t: TestContext, old: Array, now: Array) -> void:
	var buckets := {}
	for outline: PackedVector2Array in now:
		var key := _bucket(outline)
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(outline)
	var unmatched := 0
	for outline: PackedVector2Array in old:
		var found := false
		var key := _bucket(outline)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for ring: PackedVector2Array in buckets.get(key + Vector2i(dx, dy), []):
					found = found or _same_corners(outline, ring)
		if not found:
			unmatched += 1
	t.check(
		unmatched == 0 and old.size() == now.size(),
		"the walls are the 2D parse's (%d old outlines, %d new; %d of the old unmatched)"
			% [old.size(), now.size(), unmatched],
	)


## The bucket (a grid of 32 px) the middle of the corners of `outline` is in.
func _bucket(outline: PackedVector2Array) -> Vector2i:
	var sum := Vector2.ZERO
	for p in outline:
		sum += p
	return Vector2i((sum / outline.size() / 32.0).floor())


## Whether every corner of `a` has a corner of `b` within `WALL_GRID` and the other way: the
## corners proper, a vertex on the line between its neighbours being no corner (a dented wall's 2D
## parse keeps such vertices, its twin's hull does not).
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


## `ring` without the vertices that lie on the line between their neighbours.
func _corners(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in ring.size():
		var before := ring[(i - 1 + ring.size()) % ring.size()]
		var after := ring[(i + 1) % ring.size()]
		if absf((ring[i] - before).cross(after - ring[i])) > 0.5:
			out.append(ring[i])
	return out


func _gap(point: Vector2, ring: PackedVector2Array) -> float:
	var least := INF
	for q in ring:
		least = minf(least, point.distance_to(q))
	return least


## The holes: the same number, and the same total area to within `AREA_SHARE`.
func _check_holes(t: TestContext, old: Array, now: Array) -> void:
	var before := _area(old)
	var after := _area(now)
	t.check(
		old.size() == now.size(),
		"as many holes as before (%d old, %d new)" % [old.size(), now.size()],
	)
	t.check(
		absf(after - before) <= before * AREA_SHARE,
		"the holes' area is within %d%% of before (%.0f px² old, %.0f px² new)"
			% [int(AREA_SHARE * 100.0), before, after],
	)


## Each piece's own hole is the old one's, but for the pieces hung on a wall (`HUNG`).
func _check_each_piece(t: TestContext, root: Node2D) -> void:
	var differ: Array[String] = []
	for body: Node2D in root.find_children("*", "RigidBody2D", true, false):
		var old_hole := Reference.cut(body)
		var new_hole := NavHoles.cut(body)
		if old_hole.is_empty() and new_hole.is_empty():
			continue
		if old_hole.is_empty() or new_hole.is_empty() or not _same_corners(old_hole, new_hole):
			differ.append(String(body.name))
	var unexpected := differ.filter(
		func(piece_name: String) -> bool:
			return not HUNG.any(func(hung: String) -> bool: return piece_name.begins_with(hung))
	)
	t.check(
		unexpected.is_empty(),
		"each piece's hole is the old one's but for the hung ones (%d differ: %s)"
			% [differ.size(), differ],
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


## The navmesh of each: the polygon counts (what the bake and the server pay) and the walkable
## area.
func _check_mesh(t: TestContext, old: NavigationPolygon, now: NavigationPolygon) -> void:
	var before := _mesh_area(old)
	var after := _mesh_area(now)
	t.check(
		absf(after - before) <= before * MESH_SHARE,
		("the navmesh's area is within %.1f%% of before (%.0f px² old, %.0f px² new; polygons %d "
			+ "old, %d new)") % [
				MESH_SHARE * 100.0, before, after,
				old.get_polygon_count(), now.get_polygon_count(),
			],
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


## Routes between the rooms' centres on a map of each navmesh: every one the old map finds the new
## finds, within `ROUTE_SHARE` of its length (`_shares`).
func _check_routes(
	t: TestContext,
	root: Node2D,
	site: NavSite,
	old: NavigationPolygon,
	now: NavigationPolygon,
) -> void:
	var old_map := _map_of(old, root.position)
	var new_map := _map_of(now, root.position)
	var shares := _shares(old_map, new_map, site.rooms)
	var missing := shares.count(MISSING)
	var found := shares.filter(func(share: float) -> bool: return share != MISSING)
	var worst := 0.0
	for share: float in found:
		worst = maxf(worst, absf(share))
	t.require(shares.size() * 2 >= ROUTES, "premise: routes are measured (%d)" % shares.size())
	t.check(
		missing == 0 and worst <= ROUTE_SHARE,
		("every old route is found, within %d%% of its length (%d routes: %d missing, longest "
			+ "%+.1f%%, shortest %+.1f%%)") % [
				int(ROUTE_SHARE * 100.0), shares.size(), missing,
				found.max() * 100.0, found.min() * 100.0,
			],
	)
	for map in [old_map, new_map]:
		NavigationServer2D.free_rid(NavigationServer2D.map_get_regions(map)[0])
		NavigationServer2D.free_rid(map)


## What moved the routes is the hung pieces' holes alone: the new bake with those holes cut as
## before (`from_new`: its holes, its characters, its walls) gives every route the old map's length.
func _check_hung_account_for_routes(
	t: TestContext,
	root: Node2D,
	site: NavSite,
	old: NavigationPolygon,
	from_new: Array,
) -> void:
	var holes: Array = (from_new[0] as Array).duplicate()
	for body: Node2D in root.find_children("*", "RigidBody2D", true, false):
		if HUNG.any(func(hung: String) -> bool: return String(body.name).begins_with(hung)):
			var at := holes.find(NavHoles.cut(body))
			if at >= 0:
				holes[at] = Reference.cut(body)
	var poly := NavSource.bake(
		NavSource.job(site, holes, from_new[1], from_new[2]), root.position,
	)
	var old_map := _map_of(old, root.position)
	var map := _map_of(poly, root.position)
	var shares := _shares(old_map, map, site.rooms)
	t.check(
		not shares.is_empty() and shares.max() == 0.0 and shares.min() == 0.0,
		"with the hung pieces' holes as before, all %d routes are as long" % shares.size(),
	)
	for each in [old_map, map]:
		NavigationServer2D.free_rid(NavigationServer2D.map_get_regions(each)[0])
		NavigationServer2D.free_rid(each)


## How much longer (a share of the old length) the new map's route is than the old map's, for each
## route measured: `MISSING` for one the new map does not find. Each route runs between two rooms'
## centres, moved onto the old map and kept where the new map holds that point too (a centre inside
## a piece's hole is a different point on each).
func _shares(old_map: RID, new_map: RID, rooms: Array) -> Array:
	NavigationServer2D.map_force_update(old_map)
	NavigationServer2D.map_force_update(new_map)
	var out: Array = []
	for k in ROUTES:
		var n := rooms.size()
		var from: Vector2 = (rooms[(k * k * 3 + k) % n]["rect"] as Rect2).get_center()
		var to: Vector2 = (rooms[(k * 13 + k * k + 7) % n]["rect"] as Rect2).get_center()
		from = NavigationServer2D.map_get_closest_point(old_map, from)
		to = NavigationServer2D.map_get_closest_point(old_map, to)
		if (NavigationServer2D.map_get_closest_point(new_map, from).distance_to(from) > 1.0
				or NavigationServer2D.map_get_closest_point(new_map, to).distance_to(to) > 1.0):
			continue  # an end the new map does not hold (inside a hole of its own)
		var before := _length(old_map, from, to)
		var after := _length(new_map, from, to)
		if before > 0.0:
			out.append(MISSING if after <= 0.0 else (after - before) / before)
	return out


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
