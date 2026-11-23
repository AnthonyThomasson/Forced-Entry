class_name NavSource extends RefCounted
## Navigation domain: what a bake is gathered from and how a gathered bake is run, the plumbing
## `NavBuilder`, `NavTiles`, `NavRing` and `NavRebake` share. A bake is a job, `{ poly, source }`:
## the polygon to bake into (the agent radius set) and its source geometry (the walls read from the
## twins, the walkable footprint and the furniture and character holes), gathered on the main
## thread. `bake` runs a job at once; `NavRebake` hands one to a worker thread (`NavBake`). The
## walls are a
## `walls` dictionary, `{ traversable, obstruction, projected }`, built only by `walls`.

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
## How near (px) to a polygon's edge a cell's centre is asked of `Geometry2D.is_point_in_polygon`
## rather than read from where the polygon crosses the line of centres (`_fill`): the engine's
## answer for a point on an edge differs from one point of it to the next, and the bake follows it.
const TIE_DISTANCE := 0.05


## The walls as the source takes them: the `obstruction` outlines (on the map's 1 px grid)
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
## obstructions in the house's local frame snapped to the map's 1 px grid. A lintel over a doorway
## (a header from a door's height up) is no obstruction: the bake projects at the plan, so the
## doorways stay open to the paths, and so do the doors (the group `doors`: their leaves stand in
## the doorways and are no wall's shape). Furniture is not read here: it is carved from its
## footprints. The same for every bake of the house until a wall's twin changes (a dent cuts it), so
## `nav_updater.gd` reads once for a tick's two bakes. `frame` places `house`'s own frame in its
## parent's (the obstructions are moved by it before they are snapped to the grid): a part of a
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


## Add `fused` (the fused `local_outlines`) to `source` as obstruction outlines: snapped to the 1 px
## grid and simplified.
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
## `poly` in the
## plan's (x, y). Runs on the main
## thread or a worker's (`NavBake`): it reads nothing but its arguments. `closed` are cells (plan
## rects, not grown by the radius) to hold as well: a tile's border cells its neighbour holds
## (`NavSeams`).
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
		var tile := _tile_rect(poly.baking_rect, poly.border_size, origin)
		for square in _border_runs(obstructions, boxes, shrunk, tile):
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


## A tile's own rect (the baking rect less its border) on whole cells of the world's grid.
static func _tile_rect(reach: Rect2, border: float, origin: Vector2) -> Rect2:
	var inner := reach.grow(-border)
	var low := ((inner.position + origin) / CELL_SIZE).round() * CELL_SIZE - origin
	var high := ((inner.end + origin) / CELL_SIZE).round() * CELL_SIZE - origin
	return Rect2(low, high - low)


