class_name NavSource extends RefCounted
## Navigation domain: what a bake is gathered from and how a gathered bake is run, the plumbing
## `NavBuilder`, `NavTiles`, `NavRing` and `NavRebake` share. A bake is a job, `{ poly, source }`:
## the polygon to bake into (the agent radius set) and its source geometry (the walls read from the
## twins, the walkable footprint and the furniture and character holes), gathered on the main
## thread. The source stays a 2D one (`NavigationMeshSourceGeometryData2D`: plan outlines on whole
## pixels, which the planning region keeps for the avoid maps); `bake_polygon` projects it into the
## 3D baker's source (ADR 0016). `bake` runs a job at once; `NavRebake` hands one to a worker
## thread (`NavBake`). The walls are a `walls` dictionary, `{ traversable, obstruction,
## projected }`, built only by `walls`.

## The box round an outline is this much (px) larger than the polygon, so outlines that merely touch
## still count as overlapping.
const BOUNDS_EPSILON := 0.5
## The bake's voxel grid (px): D16 measured a district's bake at 113 ms at 4 px against 2.0 s at 1.
const CELL_SIZE := 4.0
## The grid's height (px), the agent's and what a body stands over: only the floor's plane is baked,
## so these only need a few cells.
const CELL_HEIGHT := 2.0
const AGENT_HEIGHT := 8.0
## How tall (px) a carved obstruction stands: over the agent, a wall or a body alike.
const OBSTRUCTION_HEIGHT := 100.0
## What `bake_polygon` keeps on the polygon it bakes: its source and origin, so a tile can be baked
## again with cells closed (`NavSeams`).
const SOURCE_META := "nav_baked_source"
const ORIGIN_META := "nav_baked_origin"
## The baker's contour error (cells): the most a hole's edge is moved by simplifying its outline.
## Not 1: at 1 a one-cell stair step of a hole's outline is no corner, which takes the district's
## merged mesh (`NavMerge`) from 1142 polygons to 853 and a sofa's lane 4 px narrower (a 140 px
## hall's lane closed: `ai/grenade/combat_stun_then_advance`).
const EDGE_MAX_ERROR := 0.8


## The walls as the source takes them: the `obstruction` outlines (on whole pixels)
## and, beside them, `traversable` outlines and `projected` obstructions (none: the twins give
## obstructions only).
static func walls(
	obstruction: Array,
	traversable: Array = [],
	projected: Array = [],
) -> Dictionary:
	return { "traversable": traversable, "obstruction": obstruction, "projected": projected }


## What a bake of `house` reads of its walls: the floor-plan polygon each shape of a wall's twin
## stands on (`NavTwins.footprints`; no 2D collider is read), as `walls`, the
## obstructions in the house's local frame snapped to whole pixels. A lintel over a doorway
## (a header from a door's height up) is no obstruction: the bake projects at the plan, so the
## doorways stay open to the paths, and so do the doors (the group `doors`: their leaves stand in
## the doorways and are no wall's shape). Furniture is not read here: it is carved from its
## footprints. The same for every bake of the house until a wall's twin changes (a dent cuts it), so
## `nav_updater.gd` reads once for a tick's two bakes. `frame` places `house`'s own frame in its
## parent's (the obstructions are moved by it before they are snapped to whole pixels): a part of a
## larger house, read on its own.
static func walls_of(house: Node2D, frame := Transform2D.IDENTITY) -> Dictionary:
	var into := frame * house.global_transform.affine_inverse()
	var obstruction: Array = []
	for wall in NavTwins.walls_under(house):
		for ring: PackedVector2Array in NavTwins.footprints(wall, true):
			obstruction.append(into * ring)
	return walls(on_grid(obstruction))


## Everything a bake needs, gathered on the main thread: the polygon to bake into (`poly`, with the
## agent radius set) and its source geometry (`source`: the walls, the walkable footprint, the
## `furniture` holes (`NavBuilder.furniture_holes`) and each of `characters`). {} with no rooms.
## `walls` are the walls (`walls_of`) when the caller has them this frame, else read here.
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
	# the walls are read into `house`'s LOCAL frame (`walls_of`), so the
	# footprint and the baked mesh live in that frame too; the region is then offset by the house's
	# position to place the whole map back in world space. Mixing world and local here is what
	# silently misaligns the walls and seals the doorways.
	var local_bounds := Rect2(bounds.position - house.position, bounds.size)
	var source := NavigationMeshSourceGeometryData2D.new()
	# Obstructions: the walls' twin footprints. Setting the outlines replaces the
	# source's lists, so it comes before the footprint is added.
	var walls_here := parsed if not parsed.is_empty() else walls_of(house)
	source.set_traversable_outlines(walls_here["traversable"])
	source.set_obstruction_outlines(walls_here["obstruction"])
	source.set_projected_obstructions(walls_here["projected"])
	# Walkable footprint: the whole house bounds. The walls carve it, leaving the doorways.
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


