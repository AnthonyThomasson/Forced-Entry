class_name NavTiles extends RefCounted
## Navigation domain: the steering map of a large footprint (a district) as a grid of tiles. One
## region over the whole footprint is one bake of every wall and every piece of furniture in it, on
## the main thread, each time a character stops or sets off; a tile is baked from only what reaches
## it (its walls, its furniture and its characters), and only when that has changed since its last
## bake, so a character stopping re-bakes the one tile it stands in (two or four on a seam). The
## tiles are regions on the steering map, children of the planning region, baked to meet at their
## edges (`BORDER`: the baker sees past the tile's edge so the agent's erosion does not shrink it;
## the grid lies on the bake's cells, `on_cells`, and `NavSeams` splits each border edge at the
## vertices its neighbour has there, so the server joins them by the edge they share and the map
## needs no edge-connection pass).
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
## The holes a tick brought that are the baked ones within `NavSettle.TOLERANCE`
## (`_holes_unchanged`).
const SEEN_META := "nav_tile_holes_seen"
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
## How many tile bakes were started on a worker thread, and how many of them were still running when
## their burst landed (a creeping share is a `NavBakeConfig.tile_frames` fallen behind the pool).
static var threaded_total := 0
static var late_total := 0


## `footprint` (the house's local frame) grown to whole cells of the bake's grid, which lies on the
## world's (`origin`, the house's position): the rect the tiles are laid over. The baker takes a
## bake's rect to the nearest cell line, so tiles whose edges fall between lines would be baked to
## edges apart; on the lines every tile's edge is the edge of its neighbour, which `NavSeams` welds.
static func on_cells(footprint: Rect2, origin: Vector2) -> Rect2:
	var from := ((footprint.position + origin) / NavSource.CELL_SIZE).floor() * NavSource.CELL_SIZE
	var to := ((footprint.end + origin) / NavSource.CELL_SIZE).ceil() * NavSource.CELL_SIZE
	return Rect2(from - origin, to - from)


## The tiles that cover `footprint` (`on_cells`), row by row; the last of a row or a column is
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


## The name of the tile region over `rect`, a tile of the grid over `footprint` (`on_cells`).
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
	region: NavigationRegion3D,
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
	var gathered: Array[NavTileBake] = []
	for k in due.size():
		var held := _gathered_if_changed(
			tiles[due[k]], site, parsed, wall_bins[k], hole_bins[due[k]])
		if held != null:
			gathered.append(held)
	_bake_together(gathered)
	var baked: Array = []
	for held in gathered:
		_assign(held.tile, held.poly, held.walls, held.holes, held.seams)
		baked.append(held.tile)
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
	region: NavigationRegion3D,
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
	region: NavigationRegion3D,
	site: NavSite,
	entries: Array,
) -> Dictionary:
	var reaches: Array[Rect2] = []
	for entry: Dictionary in entries:
		if is_instance_valid(entry["tile"]):
			reaches.append(_reach(entry["tile"]))
	return NavSource.walls(walls_reaching(region, site, reaches))


## Start one entry of `due_tiles` (`{ tile, holes }`) baking, from `parsed` (`parse_for`) and the
## holes it was due with: the source is gathered here, on the main thread, and the bake runs on a
## worker thread (`task`), so a frame pays for the gathering only. Nothing on the tile changes until
## `land`. Returns the held bake (`NavTileBake`), null when
## nothing was started (the tile was freed meanwhile, was baked from these holes already, or the
## site has nothing to bake). The worker is handed the bake's values, not the record
## (`NavTileBake.start`).
static func prepare(site: NavSite, entry: Dictionary, parsed: Dictionary) -> NavTileBake:
	var tile := entry["tile"] as NavigationRegion3D
	if not is_instance_valid(tile) or not tile.is_inside_tree():
		return null
	var reaches: Array[Rect2] = [_reach(tile)]
	var walls: Array = bin(parsed["obstruction"], reaches, Vector2.ZERO)[0]
	var held := _gathered_if_changed(tile, site, parsed, walls, entry["holes"])
	if held == null:
		return null
	held.start()
	threaded_total += 1
	baked_total += 1
	return held