## The cells of the tile's own outermost column that are held, or whose neighbour's
## cell across the border is held: by an obstruction, or by lying outside the floor (a cell is held
## by where its centre lies). The voxel baker takes a cell as held by where its centre lies, so a
## wall's tip or a floor's edge that ends between the two columns of a border leaves one tile's
## column open and its neighbour's shut, and the two tiles' walkable stretches along the border then
## differ; with the column shut on both sides they agree. Neighbouring held cells are one rectangle
## (the baker rasterises the same cells, with a fraction of the polygons).
static func _border_runs(
	obstructions: Array[PackedVector2Array],
	boxes: Array[Rect2],
	floors: Array[PackedVector2Array],
	tile: Rect2,
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var floor_boxes := _boxes(floors)
	for side in 4:
		var band := _strip_across(tile, side).merge(_strip_inside(tile, side))
		var blocks: Array[PackedVector2Array] = []
		for i in _touching(boxes, band):
			blocks.append(obstructions[i])
		var near: Array[PackedVector2Array] = []
		for i in _touching(floor_boxes, band):
			near.append(floors[i])
		out.append_array(_side_squares(blocks, near, tile, side))
	return out


## `_border_runs` along the `side` of `tile`, from the polygons `blocks` and `floors` that reach its
## two columns. A cell is a byte of `held`, found a line of cell centres at a time (`_fill`), not
## a point at a time. When the floor holds the whole band only a cell in a block can be held, and a
## band no floor reaches is held whole.
static func _side_squares(
	blocks: Array[PackedVector2Array],
	floors: Array[PackedVector2Array],
	tile: Rect2,
	side: int,
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var along := side <= 1
	var first := (tile.position.y if along else tile.position.x) + CELL_SIZE * 0.5
	var last := (tile.end.y if along else tile.end.x) - CELL_SIZE * 0.5
	if floors.is_empty():
		out.append(_run_inside(tile, side, first, last))
		return out
	var covered := _covers(floors, _strip_across(tile, side).merge(_strip_inside(tile, side)))
	if covered and blocks.is_empty():
		return out
	var held := PackedByteArray()
	held.resize(int(roundf((last - first) / CELL_SIZE)) + 1)
	var unfloored: Array[PackedVector2Array] = []
	for across in [true, false]:
		var cells := _line_held(blocks, unfloored if covered else floors, tile, side, across)
		for k in held.size():
			held[k] = held[k] | cells[k]
	return _runs_of(held, tile, side)


## The cells along the `side` of `tile` (a byte each, from the first centre) that are held on the
## line of centres across the border (`across`) or inside it: in one of `blocks`, or in none of
## `floors` (none given: only `blocks` hold).
static func _line_held(
	blocks: Array[PackedVector2Array],
	floors: Array[PackedVector2Array],
	tile: Rect2,
	side: int,
	across: bool,
) -> PackedByteArray:
	var along := side <= 1
	var first := (tile.position.y if along else tile.position.x) + CELL_SIZE * 0.5
	var last := (tile.end.y if along else tile.end.x) - CELL_SIZE * 0.5
	var strip := _strip_across(tile, side) if across else _strip_inside(tile, side)
	var at := strip.get_center().x if along else strip.get_center().y
	var held := PackedByteArray()
	held.resize(int(roundf((last - first) / CELL_SIZE)) + 1)
	_fill(held, blocks, at, along, first)
	if floors.is_empty():
		return held
	var inside := PackedByteArray()
	inside.resize(held.size())
	_fill(inside, floors, at, along, first)
	for k in held.size():
		held[k] = held[k] | (1 - inside[k])
	return held


## The cells of `held` (a byte each, from the first centre along the `side` of `tile`) that are 1,
## each stretch of them one rectangle (`_run_inside`).
static func _runs_of(
	held: PackedByteArray,
	tile: Rect2,
	side: int,
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var first := (tile.position.y if side <= 1 else tile.position.x) + CELL_SIZE * 0.5
	var run_from := -INF
	for k in held.size():
		var mid := first + CELL_SIZE * k
		if held[k] == 1 and run_from == -INF:
			run_from = mid
		elif held[k] == 0 and run_from != -INF:
			out.append(_run_inside(tile, side, run_from, mid - CELL_SIZE))
			run_from = -INF
	if run_from != -INF:
		out.append(_run_inside(tile, side, run_from, first + CELL_SIZE * (held.size() - 1)))
	return out


## Set to 1 each cell of `cells` (the centres `first` and every `CELL_SIZE` on, along the y axis
## when `vertical`, else the x axis, on the line `at` across it) that lies in one of `polygons`
## (what `Geometry2D.is_point_in_polygon` answers): the polygon's crossings with the line, paired in
## order, are the stretches inside it. A centre on or within `TIE_DISTANCE` of an edge is no
## stretch's to decide (the engine's answer on an edge is not the same at every point of it): it is
## asked of the engine, one call each.
static func _fill(
	cells: PackedByteArray,
	polygons: Array[PackedVector2Array],
	at: float,
	vertical: bool,
	first: float,
) -> void:
	for polygon in polygons:
		var crossings := PackedFloat64Array()
		var windows := PackedFloat64Array()
		_trace(polygon, at, vertical, crossings, windows)
		var ties := _cells_in(windows, first, cells.size())
		var kept := PackedByteArray()
		for k in ties:
			kept.append(cells[k])
		crossings.sort()
		for i in range(0, crossings.size() - 1, 2):
			_mark(cells, crossings[i], crossings[i + 1], first)
		for i in ties.size():
			var centre := first + CELL_SIZE * ties[i]
			var point := Vector2(at, centre) if vertical else Vector2(centre, at)
			var inside := kept[i] == 1 or Geometry2D.is_point_in_polygon(point, polygon)
			cells[ties[i]] = 1 if inside else 0


## Where `polygon` meets the line `at` (across the axis `vertical` names): the points along the line
## it crosses (`crossings`, a vertex on the line counts as just past it), and as pairs of `windows`
## the stretches along it within `TIE_DISTANCE` of an edge.
static func _trace(
	polygon: PackedVector2Array,
	at: float,
	vertical: bool,
	crossings: PackedFloat64Array,
	windows: PackedFloat64Array,
) -> void:
	var from := polygon[polygon.size() - 1]
	for to in polygon:
		var u_from := from.x if vertical else from.y
		var u_to := to.x if vertical else to.y
		var v_from := from.y if vertical else from.x
		var v_to := to.y if vertical else to.x
		var near := TIE_DISTANCE * 2.0
		if absf(u_from - at) <= TIE_DISTANCE:
			windows.append(minf(v_from, v_to if absf(u_to - at) <= TIE_DISTANCE else v_from) - near)
			windows.append(maxf(v_from, v_to if absf(u_to - at) <= TIE_DISTANCE else v_from) + near)
		if (u_from > at) != (u_to > at):
			var run := absf(v_to - v_from)
			var reach := minf(TIE_DISTANCE * (1.0 + run / absf(u_to - u_from)), run + TIE_DISTANCE)
			var v := v_from + (at - u_from) * (v_to - v_from) / (u_to - u_from)
			crossings.append(v)
			windows.append(v - reach)
			windows.append(v + reach)
		from = to


## The cells (of `count`, centres `first` and every `CELL_SIZE` on) whose centre is in a stretch of
## `windows` (pairs: from, to).
static func _cells_in(windows: PackedFloat64Array, first: float, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(0, windows.size() - 1, 2):
		for k in range(
			maxi(ceili((windows[i] - first) / CELL_SIZE), 0),
			mini(floori((windows[i + 1] - first) / CELL_SIZE), count - 1) + 1,
		):
			out.append(k)
	return out


## Set to 1 the cells of `cells` whose centre lies between `low` and `high` (either order).
static func _mark(cells: PackedByteArray, low: float, high: float, first: float) -> void:
	if low > high:
		var swap := low
		low = high
		high = swap
	var from := maxi(ceili((low - first) / CELL_SIZE), 0)
	var to := mini(floori((high - first) / CELL_SIZE), cells.size() - 1)
	for k in range(from, to + 1):
		cells[k] = 1


## The bounds of each of `polygons`.
static func _boxes(polygons: Array[PackedVector2Array]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for polygon in polygons:
		var box := Rect2(polygon[0], Vector2.ZERO)
		for p in polygon:
			box = box.expand(p)
		out.append(box)
	return out


## The indices of `boxes` that reach `band`.
static func _touching(boxes: Array[Rect2], band: Rect2) -> Array[int]:
	var out: Array[int] = []
	for i in boxes.size():
		if boxes[i].intersects(band):
			out.append(i)
	return out


## Whether the one floor polygon of `floors` holds the whole of `band` (nothing of the band is
## outside it); false for none or several, which are asked cell by cell.
static func _covers(floors: Array[PackedVector2Array], band: Rect2) -> bool:
	if floors.size() != 1:
		return false
	var corners := PackedVector2Array([
		band.position, Vector2(band.end.x, band.position.y), band.end,
		Vector2(band.position.x, band.end.y),
	])
	return Geometry2D.clip_polygons(corners, floors[0]).is_empty()


## The strip of cells just outside `tile`'s `side` (0 left, 1 right, 2 top, 3 bottom).
static func _strip_across(tile: Rect2, side: int) -> Rect2:
	match side:
		0:
			return Rect2(tile.position.x - CELL_SIZE, tile.position.y, CELL_SIZE, tile.size.y)
		1:
			return Rect2(tile.end.x, tile.position.y, CELL_SIZE, tile.size.y)
		2:
			return Rect2(tile.position.x, tile.position.y - CELL_SIZE, tile.size.x, CELL_SIZE)
	return Rect2(tile.position.x, tile.end.y, tile.size.x, CELL_SIZE)


## The strip of `tile`'s own outermost column on `side`.
static func _strip_inside(tile: Rect2, side: int) -> Rect2:
	match side:
		0:
			return Rect2(tile.position.x, tile.position.y, CELL_SIZE, tile.size.y)
		1:
			return Rect2(tile.end.x - CELL_SIZE, tile.position.y, CELL_SIZE, tile.size.y)
		2:
			return Rect2(tile.position.x, tile.position.y, tile.size.x, CELL_SIZE)
	return Rect2(tile.position.x, tile.end.y - CELL_SIZE, tile.size.x, CELL_SIZE)


## The cells of `tile`'s outermost column on `side` from the one level with `from` to the one level
## with `to` (along the border), as one rectangle.
static func _run_inside(tile: Rect2, side: int, from: float, to: float) -> PackedVector2Array:
	var half := CELL_SIZE * 0.5
	var low: Vector2
	var high: Vector2
	match side:
		0:
			low = Vector2(tile.position.x, from - half)
			high = Vector2(tile.position.x + CELL_SIZE, to + half)
		1:
			low = Vector2(tile.end.x - CELL_SIZE, from - half)
			high = Vector2(tile.end.x, to + half)
		2:
			low = Vector2(from - half, tile.position.y)
			high = Vector2(to + half, tile.position.y + CELL_SIZE)
		_:
			low = Vector2(from - half, tile.end.y - CELL_SIZE)
			high = Vector2(to + half, tile.end.y)
	return PackedVector2Array([low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)])


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
## cell size). `edge_connections` is whether the map runs the server's edge-connection pass (the
## project's setting by default): it joins free edges of different regions within a pixel, which
## rebuilds the whole map's links on every change (`steering-edge-connections.md`).
static func new_map(edge_connections := true) -> RID:
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
		(
			edge_connections
			and bool(ProjectSettings.get_setting("navigation/2d/use_edge_connections", true))
		),
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
