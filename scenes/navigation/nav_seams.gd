class_name NavSeams extends RefCounted
## Navigation domain: the borders between a district's steering tiles, welded. Each tile is baked on
## its own and its polygon ends exactly on its rect's border, but along a border the two sides
## need not have the same vertices: a wall's tip or a hole's edge that touches the line stops one
## side's polygon edge where the other side's runs on, so the tile's edge spans a stretch the
## neighbour's is cut into. The NavigationServer joins two polygons by an edge both have (the same
## two cells), and joins anything else only in its edge-connection pass, which costs the whole
## steering map's links rebuilt each time a tile changes (~10 ms in a district). So a tile's border
## edges are split at the vertices its neighbour has there: both sides then hold the same edges, and
## the map needs no pass. The tile keeps the polygon it was baked with (`RAW_META`) and is given a
## split copy of it, so a neighbour's re-bake starts from what the tile baked, not from an earlier
## split. `NavTiles` calls `weld` after it gives tiles their polygons.

## The tile's baked polygon, before any edge was split.
const RAW_META := "nav_tile_raw"
## The tile's border vertices: per side (`LEFT`, `RIGHT`, `TOP`, `BOTTOM`) the sorted coordinates
## along that border of the raw polygon's vertices on it (the house's local frame).
const POINTS_META := "nav_tile_seam_points"
## What the polygon the tile holds is split at: per side, the coordinates (`POINTS_META`'s kind)
## added to its border edges.
const SPLIT_META := "nav_tile_split"
## The tile's polygon as the baker first made it (before any border cell was closed), and what its
## border's walkable stretches are: per side a sorted array of `Vector2(from, to)` along that
## border (the house's local frame).
const BASE_META := "nav_tile_base"
const EDGES_META := "nav_tile_seam_edges"
## What its border's walkable stretches are in the polygon it holds now (`EDGES_META`'s kind).
const NOW_META := "nav_tile_seam_now"
## The stretches of its border the tile's polygon was baked closed over (`EDGES_META`'s kind).
const CLOSED_META := "nav_tile_closed"
## The tile's neighbours: `{ tile, side }`, `side` the tile's own side the neighbour lies across.
const NEIGHBOURS_META := "nav_tile_neighbours"
## A tile's sides. A left or right border runs along y, a top or bottom one along x.
const LEFT := 0
const RIGHT := 1
const TOP := 2
const BOTTOM := 3
## How near (px) a vertex lies to its tile's border to be on it.
const ON_LINE := 0.01
## The most (px squared) the cross product of two edges may be for them to be in one line.
const IN_LINE := 0.01
## The least (px) a stretch of border that is walkable on one side only is to be closed.
const MIN_STRETCH := 0.5
## The most rounds `weld` goes on agreeing borders (a closed corner cell opens a stretch across).
const MAX_ROUNDS := 4

## How many welds ended with a tile still to agree after `MAX_ROUNDS` (a real bake has none).
static var rounds_exhausted_total := 0
## How many edges `_emit` found cut but in one line with the corners round it, so left as they are
## (unwelded): a real bake has none (`steering_seams_welded` checks it).
static var unsplit_total := 0


## The polygon `poly`, just baked for `tile`, is what `tile` was baked to: kept raw, with its
## border's vertices read off (`weld` then splits it against the neighbours').
static func take(tile: NavigationRegion2D, poly: NavigationPolygon) -> void:
	var rect: Rect2 = tile.get_meta(NavTiles.RECT_META)
	_snap_to_borders(poly, rect)
	tile.set_meta(BASE_META, poly)
	tile.set_meta(EDGES_META, _border_edges(poly, rect))
	tile.set_meta(NOW_META, tile.get_meta(EDGES_META))
	tile.set_meta(CLOSED_META, _no_stretches())
	tile.set_meta(RAW_META, poly)
	tile.set_meta(POINTS_META, _border_points(poly, rect))
	tile.set_meta(SPLIT_META, _none())