## Give the tiles of the held bakes `held` (`prepare`) their polygons, all in this call: the
## steering map takes them in with one synchronisation (about 0.3 ms), so a burst lands whole.
## A tile freed or taken out of the tree meanwhile is skipped.
static func land(held: Array) -> void:
	_join(held)
	var landed: Array = []
	for bake: NavTileBake in held:
		if not is_instance_valid(bake.tile):
			continue
		if bake.tile.is_inside_tree():
			_assign(bake.tile, bake.poly, bake.walls, bake.holes, bake.seams)
			landed.append(bake.tile)
	NavSeams.weld(landed)


## Wait for the threads of the held bakes `held` (the burst is dropped: the match is gone).
static func abandon(held: Array) -> void:
	_join(held)


## Wait for each of `held`'s bakes still running on a worker thread (`late_total` counts those
## that were); a record's `task` is cleared only once its thread is done (`NavTileBake.join`).
static func _join(held: Array) -> void:
	for bake: NavTileBake in held:
		if bake.join():
			late_total += 1


## The world points of the living characters under `root` that are walking (collision layer still
## set, moving at `NavBuilder.REST_SPEED` or more): the complement of `NavBuilder.character_holes`.
static func walking_at(root: Node) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if root == null:
		return out
	for node in root.get_children():
		var body := node as Node2D
		if (body != null
				and body.is_in_group(&"characters")
				and not body.get(&"is_dead")
				and TwinSpace.real_velocity_of(body).length() >= NavBuilder.REST_SPEED):
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


## The source of a bake of `tile` from `walls` (a parse's shape) and `holes`, gathered as far as the
## main thread must (the walls and the footprint; the holes are fused and added by the bake itself,
## `NavTileBake.run`, which reads nothing of the tree): a `NavTileBake`; null when the site has
## nothing to bake.
static func _gathered(
	tile: NavigationRegion3D,
	site: NavSite,
	walls: Dictionary,
	holes: Array,
) -> NavTileBake:
	var job := NavSource.base(site, walls)
	if job.is_empty():
		return null
	var nav_poly: NavigationPolygon = job["poly"]
	nav_poly.baking_rect = _reach(tile)
	nav_poly.border_size = BORDER
	var held := NavTileBake.new()
	held.tile = tile
	held.poly = nav_poly
	held.walls = walls
	held.holes = holes
	held.rect = tile.get_meta(RECT_META)
	held.source = job["source"]
	held.origin = site.house.position
	return held


## `_gathered` for `tile` from the `walls` that reach it (of the parse `parsed`) and its `holes`,
## null when it was baked from these walls and holes already (the holes to within `NavSettle`).
static func _gathered_if_changed(
	tile: NavigationRegion3D,
	site: NavSite,
	parsed: Dictionary,
	walls: Array,
	holes: Array,
) -> NavTileBake:
	if _baked_from(tile, walls, holes):
		return null
	var reached := NavSource.walls(walls, parsed["traversable"], parsed["projected"])
	return _gathered(tile, site, reached, holes)


## Run the bakes of `gathered` (`_gathered`) in parallel, as one group on the worker pool, and wait
## for them all: a lone one is baked where it stands.
static func _bake_together(gathered: Array[NavTileBake]) -> void:
	if gathered.size() < 2:
		for held in gathered:
			held.run_here()
		return
	var group := WorkerThreadPool.add_group_task(func(i: int) -> void:
		gathered[i].run_here(),
		gathered.size(), -1, true, "nav tile bakes")
	WorkerThreadPool.wait_for_group_task_completion(group)


