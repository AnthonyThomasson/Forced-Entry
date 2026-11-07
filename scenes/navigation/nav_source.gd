class_name NavSource extends RefCounted
## Navigation domain: what a bake is gathered from and how a gathered bake is run, the plumbing
## `NavBuilder`, `NavTiles`, `NavRing` and `NavRebake` share. A bake is a job, `{ poly, source }`:
## the polygon to bake into (the agent radius set) and its source geometry (the parsed walls, the
## walkable footprint and the furniture and character holes), gathered on the main thread. `bake`
## runs a job at once; `NavRebake` hands one to the server's worker thread. The parsed walls are a
## `walls` dictionary, `{ traversable, obstruction, projected }`, built only by `walls`.

## The box round an outline is this much (px) larger than the polygon, so outlines that merely touch
## still count as overlapping.
const BOUNDS_EPSILON := 0.5


## A parse's walls as the source takes them: the `obstruction` outlines (on the map's 1 px grid)
## and, beside them, the `traversable` outlines and `projected` obstructions the parse made.
static func walls(
	obstruction: Array,
	traversable: Array = [],
	projected: Array = [],
) -> Dictionary:
	return { "traversable": traversable, "obstruction": obstruction, "projected": projected }


## What a bake of `house` parses of it: its static colliders (the walls; RigidBody2D furniture, an
## anchored piece too, is not a StaticBody2D, so it is not parsed: the furniture is carved from its
## footprints), as `walls`, the obstructions snapped to the map's 1 px grid. The same for every bake
## of the house until a wall's collider changes, so `nav_updater.gd` parses once for a tick's two
## bakes. The doors under the house (the group `doors`) are left out: their leaves stand in the
## doorways, which stay open to the paths. `frame` places `house`'s own frame in its parent's (the
## obstructions are moved by it before they are snapped to the grid): a part of a larger house,
## parsed on its own.
static func walls_of(
	house: Node2D,
	agent_radius: float,
	frame := Transform2D.IDENTITY,
) -> Dictionary:
	var source := NavigationMeshSourceGeometryData2D.new()
	var doors := NavLeaves.doors_of(house)
	var layers: Array[int] = []
	for door in doors:
		layers.append(door.collision_layer)
		door.collision_layer = 0
	NavigationServer2D.parse_source_geometry_data(new_polygon(agent_radius), source, house)
	for i in doors.size():
		doors[i].collision_layer = layers[i]
	var obstruction: Array = source.get_obstruction_outlines()
	if frame != Transform2D.IDENTITY:
		var moved: Array = []
		for outline: PackedVector2Array in obstruction:
			moved.append(frame * outline)
		obstruction = moved
	return walls(
		on_grid(obstruction),
		source.get_traversable_outlines(),
		source.get_projected_obstructions(),
	)


## Everything a bake needs, gathered on the main thread: the polygon to bake into (`poly`, with the
## agent radius set) and its source geometry (`source`: the walls, the walkable footprint, the
## `furniture` holes (`NavBuilder.furniture_holes`) and each of `characters`). {} with no rooms.
## `walls` are the parsed walls (`walls_of`) when the caller has them this frame, else parsed here.
static func job(
	site: NavSite,
	furniture: Array,
	characters: Array = [],
	parsed: Dictionary = {},
) -> Dictionary:
	var baked := base(site, parsed)
	if not baked.is_empty():
		add_holes(baked["source"], site.house.position, furniture + characters)
	return baked


