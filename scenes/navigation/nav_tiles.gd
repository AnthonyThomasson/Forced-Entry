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


## The tiles that cover `footprint` (the house's local frame), row by row; the last of a row or a
## column is the remainder.
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


## The name of the tile region over `rect`, a tile of the grid over `footprint`.
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
	var baked := 0
	for k in due.size():
		var tile: NavigationRegion2D = tiles[due[k]]
		if _baked_from(tile, wall_bins[k], hole_bins[due[k]]):
			continue
		var reached := NavSource.walls(wall_bins[k], parsed["traversable"], parsed["projected"])
		if _bake_tile(tile, site, reached, hole_bins[due[k]]):
			baked += 1
	return baked


## `tile` baked from `walls` (a parse's shape) and the `holes` that reach it, which it keeps to see
## whether they change. False when the site has nothing to bake.
static func _bake_tile(
	tile: NavigationRegion2D,
	site: NavSite,
	walls: Dictionary,
	holes: Array,
) -> bool:
	var job := NavSource.job(site, holes, [], walls)
	if job.is_empty():
		return false
	var nav_poly: NavigationPolygon = job["poly"]
	nav_poly.baking_rect = _reach(tile)
	nav_poly.border_size = BORDER
	tile.navigation_polygon = NavSource.bake(job, site.house.position)
	tile.set_meta(WALLS_META, walls["obstruction"])
	tile.set_meta(HOLES_META, holes)
	return true


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
## the house's position).
static func bin(outlines: Array, reaches: Array[Rect2], shift: Vector2) -> Array:
	var bins: Array = []
	for _reach_rect in reaches:
		bins.append([])
	for outline: PackedVector2Array in outlines:
		var box := NavSource.outline_bounds(outline)
		box.position -= shift
		for i in reaches.size():
			if reaches[i].intersects(box):
				bins[i].append(outline)
	return bins