## `tile` takes `poly`, baked from `walls` and `holes`, which it keeps.
static func _assign(
	tile: NavigationRegion3D,
	poly: NavigationPolygon,
	walls: Dictionary,
	holes: Array,
	seams := {},
) -> void:
	NavSeams.take(tile, poly, seams)
	NavPlan.assign(tile, poly)
	tile.set_meta(WALLS_META, walls["obstruction"])
	tile.set_meta(HOLES_META, holes)
	tile.set_meta(SEEN_META, holes)


## The wall outlines (the house's local frame, on whole pixels) of the towers whose walls
## reach any of `reaches`. Each direct child of the house is parsed on its own and kept on `region`
## (`_refreshed`); the ones that reach are parsed again, so a wall dented since is in the result.
## A tower costs a tenth of the whole district's parse, and a tile touches one or two. A collider
## or a wall that is a child of the house itself is no tower's: the whole house is parsed instead.
static func walls_reaching(
	region: NavigationRegion3D,
	site: NavSite,
	reaches: Array[Rect2],
) -> Array:
	var entries: Variant = _refreshed(region, site, reaches)
	if entries == null:
		return NavSource.walls_of(site.house)["obstruction"]
	var out: Array = []
	for entry: Dictionary in entries:
		if _touches(entry, reaches):
			out.append_array(entry["outlines"])
	return out


## `walls_reaching` for every tower, not only those that reach: the ones that reach `reaches` are
## parsed again, and the rest keep what they were.
static func walls_all(
	region: NavigationRegion3D,
	site: NavSite,
	reaches: Array[Rect2],
) -> Array:
	var entries: Variant = _refreshed(region, site, reaches)
	if entries == null:
		return NavSource.walls_of(site.house)["obstruction"]
	var out: Array = []
	for entry: Dictionary in entries:
		out.append_array(entry["outlines"])
	return out


## The parse of each tower of `site`'s house (`_parse_tower`), in the order of the house's children,
## as kept on `region`: a tower never parsed, or one that reaches `reaches`, is read again and
## kept. Null when a body, a wall or a door is a child of the house itself.
static func _refreshed(
	region: NavigationRegion3D,
	site: NavSite,
	reaches: Array[Rect2],
) -> Variant:
	for child in site.house.get_children():
		if child.is_in_group(TwinSpace.BODIES):
			return null
	var cache: Dictionary = region.get_meta(WALL_CACHE_META, {})
	var entries: Array = []
	for child in site.house.get_children():
		if not child is Node2D:
			continue
		var entry: Dictionary = cache.get(child.get_instance_id(), {})
		if entry.is_empty() or _touches(entry, reaches):
			entry = _parse_tower(child as Node2D)
			cache[child.get_instance_id()] = entry
		entries.append(entry)
	region.set_meta(WALL_CACHE_META, cache)
	return entries


## The walls (`NavSource.walls`' shape) a planning re-bake of `site` is made from after the
## furniture went from `before` to `after` (`NavBuilder.furniture_holes`): a house's whole parse; a
## district's every tower, those near a piece that moved parsed afresh (`walls_all`).
static func walls_after(
	region: NavigationRegion3D,
	site: NavSite,
	before: Array,
	after: Array,
) -> Dictionary:
	if not site.bounds.has_area():
		return NavSource.walls_of(site.house)
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
static func _parse_tower(tower: Node2D) -> Dictionary:
	var outlines: Array = NavSource.walls_of(tower, tower.transform)["obstruction"]
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
static func _reach(tile: NavigationRegion3D) -> Rect2:
	return (tile.get_meta(RECT_META) as Rect2).grow(BORDER)