## A job (`job`) before its holes: the polygon to bake into and the source with the walls and the
## walkable footprint. {} with no rooms. The holes come after the footprint (both are outlines on
## the same source) and before the bake carves them in: `add_holes`, or `local_outlines`, a
## `NavUnion` and `finish_holes` for a gather done in steps (`NavGather`).
static func base(site: NavSite, parsed: Dictionary = {}) -> Dictionary:
	var house := site.house
	var bounds := bounds_of(site.rooms)
	if bounds.size == Vector2.ZERO:
		return {}
	bounds = site.bounds if site.bounds.has_area() else bounds.grow(NavBuilder.BOUNDS_PAD)
	# parse_source_geometry_data returns the wall colliders in `house`'s LOCAL frame, so the
	# footprint and the baked mesh live in that frame too; the region is then offset by the house's
	# position to place the whole map back in world space. Mixing world and local here is what
	# silently misaligns the walls and seals the doorways.
	var local_bounds := Rect2(bounds.position - house.position, bounds.size)
	var source := NavigationMeshSourceGeometryData2D.new()
	# Obstructions: the house's static colliders (walls). Setting the parsed outlines replaces the
	# source's lists, so it comes before the footprint is added.
	var walls_here := parsed if not parsed.is_empty() else walls_of(house, site.agent_radius)
	source.set_traversable_outlines(walls_here["traversable"])
	source.set_obstruction_outlines(walls_here["obstruction"])
	source.set_projected_obstructions(walls_here["projected"])
	# Walkable footprint: the whole house bounds. The parsed walls carve it, leaving the doorways.
	source.add_traversable_outline(rect_outline(local_bounds))
	return { "poly": new_polygon(site.agent_radius), "source": source }


## Add each of `footprints` (closed WORLD-space polygons) to `source` as an obstruction outline, so
## the baked navmesh has a hole there and paths route AROUND it. They are converted into the frame
## the bake runs in (world minus `origin`, the house's position) and fused before they go in, so a
## character against a piece of furniture or against another character is one outline.
static func add_holes(
	source: NavigationMeshSourceGeometryData2D,
	origin: Vector2,
	footprints: Array,
) -> void:
	finish_holes(source, NavUnion.fuse(local_outlines(origin, footprints)))


## `footprints` (closed WORLD-space polygons) in the frame the bake runs in: minus `origin`, the
## house's position.
static func local_outlines(origin: Vector2, footprints: Array) -> Array:
	var outlines: Array = []
	for outline in footprints:
		var local := PackedVector2Array()
		for p in outline:
			local.append(p - origin)
		outlines.append(local)
	return outlines


## Add `fused` (the fused `local_outlines`) to `source` as obstruction outlines: snapped to the 1 px
## grid and simplified.
static func finish_holes(source: NavigationMeshSourceGeometryData2D, fused: Array) -> void:
	for outline in on_grid(fused):
		source.add_obstruction_outline(simplified(outline))


## Bake a gathered job (`job`) at once, welded and without slivers (`NavWeld.finish`); `origin` is
## the region's offset.
static func bake(baked: Dictionary, origin: Vector2) -> NavigationPolygon:
	var nav_poly: NavigationPolygon = baked["poly"]
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, baked["source"])
	NavWeld.finish(nav_poly, origin)
	return nav_poly


## Keep what the planning bake was made from (its walkable outline, its obstructions and the agent
## radius) on `region`, with a version that counts the bakes, so an avoid map can be baked from it
## with more holes and knows when the furniture has moved.
static func remember(region: NavigationRegion2D, baked: Dictionary) -> void:
	var source: NavigationMeshSourceGeometryData2D = baked["source"]
	var poly: NavigationPolygon = baked["poly"]
	var version := 0
	if region.has_meta(NavBuilder.SOURCE_META):
		version = int((region.get_meta(NavBuilder.SOURCE_META) as Dictionary)["version"]) + 1
	region.set_meta(NavBuilder.SOURCE_META, {
		"traversable": source.get_traversable_outlines(),
		"obstructions": source.get_obstruction_outlines(),
		"agent_radius": poly.agent_radius - NavBuilder.WALL_MARGIN,
		"version": version,
	})


## A new active map with the project's 2D navigation defaults (what the world's own map is made
## with: a freshly made map has the 3D ones, and the server refuses a navmesh baked with another
## cell size).
static func new_map() -> RID:
	var map := NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(
		map,
		float(ProjectSettings.get_setting("navigation/2d/default_cell_size", 1.0)),
	)
	NavigationServer2D.map_set_edge_connection_margin(
		map,
		float(ProjectSettings.get_setting("navigation/2d/default_edge_connection_margin", 1.0)),
	)
	NavigationServer2D.map_set_link_connection_radius(
		map,
		float(ProjectSettings.get_setting("navigation/2d/default_link_connection_radius", 4.0)),
	)
	NavigationServer2D.map_set_use_edge_connections(
		map,
		bool(ProjectSettings.get_setting("navigation/2d/use_edge_connections", true)),
	)
	NavigationServer2D.map_set_active(map, true)
	return map