## Weld the borders of `changed` (tiles that took a new baked polygon, `take`) with their
## neighbours': each of them and each neighbour of theirs is split at the vertices the other side
## of the border has and it has not, and a tile whose split changed is given the new polygon. The
## tiles of one landing are welded together, so the map takes them in with one synchronisation.
##
## First the two sides of each border are made to agree (`_agree`): the voxel baker decides a cell
## on a tile's edge by where its centre lies, so a wall's tip or a hole's edge near a border can
## leave a cell open to one tile and shut to the other, and the walkable stretches of the border
## differ. A tile's border stretches that its neighbour's border does not hold are baked closed
## (the cells of its outermost column), so both sides hold the same stretches, whichever tile was
## baked last.
static func weld(changed: Array) -> void:
	var queue := {}
	for item: Variant in changed:
		if not _live(item):
			continue
		var tile := item as NavigationRegion2D
		queue[tile] = true
		_add_neighbours(queue, tile)
	var fit := {}
	for item: Variant in queue:
		fit[item] = true
		_add_neighbours(fit, item as NavigationRegion2D)
	# Closing a cell at a tile's corner opens a stretch on the border across: each tile that was
	# baked again queues its neighbours for the next round, until none is.
	for _round in MAX_ROUNDS:
		var next := {}
		for item: Variant in queue:
			if _live(item) and _agree(item as NavigationRegion2D):
				_add_neighbours(next, item as NavigationRegion2D)
				_add_neighbours(fit, item as NavigationRegion2D)
				fit[item] = true
		queue = next
		if queue.is_empty():
			break
	if not queue.is_empty():
		rounds_exhausted_total += 1
	for item: Variant in fit:
		if _live(item):
			_fit(item as NavigationRegion2D)


## Add the live neighbours of `tile` to the set `into`.
static func _add_neighbours(into: Dictionary, tile: NavigationRegion2D) -> void:
	for entry: Dictionary in neighbours(tile):
		if _live(entry["tile"]):
			into[entry["tile"]] = true


## Bake `tile` again, from what it was first baked from, with the stretches of its borders its
## neighbours' borders do not hold closed, when those are not the stretches it was last baked
## closed over. Whether it was.
static func _agree(tile: NavigationRegion2D) -> bool:
	if not tile.has_meta(EDGES_META):
		return false
	var base: NavigationPolygon = tile.get_meta(BASE_META)
	if not base.has_meta(NavSource.SOURCE_META):
		return false
	var closed := _stretches_to_close(tile)
	if closed == tile.get_meta(CLOSED_META):
		return false
	var rect: Rect2 = tile.get_meta(NavTiles.RECT_META)
	var poly := base
	if closed != _no_stretches():
		poly = base.duplicate() as NavigationPolygon
		NavSource.bake_polygon(
			poly,
			base.get_meta(NavSource.SOURCE_META),
			base.get_meta(NavSource.ORIGIN_META),
			_cells(closed, rect),
		)
		_snap_to_borders(poly, rect)
	tile.set_meta(CLOSED_META, closed)
	tile.set_meta(RAW_META, poly)
	tile.set_meta(NOW_META, _border_edges(poly, rect))
	tile.set_meta(POINTS_META, _border_points(poly, rect))
	tile.set_meta(SPLIT_META, _none())
	tile.navigation_polygon = poly
	return true


## Per side, the stretches of `tile`'s border that it holds walkable (as it was first baked) where
## the neighbour across holds none (as it holds them now).
static func _stretches_to_close(tile: NavigationRegion2D) -> Array:
	var out := _no_stretches()
	var mine: Array = tile.get_meta(EDGES_META)
	var rect: Rect2 = tile.get_meta(NavTiles.RECT_META)
	for entry: Dictionary in neighbours(tile):
		if not _live(entry["tile"]) or not entry["tile"].has_meta(NOW_META):
			continue
		var side: int = entry["side"]
		var other: NavigationRegion2D = entry["tile"]
		var their_rect: Rect2 = other.get_meta(NavTiles.RECT_META)
		var reach := Vector2(
			maxf(_from(rect, side), _from(their_rect, side)),
			minf(_to(rect, side), _to(their_rect, side)),
		)
		var theirs: Array = (other.get_meta(NOW_META) as Array)[side ^ 1]
		for stretch: Vector2 in mine[side]:
			var within := Vector2(maxf(stretch.x, reach.x), minf(stretch.y, reach.y))
			if within.y - within.x > MIN_STRETCH:
				out[side].append_array(_without(within, theirs))
	return out