## Add `fused` (the fused `local_outlines`) to `source` as obstruction outlines: snapped to whole
## pixels and simplified.
static func finish_holes(source: NavigationMeshSourceGeometryData2D, fused: Array) -> void:
	for outline in on_grid(fused):
		source.add_obstruction_outline(simplified(outline))


## Bake a gathered job (`job`) at once; `origin` is the region's offset (the bake's grid is laid on
## the world's: `bake_polygon`).
static func bake(baked: Dictionary, origin: Vector2) -> NavigationPolygon:
	var nav_poly: NavigationPolygon = baked["poly"]
	bake_polygon(nav_poly, baked["source"], origin)
	return nav_poly


## Bake `source` (the outlines of a job) into `poly` with the NavigationServer3D baker (D16): the
## walkable outlines are the floor of a plan-space world (x, 0, z), each obstruction outline a
## projected obstruction standing on it, so no piece, wall or body has a walkable top and no
## height of a lintel or a door can close a doorway. The agent's radius (`poly.agent_radius`) is
## taken off in the plan, as the 2D baker did (obstructions grown by it with round joins, the
## floor shrunk by it): the voxel baker's own erosion measures in whole cells and leaves a wall's
## end a third nearer than its radius. The mesh is voxelised on a `CELL_SIZE` px grid laid on the
## WORLD's (`origin`: the region's offset), so every region's vertices fall on the cells the map
## merges by; its polygons (merged where the union is convex: `NavMerge`) and vertices are set on
## `poly` in the plan's (x, y). Runs on the main thread or a worker's (`NavBake`): it reads
## nothing but its arguments. `closed` are cells (plan rects, not grown by the radius) to hold as
## well: a tile's border cells its neighbour holds (`NavSeams`).
static func bake_polygon(
	poly: NavigationPolygon,
	source: NavigationMeshSourceGeometryData2D,
	origin: Vector2,
	closed: Array[PackedVector2Array] = [],
) -> void:
	var floors := source.get_traversable_outlines()
	var radius := poly.agent_radius
	var shrunk: Array[PackedVector2Array] = []
	var mesh := NavigationMesh.new()
	mesh.cell_size = CELL_SIZE
	mesh.cell_height = CELL_HEIGHT
	mesh.agent_height = AGENT_HEIGHT
	mesh.agent_max_climb = CELL_HEIGHT
	mesh.agent_radius = 0.0
	mesh.region_min_size = 0.0
	mesh.region_merge_size = 0.0
	mesh.edge_max_error = EDGE_MAX_ERROR
	mesh.sample_partition_type = NavigationMesh.SAMPLE_PARTITION_WATERSHED
	mesh.border_size = poly.border_size if poly.baking_rect.has_area() else 0.0
	mesh.filter_baking_aabb = _bake_box(floors, poly.baking_rect, origin)
	var geometry := NavigationMeshSourceGeometryData3D.new()
	for outline: PackedVector2Array in floors:
		for inner: PackedVector2Array in Geometry2D.offset_polygon(
			outline, -radius, Geometry2D.JOIN_MITER,
		):
			shrunk.append(inner)
			geometry.add_faces(_floor_faces(inner), Transform3D.IDENTITY)
	var obstructions: Array[PackedVector2Array] = []
	var boxes: Array[Rect2] = []
	for outline: PackedVector2Array in source.get_obstruction_outlines():
		for grown: PackedVector2Array in Geometry2D.offset_polygon(
			outline, radius, Geometry2D.JOIN_ROUND,
		):
			obstructions.append(grown)
			boxes.append(outline_bounds(outline).grow(radius))
			geometry.add_projected_obstruction(_ring(grown), 0.0, OBSTRUCTION_HEIGHT, true)
	if poly.baking_rect.has_area():
		var tile := NavBorder.tile_rect(poly.baking_rect, poly.border_size, origin)
		for square in NavBorder.runs(obstructions, boxes, shrunk, tile):
			geometry.add_projected_obstruction(_ring(square), 0.0, OBSTRUCTION_HEIGHT, true)
	for square in closed:
		geometry.add_projected_obstruction(_ring(square), 0.0, OBSTRUCTION_HEIGHT, true)
	NavigationServer3D.bake_from_source_geometry_data(mesh, geometry)
	_take_mesh(poly, mesh)
	poly.set_meta(SOURCE_META, source)
	poly.set_meta(ORIGIN_META, origin)


