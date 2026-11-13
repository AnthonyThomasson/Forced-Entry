class_name NavTiles extends RefCounted
## Navigation domain: the steering map of a large footprint (a district) as a grid of tiles. One
## region over the whole footprint is one bake of every wall and every piece of furniture in it, on
## the main thread, each time a character stops or sets off; a tile is baked from only what reaches
## it (its walls, its furniture and its characters), and only when that has changed since its last
## bake, so a character stopping re-bakes the one tile it stands in (two or four on a seam). The
## tiles are regions on the steering map, children of the planning region, baked to meet at their
## edges (`BORDER`: the baker sees past the tile's edge so the agent's erosion does not shrink it,
## and the 1 px grid the bake is welded to puts the neighbours' vertices on the same points).
## `NavBuilder` builds the tiles and hands each tick's footprints to `rebake`.

## A tile's side, px.
const SIZE := 512.0
## How far (px) past a tile's edge the baker sees: more than a wall's erosion and a hole's margin.
const BORDER := 40.0
## A tile region's name is this and its column and row.
const NAME_PREFIX := "NavSteering_"
## The meta on a tile region: its rect (the house's local frame), and the walls' and the holes'
## outlines it was baked from (to see whether a tick changed them).
const RECT_META := "nav_tile_rect"
const WALLS_META := "nav_tile_walls"
const HOLES_META := "nav_tile_holes"
## The meta on the planning region that keeps each tower's parsed walls (`walls_reaching`).
const WALL_CACHE_META := "nav_wall_cache"
## How many outline bounds are remembered; a full cache starts afresh rather than growing forever.
const BOUNDS_KEPT := 4096

## Outline contents -> their bounds. A piece that moves has a different outline and is measured
## again; identical static outlines share one entry even when the hull helper returns a copy.
static var _bounds: Dictionary = {}
## Actual bounds measurements and candidate rectangle checks, observables of the two fast paths.
static var bounds_measures := 0
static var intersection_tests := 0
## How many steering tiles have been baked since the process began, by `rebake` and `prepare`
## alike (a perf probe's read of what a tick's re-bake cost; a tile whose job was empty is no
## bake). A tile counts when it is baked, not when it lands (`land`).
static var baked_total := 0


## `footprint` (the house's local frame) grown to whole pixels: the rect the tiles are laid over.
## The baker rounds a bake's rect to whole pixels (toward zero, a corner and a side apart), so tiles
## whose edges fall between pixels would be baked to edges a pixel apart; on whole pixels every
## tile's edge is the edge of its neighbour, which `NavSeams` welds.
static func whole_pixels(footprint: Rect2) -> Rect2:
	var from := footprint.position.floor()
	return Rect2(from, footprint.end.ceil() - from)