## The parts of the stretch `within` that none of the sorted `held` stretches covers.
static func _without(within: Vector2, held: Array) -> Array:
	var out := []
	var at := within.x
	for stretch: Vector2 in held:
		if stretch.y <= at:
			continue
		if stretch.x >= within.y:
			break
		if stretch.x - at > MIN_STRETCH:
			out.append(Vector2(at, stretch.x))
		at = maxf(at, stretch.y)
	if within.y - at > MIN_STRETCH:
		out.append(Vector2(at, within.y))
	return out


## The cells (a rect each, plan frame) of the outermost column on each side that lie along the
## `closed` stretches.
static func _cells(closed: Array, rect: Rect2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var depth := NavSource.CELL_SIZE
	for side in 4:
		for stretch: Vector2 in closed[side]:
			var box: Rect2
			match side:
				LEFT:
					box = Rect2(rect.position.x, stretch.x, depth, stretch.y - stretch.x)
				RIGHT:
					box = Rect2(rect.end.x - depth, stretch.x, depth, stretch.y - stretch.x)
				TOP:
					box = Rect2(stretch.x, rect.position.y, stretch.y - stretch.x, depth)
				_:
					box = Rect2(stretch.x, rect.end.y - depth, stretch.y - stretch.x, depth)
			out.append(
				PackedVector2Array([
					box.position, Vector2(box.end.x, box.position.y),
					box.end, Vector2(box.position.x, box.end.y),
				]),
			)
	return out


## The stretches of `poly`'s edges that lie along each border of `rect`, as `EDGES_META` keeps them:
## sorted, and those that meet joined.
static func _border_edges(poly: NavigationPolygon, rect: Rect2) -> Array:
	var verts := poly.get_vertices()
	var out := _no_stretches()
	for i in poly.get_polygon_count():
		var ring := poly.get_polygon(i)
		for k in ring.size():
			var p := verts[ring[k]]
			var q := verts[ring[(k + 1) % ring.size()]]
			var side := _border_of(p, q, rect)
			if side >= 0:
				var along := [p.y, q.y] if side <= RIGHT else [p.x, q.x]
				out[side].append(Vector2(minf(along[0], along[1]), maxf(along[0], along[1])))
	for side in 4:
		var stretches: Array = out[side]
		stretches.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var joined := []
		for stretch: Vector2 in stretches:
			if not joined.is_empty() and stretch.x <= joined[-1].y + ON_LINE:
				joined[-1] = Vector2(joined[-1].x, maxf(joined[-1].y, stretch.y))
			else:
				joined.append(stretch)
		out[side] = joined
	return out


## The coordinate along its border where `rect` starts, on `side`.
static func _from(rect: Rect2, side: int) -> float:
	return rect.position.y if side <= RIGHT else rect.position.x


## The coordinate along its border where `rect` ends, on `side`.
static func _to(rect: Rect2, side: int) -> float:
	return rect.end.y if side <= RIGHT else rect.end.x


## No stretches on any side.
static func _no_stretches() -> Array:
	return [[], [], [], []]


## Whether `tile` is a tile still in the tree (one freed, or taken out, meanwhile is left as it is).
static func _live(tile: Variant) -> bool:
	if not is_instance_valid(tile):
		return false
	var region := tile as NavigationRegion2D
	return region != null and region.is_inside_tree()


## The tiles that share a stretch of border with `tile`, `{ tile, side }`, kept on the tile (a
## district's tiles stay as they are).
static func neighbours(tile: NavigationRegion2D) -> Array:
	if tile.has_meta(NEIGHBOURS_META):
		return tile.get_meta(NEIGHBOURS_META)
	var out := []
	var rect: Rect2 = tile.get_meta(NavTiles.RECT_META)
	for other in tile.get_parent().get_children():
		var near := other as NavigationRegion2D
		if near == null or near == tile or not near.has_meta(NavTiles.RECT_META):
			continue
		var side := _side_between(rect, near.get_meta(NavTiles.RECT_META))
		if side >= 0:
			out.append({ "tile": near, "side": side })
	tile.set_meta(NEIGHBOURS_META, out)
	return out


## Give `tile` the raw polygon split at what its neighbours have on the borders, when that is not
## what it holds.
static func _fit(tile: NavigationRegion2D) -> void:
	if not tile.has_meta(RAW_META):
		return
	var missing := _missing_points(tile)
	if missing == tile.get_meta(SPLIT_META):
		return
	var raw: NavigationPolygon = tile.get_meta(RAW_META)
	tile.navigation_polygon = raw if missing == _none() else _split(raw, tile, missing)
	tile.set_meta(SPLIT_META, missing)


## Per side, the coordinates of the border vertices the neighbours have and `tile` has not (in a
## cell of its own: two vertices in one cell are one to the server).
static func _missing_points(tile: NavigationRegion2D) -> Array:
	var out := _none()
	var mine: Array = tile.get_meta(POINTS_META)
	var offset := tile.to_global(Vector2.ZERO)
	for entry: Dictionary in neighbours(tile):
		if not _live(entry["tile"]):
			continue
		var other: NavigationRegion2D = entry["tile"]
		if not other.has_meta(POINTS_META):
			continue
		var side: int = entry["side"]
		var shift := offset.y if side <= RIGHT else offset.x
		var theirs: PackedFloat64Array = (other.get_meta(POINTS_META) as Array)[side ^ 1]
		var added := _apart(theirs, mine[side], shift)
		if not added.is_empty():
			var merged := PackedFloat64Array(out[side])
			merged.append_array(added)
			merged.sort()
			out[side] = merged
	return out


## The bake's cell (`NavSource.CELL_SIZE` px, on the world's grid) the coordinate `c` lies in.
static func _cell(c: float) -> int:
	return floori(c / NavSource.CELL_SIZE)


## The coordinates of `theirs` none of `mine` shares a cell with (`shift` the frame's offset along
## the border), one for each cell.
static func _apart(
	theirs: PackedFloat64Array,
	mine: PackedFloat64Array,
	shift: float,
) -> PackedFloat64Array:
	var taken := {}
	for c in mine:
		taken[_cell(c + shift)] = true
	var out := PackedFloat64Array()
	for c in theirs:
		var cell := _cell(c + shift)
		if not taken.has(cell):
			taken[cell] = true
			out.append(c)
	return out


## `raw` with each of its edges along a border cut at the coordinates `missing` (per side) that lie
## strictly inside it and in a cell of their own. A polygon whose edge is cut is not given the cut
## vertices on its ring (three collinear vertices make a degenerate corner, which the server's
## queries answer wrongly): the triangle the edge and the polygon's next corner make is fanned from
## that corner, one triangle to each piece of the edge, and the rest of the polygon stays one.
static func _split(
	raw: NavigationPolygon,
	tile: NavigationRegion2D,
	missing: Array,
) -> NavigationPolygon:
	var cut := {
		"verts": raw.get_vertices(),
		"rect": tile.get_meta(NavTiles.RECT_META),
		"missing": missing,
		"shift": tile.to_global(Vector2.ZERO),
		"made": {},
	}
	var rings: Array[PackedInt32Array] = []
	for i in raw.get_polygon_count():
		_emit(raw.get_polygon(i), cut, rings)
	var poly := raw.duplicate() as NavigationPolygon
	poly.clear_polygons()
	poly.vertices = cut["verts"]
	for ring in rings:
		poly.add_polygon(ring)
	return poly


## Add to `rings` the pieces of the polygon `ring`: itself when none of its edges is cut, else the
## triangles of its first cut edge, fanned from the corner after it (the one before, when that is in
## line with the edge), and then what is left of the polygon, taken the same way.
static func _emit(ring: PackedInt32Array, cut: Dictionary, rings: Array[PackedInt32Array]) -> void:
	var n := ring.size()
	for k in n:
		var chain := _cuts(ring[k], ring[(k + 1) % n], cut)
		if chain.is_empty():
			continue
		var forward := _bends(cut["verts"], ring[k], ring[(k + 1) % n], ring[(k + 2) % n])
		var corner := ring[(k + 2) % n] if forward else ring[(k + n - 1) % n]
		if not forward and not _bends(
				cut["verts"], ring[(k + n - 1) % n], ring[k], ring[(k + 1) % n]):
			if not _emit_across(ring, k, cut, rings):
				continue
			return
		var along: Array[int] = [ring[k]]
		along.append_array(chain)
		along.append(ring[(k + 1) % n])
		for i in along.size() - 1:
			rings.append(
				PackedInt32Array([along[i], along[i + 1], corner]) if forward
				else PackedInt32Array([corner, along[i], along[i + 1]]),
			)
		var rest := ring.duplicate()
		rest.remove_at((k + 1) % n if forward else k)
		if rest.size() >= 3:
			_emit(rest, cut, rings)
		return
	rings.append(ring)


## `_emit` for the cut edge `ring[k]` to `ring[k + 1]` when the corners either side of it are in
## line with it (a merged polygon keeps the collinear vertices of the borders it was made over):
## the triangles of the edge are fanned from the nearest vertex of the ring (by steps round it)
## that is off its line, and the two parts of the polygon left either side of that triangle are
## taken the same way. A polygon is convex, so the triangle lies inside it. False when the ring has
## no such vertex: the edge is left whole (`unsplit_total`).
static func _emit_across(
	ring: PackedInt32Array,
	k: int,
	cut: Dictionary,
	rings: Array[PackedInt32Array],
) -> bool:
	var n := ring.size()
	var a := ring[k]
	var b := ring[(k + 1) % n]
	var at := -1
	for step in range(1, n):
		for j in [(k + 1 + step) % n, (k + n - step + 1) % n]:
			if at < 0 and j != k and j != (k + 1) % n and _bends(cut["verts"], a, b, ring[j]):
				at = j
	if at < 0:
		unsplit_total += 1
		push_error("NavSeams: an edge to cut lies in one line with the corners round it")
		return false
	var corner := ring[at]
	var along: Array[int] = [a]
	along.append_array(_cuts(a, b, cut))
	along.append(b)
	for i in along.size() - 1:
		rings.append(PackedInt32Array([along[i], along[i + 1], corner]))
	var after := PackedInt32Array()
	var i := (k + 1) % n
	while true:
		after.append(ring[i])
		if i == at:
			break
		i = (i + 1) % n
	var before := PackedInt32Array()
	i = at
	while true:
		before.append(ring[i])
		if i == k:
			break
		i = (i + 1) % n
	for part in [after, before]:
		if part.size() >= 3:
			_emit(part, cut, rings)
	return true


## Whether the corner `b` of the points `a`, `b`, `c` is a turn (they are not in one line).
static func _bends(verts: PackedVector2Array, a: int, b: int, c: int) -> bool:
	return absf((verts[b] - verts[a]).cross(verts[c] - verts[b])) > IN_LINE


## The indices of the vertices to put between `a` and `b` of a polygon: when they lie on one border
## of `cut`'s rect, the new vertices (appended to `cut`'s `verts`, one for each place: `made`) of
## that side's `missing` coordinates strictly between them, in the cells neither end is in, from `a`
## to `b`. `cut` is `{ verts, rect, missing, shift (the tile's frame's offset), made }`.
static func _cuts(a: int, b: int, cut: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var from: Vector2 = cut["verts"][a]
	var to: Vector2 = cut["verts"][b]
	var side := _border_of(from, to, cut["rect"])
	if side < 0 or (cut["missing"][side] as PackedFloat64Array).is_empty():
		return out
	var vertical := side <= RIGHT
	var made: Dictionary = cut["made"]
	for c: float in _between(cut, side, from, to):
		var at := Vector2(from.x, c) if vertical else Vector2(c, from.y)
		if not made.has(at):
			made[at] = cut["verts"].size()
			cut["verts"].append(at)
		out.append(made[at])
	return out


## The coordinates `cut` misses on `side` that lie strictly between the points `from` and `to` of
## that border and in no cell of either, ordered from `from` to `to`.
static func _between(cut: Dictionary, side: int, from: Vector2, to: Vector2) -> Array:
	var vertical := side <= RIGHT
	var start := from.y if vertical else from.x
	var end := to.y if vertical else to.x
	var offset: float = cut["shift"].y if vertical else cut["shift"].x
	var cells := [_cell(start + offset), _cell(end + offset)]
	var coords: Array = Array(cut["missing"][side]).filter(
		func(c: float) -> bool:
			return (
				c > minf(start, end) and c < maxf(start, end)
				and not cells.has(_cell(c + offset))
			),
	)
	if start > end:
		coords.reverse()
	return coords


## The side of `rect` both `p` and `q` lie on, -1 when none.
static func _border_of(p: Vector2, q: Vector2, rect: Rect2) -> int:
	if absf(p.x - q.x) <= ON_LINE:
		if absf(p.x - rect.position.x) <= ON_LINE:
			return LEFT
		if absf(p.x - rect.end.x) <= ON_LINE:
			return RIGHT
	if absf(p.y - q.y) <= ON_LINE:
		if absf(p.y - rect.position.y) <= ON_LINE:
			return TOP
		if absf(p.y - rect.end.y) <= ON_LINE:
			return BOTTOM
	return -1


## Put each vertex of `poly` that lies on a border of `rect`, to the baker's precision (it rounds to
## 1/128 px: a vertex a hair inside the line is in the cell before it, and then not the neighbour's
## vertex to the server), exactly on it.
static func _snap_to_borders(poly: NavigationPolygon, rect: Rect2) -> void:
	var verts := poly.get_vertices()
	var moved := false
	for i in verts.size():
		var v := verts[i]
		for line in [rect.position.x, rect.end.x]:
			if absf(v.x - line) <= ON_LINE and v.x != line:
				v.x = line
		for line in [rect.position.y, rect.end.y]:
			if absf(v.y - line) <= ON_LINE and v.y != line:
				v.y = line
		if v != verts[i]:
			verts[i] = v
			moved = true
	if moved:
		poly.vertices = verts


## The vertices of `poly` on each border of `rect`, as `POINTS_META` keeps them.
static func _border_points(poly: NavigationPolygon, rect: Rect2) -> Array:
	var out := _none()
	for v in poly.get_vertices():
		for side in 4:
			if absf((v.x if side <= RIGHT else v.y) - _line(rect, side)) <= ON_LINE:
				out[side].append(v.y if side <= RIGHT else v.x)
	for side in 4:
		out[side].sort()
	return out


## The coordinate of `rect`'s `side`: x for a left or right one, y for a top or bottom one.
static func _line(rect: Rect2, side: int) -> float:
	match side:
		LEFT:
			return rect.position.x
		RIGHT:
			return rect.end.x
		TOP:
			return rect.position.y
	return rect.end.y


## Which side of `rect` the tile `other` lies across, -1 when it shares no stretch of border.
static func _side_between(rect: Rect2, other: Rect2) -> int:
	var along_y := minf(rect.end.y, other.end.y) > maxf(rect.position.y, other.position.y)
	var along_x := minf(rect.end.x, other.end.x) > maxf(rect.position.x, other.position.x)
	if along_y and is_equal_approx(other.end.x, rect.position.x):
		return LEFT
	if along_y and is_equal_approx(other.position.x, rect.end.x):
		return RIGHT
	if along_x and is_equal_approx(other.end.y, rect.position.y):
		return TOP
	if along_x and is_equal_approx(other.position.y, rect.end.y):
		return BOTTOM
	return -1


## An empty split: no coordinates on any side.
static func _none() -> Array:
	var out: Array = []
	for i in 4:
		out.append(PackedFloat64Array())
	return out