## An empty polygon to bake into, with the bake's agent radius (plus the wall margin).
static func new_polygon(agent_radius: float) -> NavigationPolygon:
	var nav_poly := NavigationPolygon.new()
	nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav_poly.agent_radius = agent_radius + NavBuilder.WALL_MARGIN
	return nav_poly


## The union of every room's world-space rect (zero-size Rect2 if `rooms` is empty).
static func bounds_of(rooms: Array) -> Rect2:
	var bounds := Rect2()
	var first := true
	for room in rooms:
		var rect: Rect2 = room["rect"]
		if first:
			bounds = rect
			first = false
		else:
			bounds = bounds.merge(rect)
	return bounds


## The four corners of `rect` as a closed outline, for the navigation baker.
static func rect_outline(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	])


## The box around `outline`, a hair larger than the polygon (`BOUNDS_EPSILON`) so outlines that
## merely touch still count as overlapping.
static func outline_bounds(outline: PackedVector2Array) -> Rect2:
	var box := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		box = box.expand(p)
	return box.grow(BOUNDS_EPSILON)


## `outlines` with every vertex snapped to the map's 1 px cell grid.
static func on_grid(outlines: Array) -> Array:
	var out: Array = []
	for outline in outlines:
		var snapped_outline := PackedVector2Array()
		for p in outline:
			var q: Vector2 = p.round()
			if snapped_outline.is_empty() or snapped_outline[snapped_outline.size() - 1] != q:
				snapped_outline.append(q)
		if (snapped_outline.size() > 1
				and snapped_outline[0] == snapped_outline[snapped_outline.size() - 1]):
			snapped_outline.remove_at(snapped_outline.size() - 1)
		if snapped_outline.size() >= 3:
			out.append(snapped_outline)
	return out


## `outline` without the vertices that sit within `NavBuilder.SIMPLIFY_TOLERANCE` of the line
## between their neighbours (the nearest to that line first, never below a triangle). A shot-up
## piece's hull has many such vertices (a shallow curve), and snapping them to the 1 px grid leaves
## a run of steps and notches a pixel deep. The baker's offset and its convex partition cannot
## always make a mesh of that, and then log "polygon convex partition failed" and bake NO navmesh at
## all (every path in the house is gone until the next re-bake). Dropping the vertices moves the
## edge by under the tolerance, far less than the margin around the piece.
static func simplified(outline: PackedVector2Array) -> PackedVector2Array:
	var points := outline.duplicate()
	# Each vertex's distance from the line between its neighbours, kept: dropping a vertex changes
	# only its two neighbours'.
	var gaps := PackedFloat64Array()
	for i in points.size():
		gaps.append(_gap_at(points, i))
	while points.size() > 3:
		var drop := -1
		var nearest := NavBuilder.SIMPLIFY_TOLERANCE
		for i in gaps.size():
			if gaps[i] < nearest:
				nearest = gaps[i]
				drop = i
		if drop < 0:
			break
		points.remove_at(drop)
		gaps.remove_at(drop)
		var n := points.size()
		gaps[(drop - 1 + n) % n] = _gap_at(points, (drop - 1 + n) % n)
		gaps[drop % n] = _gap_at(points, drop % n)
	return points


## How far vertex `i` of the ring `points` lies from the line between its neighbours
## (`simplified`).
static func _gap_at(points: PackedVector2Array, i: int) -> float:
	var n := points.size()
	var line_from: Vector2 = points[(i - 1 + n) % n]
	var line_to: Vector2 = points[(i + 1) % n]
	return points[i].distance_to(Geometry2D.get_closest_point_to_segment(
		points[i], line_from, line_to,
	))