## Set `mesh`'s vertices on `poly` in the plan's (x, y), and its polygons merged where the union is
## convex (`NavMerge`).
static func _take_mesh(poly: NavigationPolygon, mesh: NavigationMesh) -> void:
	poly.clear()
	poly.cell_size = CELL_SIZE
	var vertices := PackedVector2Array()
	for v in mesh.get_vertices():
		vertices.append(Vector2(v.x, v.z))
	poly.vertices = vertices
	var polygons: Array[PackedInt32Array] = []
	for i in mesh.get_polygon_count():
		polygons.append(mesh.get_polygon(i))
	for ring in NavMerge.merged(vertices, polygons):
		poly.add_polygon(ring)


## `outline` as a ring of the plan-space world (x, 0, z).
static func _ring(outline: PackedVector2Array) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for p in outline:
		ring.append(Vector3(p.x, 0.0, p.y))
	return ring


## The box a bake is made in: `rect` less its `border` (a tile's reach less what it sees past its
## edge) or else the floor outlines' bounds, on whole cells of the world's grid (`origin` is the
## region's offset). A tile's edges are rounded to the nearest cell line, so neighbours meet on the
## same one; the floor's are widened. Its height holds the floor and the obstructions.
static func _bake_box(floors: Array, rect: Rect2, origin: Vector2) -> AABB:
	var low: Vector2
	var high: Vector2
	if rect.has_area():
		low = ((rect.position + origin) / CELL_SIZE).round() * CELL_SIZE - origin
		high = ((rect.end + origin) / CELL_SIZE).round() * CELL_SIZE - origin
	else:
		var first := true
		for outline: PackedVector2Array in floors:
			var box := Rect2(outline[0], Vector2.ZERO)
			for p in outline:
				box = box.expand(p)
			rect = box if first else rect.merge(box)
			first = false
		low = ((rect.position + origin) / CELL_SIZE).floor() * CELL_SIZE - origin
		high = ((rect.end + origin) / CELL_SIZE).ceil() * CELL_SIZE - origin
	return AABB(
		Vector3(low.x, -CELL_HEIGHT * 2.0, low.y),
		Vector3(high.x - low.x, OBSTRUCTION_HEIGHT + CELL_HEIGHT * 4.0, high.y - low.y),
	)


## The two or more triangles of the floor `outline` (plan points), facing up.
static func _floor_faces(outline: PackedVector2Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var corners := Geometry2D.triangulate_polygon(outline)
	for i in range(0, corners.size(), 3):
		var a := outline[corners[i]]
		var b := outline[corners[i + 1]]
		var c := outline[corners[i + 2]]
		if (b - a).cross(c - a) < 0.0:
			var swap := b
			b = c
			c = swap
		faces.append(Vector3(a.x, 0.0, a.y))
		faces.append(Vector3(b.x, 0.0, b.y))
		faces.append(Vector3(c.x, 0.0, c.y))
	return faces


## Keep what the planning bake was made from (its walkable outline, its obstructions and the agent
## radius) on `region`, with a version that counts the bakes, so an avoid map can be baked from it
## with more holes and knows when the furniture has moved.
static func remember(region: NavigationRegion3D, baked: Dictionary) -> void:
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


## A new active map with the project's 3D navigation defaults (what a world's own map is made
## with, `project.godot`: cell size and height are those a bake's mesh is made in, and the server
## refuses a navmesh baked with another cell size). `edge_connections` is whether the map runs the
## server's edge-connection pass (the project's setting by default): it joins free edges of
## different regions within a pixel, which rebuilds the whole map's links on every change
## (`steering-edge-connections.md`).
static func new_map(edge_connections := true) -> RID:
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(
		map, float(ProjectSettings.get_setting("navigation/3d/default_cell_size", CELL_SIZE)),
	)
	NavigationServer3D.map_set_cell_height(
		map, float(ProjectSettings.get_setting("navigation/3d/default_cell_height", CELL_HEIGHT)),
	)
	NavigationServer3D.map_set_edge_connection_margin(
		map,
		float(ProjectSettings.get_setting("navigation/3d/default_edge_connection_margin", 1.0)),
	)
	NavigationServer3D.map_set_link_connection_radius(
		map,
		float(ProjectSettings.get_setting("navigation/3d/default_link_connection_radius", 4.0)),
	)
	NavigationServer3D.map_set_use_edge_connections(
		map,
		(
			edge_connections
			and bool(ProjectSettings.get_setting("navigation/3d/use_edge_connections", true))
		),
	)
	NavigationServer3D.map_set_active(map, true)
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


## `outlines` with every vertex snapped to whole pixels (the bake's cells, `CELL_SIZE`, lie on whole
## pixels too).
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
## piece's hull has many such vertices (a shallow curve), and snapping them to whole pixels leaves
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