## The tiles that cover `footprint` (`whole_pixels`), row by row; the last of a row or a column is
## the remainder.
static func grid(footprint: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var y := footprint.position.y
	while y < footprint.end.y:
		var x := footprint.position.x
		while x < footprint.end.x:
			out.append(Rect2(x, y, SIZE, SIZE).intersection(footprint))
			x += SIZE
		y += SIZE
	return out


## The name of the tile region over `rect`, a tile of the grid over `footprint` (`whole_pixels`).
static func name_of(rect: Rect2, footprint: Rect2) -> String:
	var column := int((rect.position.x - footprint.position.x) / SIZE)
	var row := int((rect.position.y - footprint.position.y) / SIZE)
	return "%s%d_%d" % [NAME_PREFIX, column, row]


## Re-bake the tiles of `region`'s steering map (`NavBuilder.steering_regions`) whose furniture or
## characters changed since they were last baked (a tile never baked has none, so the first call
## bakes them all), each from the walls and the furniture and characters that reach it. The walls
## are `walls` (a whole parse, `NavSource.walls_of`) when given, else those of the towers that
## reach the tiles to bake, parsed afresh (`walls_reaching`): a wall shot up in a tile where nothing
## stands or moves waits for the next change there. Returns how many tiles were baked.
static func rebake(
	region: NavigationRegion2D,
	site: NavSite,
	furniture: Array,
	characters: Array,
	walls: Dictionary = {},
) -> int:
	var tiles := NavBuilder.steering_regions(region)
	var hole_bins := bin(furniture + characters, _reaches(tiles), site.house.position)
	var due: Array[int] = []
	for i in tiles.size():
		if not _holes_unchanged(tiles[i], hole_bins[i]):
			due.append(i)
	if due.is_empty():
		return 0
	var reaches: Array[Rect2] = []
	for i in due:
		reaches.append(_reach(tiles[i]))
	var parsed := walls
	if parsed.is_empty():
		parsed = NavSource.walls(walls_reaching(region, site, reaches))
	var wall_bins := bin(parsed["obstruction"], reaches, Vector2.ZERO)
	var baked: Array = []
	for k in due.size():
		var tile: NavigationRegion2D = tiles[due[k]]
		if _baked_from(tile, wall_bins[k], hole_bins[due[k]]):
			continue
		var reached := NavSource.walls(wall_bins[k], parsed["traversable"], parsed["projected"])
		if _bake_tile(tile, site, reached, hole_bins[due[k]]):
			baked.append(tile)
	NavSeams.weld(baked)
	baked_total += baked.size()
	return baked.size()


## The steering tiles of `region` that `furniture` and `characters` (this tick's footprints) leave
## due, as `{ tile, holes }` in the order they are baked (`prepare`): first the tiles that hold a
## moving walker (a living character `walking_at` finds), nearest first, then the rest. A tile's
## distance is that of the nearest walker to the tile's own rect (its rect, not the `BORDER` round
## it), 0 for the tile holding it; equal distances, and every tile when nothing walks, go in the
## grid's order (the tiles' own). `walkers` are world points. Where `rebake` bakes every due tile
## now, the updater bakes the first at once and one more each physics frame, and lands them
## together.
static func due_tiles(
	region: NavigationRegion2D,
	site: NavSite,
	furniture: Array,
	characters: Array,
	walkers: Array[Vector2] = [],
) -> Array[Dictionary]:
	var tiles := NavBuilder.steering_regions(region)
	var hole_bins := bin(furniture + characters, _reaches(tiles), site.house.position)
	var keyed: Array[Dictionary] = []
	for i in tiles.size():
		if _holes_unchanged(tiles[i], hole_bins[i]):
			continue
		var rect: Rect2 = tiles[i].get_meta(RECT_META)
		var gap := _gap(rect, walkers, site)
		keyed.append({ "tile": tiles[i], "holes": hole_bins[i], "gap": gap, "i": i })
	keyed.sort_custom(_nearer)
	return keyed


## The walls (`NavSource.walls`' shape) that reach any of the tiles of `entries` (`due_tiles`'
## entries), parsed once for a whole burst: the towers that do, parsed afresh, as `rebake` parses
## them for all its due tiles at once.
static func parse_for(
	region: NavigationRegion2D,
	site: NavSite,
	entries: Array,
) -> Dictionary:
	var reaches: Array[Rect2] = []
	for entry: Dictionary in entries:
		if is_instance_valid(entry["tile"]):
			reaches.append(_reach(entry["tile"]))
	return NavSource.walls(walls_reaching(region, site, reaches))


## Bake one entry of `due_tiles` (`{ tile, holes }`) from `parsed` (`parse_for`) and the holes it
## was due with, and hold the polygon: nothing on the tile changes until `land`. Returns the held
## bake `{ tile, poly, walls, holes }`, `{}` when nothing was baked (the tile was freed meanwhile,
## was baked from exactly these already, or the site has nothing to bake).
static func prepare(site: NavSite, entry: Dictionary, parsed: Dictionary) -> Dictionary:
	var tile := entry["tile"] as NavigationRegion2D
	if not is_instance_valid(tile) or not tile.is_inside_tree():
		return {}
	var reaches: Array[Rect2] = [_reach(tile)]
	var walls: Array = bin(parsed["obstruction"], reaches, Vector2.ZERO)[0]
	if _baked_from(tile, walls, entry["holes"]):
		return {}
	var reached := NavSource.walls(walls, parsed["traversable"], parsed["projected"])
	var poly := _baked_poly(tile, site, reached, entry["holes"])
	if poly == null:
		return {}
	baked_total += 1
	return { "tile": tile, "poly": poly, "walls": reached, "holes": entry["holes"] }


## Give the tiles of the held bakes `held` (`prepare`) their polygons, all in this call: the
## steering map takes them in with one synchronisation (about 0.3 ms with its edge connections off,
## it was 12 ms with them on), so a burst lands whole. A tile freed meanwhile is skipped.
static func land(held: Array) -> void:
	var landed: Array = []
	for bake: Dictionary in held:
		var tile := bake["tile"] as NavigationRegion2D
		if is_instance_valid(tile):
			_assign(tile, bake["poly"], bake["walls"], bake["holes"])
			landed.append(tile)
	NavSeams.weld(landed)


## The world points of the living characters under `root` that are walking (collision layer still
## set, moving at `NavBuilder.REST_SPEED` or more): the complement of `NavBuilder.character_holes`.
static func walking_at(root: Node) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if root == null:
		return out
	for node in root.get_children():
		var body := node as CharacterBody2D
		if (body != null
				and body.collision_layer != 0
				and body.get_real_velocity().length() >= NavBuilder.REST_SPEED):
			out.append(body.global_position)
	return out


## The squared distance from the nearest of the world points `walkers` to `rect` (the house's local
## frame); INF with none.
static func _gap(rect: Rect2, walkers: Array[Vector2], site: NavSite) -> float:
	var best := INF
	for point in walkers:
		var local := point - site.house.position
		best = minf(best, (local.clamp(rect.position, rect.end) - local).length_squared())
	return best


## Whether the due entry `a` is baked before `b`: the nearer to a walker, then the grid's order.
static func _nearer(a: Dictionary, b: Dictionary) -> bool:
	if a["gap"] != b["gap"]:
		return a["gap"] < b["gap"]
	return a["i"] < b["i"]


## `tile` baked from `walls` (a parse's shape) and the `holes` that reach it, which it keeps to see
## whether they change. False when the site has nothing to bake.
static func _bake_tile(
	tile: NavigationRegion2D,
	site: NavSite,
	walls: Dictionary,
	holes: Array,
) -> bool:
	var poly := _baked_poly(tile, site, walls, holes)
	if poly == null:
		return false
	_assign(tile, poly, walls, holes)
	return true


## The polygon of `tile` baked from `walls` and `holes`; null when the site has nothing to bake.
static func _baked_poly(
	tile: NavigationRegion2D,
	site: NavSite,
	walls: Dictionary,
	holes: Array,
) -> NavigationPolygon:
	var job := NavSource.job(site, holes, [], walls)
	if job.is_empty():
		return null
	var nav_poly: NavigationPolygon = job["poly"]
	nav_poly.baking_rect = _reach(tile)
	nav_poly.border_size = BORDER
	return NavSource.bake(job, site.house.position)


## `tile` takes `poly`, baked from `walls` and `holes`, which it keeps.
static func _assign(
	tile: NavigationRegion2D,
	poly: NavigationPolygon,
	walls: Dictionary,
	holes: Array,
) -> void:
	NavSeams.take(tile, poly)
	tile.navigation_polygon = poly
	tile.set_meta(WALLS_META, walls["obstruction"])
	tile.set_meta(HOLES_META, holes)


## The wall outlines (the house's local frame, on the map's 1 px grid) of the towers whose walls
## reach any of `reaches`. Each direct child of the house is parsed on its own and kept on `region`
## (`_refreshed`); the ones that reach are parsed again, so a wall dented since is in the result.
## A tower costs a tenth of the whole district's parse, and a tile touches one or two. A collider
## that is a child of the house itself is no tower's: the whole house is parsed instead.
static func walls_reaching(
	region: NavigationRegion2D,
	site: NavSite,
	reaches: Array[Rect2],
) -> Array:
	var entries: Variant = _refreshed(region, site, reaches)
	if entries == null:
		return NavSource.walls_of(site.house, site.agent_radius)["obstruction"]
	var out: Array = []
	for entry: Dictionary in entries:
		if _touches(entry, reaches):
			out.append_array(entry["outlines"])
	return out


## `walls_reaching` for every tower, not only those that reach: the ones that reach `reaches` are
## parsed again, and the rest keep what they were.
static func walls_all(
	region: NavigationRegion2D,
	site: NavSite,
	reaches: Array[Rect2],
) -> Array:
	var entries: Variant = _refreshed(region, site, reaches)
	if entries == null:
		return NavSource.walls_of(site.house, site.agent_radius)["obstruction"]
	var out: Array = []
	for entry: Dictionary in entries:
		out.append_array(entry["outlines"])
	return out


## The parse of each tower of `site`'s house (`_parse_tower`), in the order of the house's children,
## as kept on `region`: a tower never parsed, or one that reaches `reaches`, is parsed again and
## kept. Null when a collider is a child of the house itself.
static func _refreshed(
	region: NavigationRegion2D,
	site: NavSite,
	reaches: Array[Rect2],
) -> Variant:
	for child in site.house.get_children():
		if child is CollisionObject2D:
			return null
	var cache: Dictionary = region.get_meta(WALL_CACHE_META, {})
	var entries: Array = []
	for child in site.house.get_children():
		if not child is Node2D:
			continue
		var entry: Dictionary = cache.get(child.get_instance_id(), {})
		if entry.is_empty() or _touches(entry, reaches):
			entry = _parse_tower(child as Node2D, site.agent_radius)
			cache[child.get_instance_id()] = entry
		entries.append(entry)
	region.set_meta(WALL_CACHE_META, cache)
	return entries


## The walls (`NavSource.walls`' shape) a planning re-bake of `site` is made from after the
## furniture went from `before` to `after` (`NavBuilder.furniture_holes`): a house's whole parse; a
## district's every tower, those near a piece that moved parsed afresh (`walls_all`).
static func walls_after(
	region: NavigationRegion2D,
	site: NavSite,
	before: Array,
	after: Array,
) -> Dictionary:
	if not site.bounds.has_area():
		return NavSource.walls_of(site.house, site.agent_radius)
	return NavSource.walls(walls_all(region, site, _changed(site, before, after)))


## The areas (the house's local frame) where `after` differs from `before`: the box of each piece
## that stands elsewhere, then and now, and the whole footprint when the pieces are not the same
## ones (a count that changed).
static func _changed(site: NavSite, before: Array, after: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if before.size() != after.size():
		out.append(site.footprint())
		return out
	for i in before.size():
		if before[i] != after[i]:
			for outline: PackedVector2Array in [before[i], after[i]]:
				var box := NavSource.outline_bounds(outline)
				box.position -= site.house.position
				out.append(box)
	return out


## The walls under `tower` as `{ outlines, box }`: its obstruction outlines in the house's frame
## (its own transform applied before they are snapped to the grid, as a parse of the house would)
## and the box round them.
static func _parse_tower(tower: Node2D, agent_radius: float) -> Dictionary:
	var outlines: Array = NavSource.walls_of(tower, agent_radius, tower.transform)["obstruction"]
	var box := Rect2()
	for i in outlines.size():
		var outline_box := NavSource.outline_bounds(outlines[i])
		box = outline_box if i == 0 else box.merge(outline_box)
	return { "outlines": outlines, "box": box }


## Whether the walls in `entry` (`_parse_tower`) reach any of `reaches`.
static func _touches(entry: Dictionary, reaches: Array[Rect2]) -> bool:
	if (entry["outlines"] as Array).is_empty():
		return false
	for reach in reaches:
		if reach.intersects(entry["box"]):
			return true
	return false


## `tile`'s rect with the `BORDER` round it: what reaches it.
static func _reach(tile: NavigationRegion2D) -> Rect2:
	return (tile.get_meta(RECT_META) as Rect2).grow(BORDER)


## The `_reach` of each of `tiles`.
static func _reaches(tiles: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for tile: NavigationRegion2D in tiles:
		out.append(_reach(tile))
	return out


## Whether `tile` was last baked from exactly `holes` (never baked: no).
static func _holes_unchanged(tile: NavigationRegion2D, holes: Array) -> bool:
	return tile.has_meta(HOLES_META) and tile.get_meta(HOLES_META) == holes


## Whether `tile` was last baked from exactly `walls` and `holes` (never baked: no).
static func _baked_from(tile: NavigationRegion2D, walls: Array, holes: Array) -> bool:
	return (tile.has_meta(WALLS_META)
			and tile.get_meta(WALLS_META) == walls
			and tile.get_meta(HOLES_META) == holes)


## A world point on `tile`'s navmesh (the centre of its first polygon), `Vector2.INF` when the tile
## has none (all wall or all furniture): where the map's ready check asks for the tile. `fallback`
## for a steering region that is no tile.
static func probe_of(tile: NavigationRegion2D, fallback: Vector2) -> Vector2:
	if not tile.has_meta(RECT_META):
		return fallback
	var nav_poly := tile.navigation_polygon
	if nav_poly == null or nav_poly.get_polygon_count() == 0:
		return Vector2.INF
	var vertices := nav_poly.get_vertices()
	var sum := Vector2.ZERO
	var indices := nav_poly.get_polygon(0)
	for index in indices:
		sum += vertices[index]
	return tile.to_global(sum / float(indices.size()))


## `outlines` binned by the rect of `reaches` each meets: one list per rect, in the order of
## `outlines`. `shift` is how far the outlines' frame lies from the rects' (a world-space outline,
## the house's position). The reaches are tile rects grown by `BORDER`, so their grid cell gives
## the only bins a box can meet; the exact rectangle test at those candidates keeps border contact
## and the last row's or column's shorter tiles identical to the full scan. A caller with reaches
## that are not such a grid (the planning ring's one large footprint) keeps the full scan.
static func bin(outlines: Array, reaches: Array[Rect2], shift: Vector2) -> Array:
	var bins: Array = []
	for _reach_rect in reaches:
		bins.append([])
	if reaches.is_empty():
		return bins
	var origin := reaches[0].position + Vector2.ONE * BORDER
	var cells := _grid_cells(reaches)
	if cells.is_empty():
		return _full_scan(outlines, reaches, shift)
	var span := _span(cells)
	for outline: PackedVector2Array in outlines:
		var box := _outline_bounds(outline)
		box.position -= shift
		for i in _candidates(box, origin, cells, span):
			intersection_tests += 1
			if reaches[i].intersects(box):
				bins[i].append(outline)
	return bins


## The cells (low corner, and past the high one) the grid's tiles occupy. A box far larger than the
## district, or a stray point, only ever meets these.
static func _span(cells: Dictionary) -> Rect2i:
	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-(1 << 30), -(1 << 30))
	for cell: Vector2i in cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	return Rect2i(low, high - low + Vector2i.ONE)


## The indices of the reaches a box can meet. Neighbouring reaches overlap by twice the border, so
## the box is grown and looked up on the ungrown tiles' grid; the caller tests the original box
## against each candidate's actual reach.
static func _candidates(box: Rect2, origin: Vector2, cells: Dictionary, span: Rect2i) -> Array[int]:
	var grid_box := box.grow(BORDER)
	var first := _cell(grid_box.position, origin).clamp(span.position, span.end - Vector2i.ONE)
	var last := _cell(grid_box.end, origin).clamp(span.position, span.end - Vector2i.ONE)
	var out: Array[int] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if cells.has(Vector2i(x, y)):
				out.append(cells[Vector2i(x, y)])
	return out


## Grid cell -> reach index for a genuine steering-tile grid; empty when the reaches are anything
## else, so the caller keeps the original every-reach scan.
static func _grid_cells(reaches: Array[Rect2]) -> Dictionary:
	var margin := Vector2.ONE * BORDER
	var origin := reaches[0].position + margin
	var cells := {}
	for i in reaches.size():
		var cell := _cell(reaches[i].position + margin, origin)
		var aligned := origin + Vector2(cell) * SIZE - margin
		if (reaches[i].size.x > SIZE + 2 * BORDER
				or reaches[i].size.y > SIZE + 2 * BORDER
				or not reaches[i].position.is_equal_approx(aligned)
				or cells.has(cell)):
			return {}
		cells[cell] = i
	return cells


## The every-reach scan for a caller whose reaches are not a steering-tile grid.
static func _full_scan(outlines: Array, reaches: Array[Rect2], shift: Vector2) -> Array:
	var bins: Array = []
	for _reach_rect in reaches:
		bins.append([])
	for outline: PackedVector2Array in outlines:
		var box := _outline_bounds(outline)
		box.position -= shift
		for i in reaches.size():
			intersection_tests += 1
			if reaches[i].intersects(box):
				bins[i].append(outline)
	return bins


## The grid cell containing `point`, on the tiles' `SIZE` grid from `origin`; floor, not truncation,
## so a district whose footprint starts at a negative coordinate uses the cells to its left too.
static func _cell(point: Vector2, origin: Vector2) -> Vector2i:
	var p := (point - origin) / SIZE
	return Vector2i(floori(p.x), floori(p.y))


## An outline's bounds, remembered while its points stand still. Hashing the outline also makes two
## identical pieces share the answer; any moved point makes a different key, never a stale bound.
static func _outline_bounds(outline: PackedVector2Array) -> Rect2:
	if _bounds.has(outline):
		return _bounds[outline]
	if _bounds.size() >= BOUNDS_KEPT:
		_bounds.clear()
	bounds_measures += 1
	var box := NavSource.outline_bounds(outline)
	_bounds[outline] = box
	return box