## The `_reach` of each of `tiles`.
static func _reaches(tiles: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for tile: NavigationRegion3D in tiles:
		out.append(_reach(tile))
	return out


## Whether `tile` was last baked from `holes` (never baked: no), to within `NavSettle.TOLERANCE`:
## a piece that settled by a hair is no change. The comparison is always against the holes the tile
## was baked from, so a piece creeping on is due once it adds up to the tolerance; the holes found
## within it are remembered (`SEEN_META`), so the next tick's identical ones are one equality test
## and the shape comparison is made only when a footprint moves.
static func _holes_unchanged(tile: NavigationRegion3D, holes: Array) -> bool:
	if not tile.has_meta(HOLES_META):
		return false
	if tile.get_meta(SEEN_META, null) == holes:
		return true
	var baked: Array = tile.get_meta(HOLES_META)
	if not NavSettle.same_holes(baked, holes):
		return false
	tile.set_meta(SEEN_META, holes)
	return true


## Whether `tile` was last baked from exactly `walls` and `holes` (to `NavSettle.TOLERANCE`; never
## baked: no).
static func _baked_from(tile: NavigationRegion3D, walls: Array, holes: Array) -> bool:
	return (tile.has_meta(WALLS_META)
			and tile.get_meta(WALLS_META) == walls
			and _holes_unchanged(tile, holes))


## A world point on `tile`'s navmesh (the centre of its first polygon), `Vector2.INF` when the tile
## has none (all wall or all furniture): where the map's ready check asks for the tile. `fallback`
## for a steering region that is no tile.
static func probe_of(tile: NavigationRegion3D, fallback: Vector2) -> Vector2:
	if not tile.has_meta(RECT_META):
		return fallback
	var nav_poly := NavPlan.polygon_of(tile)
	if nav_poly == null or nav_poly.get_polygon_count() == 0:
		return Vector2.INF
	var vertices := nav_poly.get_vertices()
	var sum := Vector2.ZERO
	var indices := nav_poly.get_polygon(0)
	for index in indices:
		sum += vertices[index]
	return NavPlan.plan_of(tile.to_global(NavPlan.lift(sum / float(indices.size()))))


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
	var table := _table(cells, span)
	for outline: PackedVector2Array in outlines:
		var box := _outline_bounds(outline)
		box.position -= shift
		var reach := _reach_cells(box, origin, span)
		for y in range(reach.position.y, reach.end.y):
			for x in range(reach.position.x, reach.end.x):
				var i := table[(y - span.position.y) * span.size.x + x - span.position.x]
				if i < 0:
					continue
				intersection_tests += 1
				if reaches[i].intersects(box):
					bins[i].append(outline)
	return bins


## The cells of `span` that `box`, grown by the border, reaches: neighbouring reaches overlap by
## twice the border, so the box is looked up on the ungrown tiles' grid; the caller tests the
## original box against each candidate's actual reach.
static func _reach_cells(box: Rect2, origin: Vector2, span: Rect2i) -> Rect2i:
	var grown := box.grow(BORDER)
	var low := _cell(grown.position, origin).clamp(span.position, span.end - Vector2i.ONE)
	var high := _cell(grown.end, origin).clamp(span.position, span.end - Vector2i.ONE)
	return Rect2i(low, high - low + Vector2i.ONE)


## `cells` (grid cell -> reach index) as a flat table over `span`, row by row; -1 where no tile is.
static func _table(cells: Dictionary, span: Rect2i) -> PackedInt32Array:
	var table := PackedInt32Array()
	table.resize(span.size.x * span.size.y)
	table.fill(-1)
	for cell: Vector2i in cells:
		table[(cell.y - span.position.y) * span.size.x + cell.x - span.position.x] = cells[cell]
	return table


## The cells (low corner, and past the high one) the grid's tiles occupy. A box far larger than the
## district, or a stray point, only ever meets these.
static func _span(cells: Dictionary) -> Rect2i:
	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-(1 << 30), -(1 << 30))
	for cell: Vector2i in cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	return Rect2i(low, high - low + Vector2i.ONE)


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
	var kept: Variant = _bounds.get(outline)
	if kept != null:
		return kept
	if _bounds.size() >= BOUNDS_KEPT:
		_bounds.clear()
	bounds_measures += 1
	var box := NavSource.outline_bounds(outline)
	_bounds[outline] = box
	return box
