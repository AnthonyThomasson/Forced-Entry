class_name NavBorder extends RefCounted
## Navigation domain: the border cells of a steering tile's bake. A tile is baked with a border (the
## baker sees past its edge), and the two tiles that meet on an edge must agree on which cells of
## the two columns along it are held. The voxel baker takes a cell as held by where its centre lies,
## so a wall's tip or a floor's edge that ends between the two columns leaves one tile's column
## open and its neighbour's shut. `runs` finds the cells a tile holds on every side, as rectangles
## the bake adds as obstructions (`NavSource.bake_polygon`); a side is 0 left, 1 right, 2 top,
## 3 bottom.

## How near (px) to a polygon's edge a cell's centre is asked of `Geometry2D.is_point_in_polygon`
## rather than read from where the polygon crosses the line of centres (`_fill`): the engine's
## answer for a point on an edge differs from one point of it to the next, and the bake follows it.
const TIE_DISTANCE := 0.05
## The way out of a tile across each side (0 left, 1 right, 2 top, 3 bottom).
const OUTWARD: Array[Vector2] = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]


## A tile's own rect (the baking rect less its border) on whole cells of the world's grid.
static func tile_rect(reach: Rect2, border: float, origin: Vector2) -> Rect2:
	var inner := reach.grow(-border)
	var cell := NavSource.CELL_SIZE
	var low := ((inner.position + origin) / cell).round() * cell - origin
	var high := ((inner.end + origin) / cell).round() * cell - origin
	return Rect2(low, high - low)


## The cells of the tile's own outermost column that are held, or whose neighbour's cell across the
## border is held: by an obstruction, or by lying outside the floor (a cell is held by where its
## centre lies). With the column shut on both sides the two tiles' walkable stretches along the
## border agree. Neighbouring held cells are one rectangle (the baker rasterises the same cells,
## with a fraction of the polygons). `boxes` are the bounds of `obstructions`.
static func runs(
	obstructions: Array[PackedVector2Array],
	boxes: Array[Rect2],
	floors: Array[PackedVector2Array],
	tile: Rect2,
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var floor_boxes := _boxes(floors)
	for side in 4:
		var band := strip_across(tile, side).merge(strip_inside(tile, side))
		var blocks: Array[PackedVector2Array] = []
		for i in _touching(boxes, band):
			blocks.append(obstructions[i])
		var near: Array[PackedVector2Array] = []
		for i in _touching(floor_boxes, band):
			near.append(floors[i])
		out.append_array(_side_squares(blocks, near, tile, side))
	return out


## The strip of `tile`'s own outermost column on `side`.
static func strip_inside(tile: Rect2, side: int) -> Rect2:
	var thick := Vector2(NavSource.CELL_SIZE, tile.size.y)
	if side > 1:
		thick = Vector2(tile.size.x, NavSource.CELL_SIZE)
	return Rect2(tile.end - thick if side % 2 == 1 else tile.position, thick)


## The strip of cells just outside `tile`'s `side`.
static func strip_across(tile: Rect2, side: int) -> Rect2:
	var inside := strip_inside(tile, side)
	return Rect2(inside.position + OUTWARD[side] * NavSource.CELL_SIZE, inside.size)


## The cells of `tile`'s outermost column on `side` from the one level with `from` to the one level
## with `to` (along the border), as one rectangle.
static func run_inside(tile: Rect2, side: int, from: float, to: float) -> PackedVector2Array:
	var strip := strip_inside(tile, side)
	var half := NavSource.CELL_SIZE * 0.5
	var box := Rect2(strip.position.x, from - half, strip.size.x, to - from + half * 2.0)
	if side > 1:
		box = Rect2(from - half, strip.position.y, to - from + half * 2.0, strip.size.y)
	return PackedVector2Array([
		box.position, Vector2(box.end.x, box.position.y), box.end,
		Vector2(box.position.x, box.end.y),
	])


## The centre of the first cell along `side` of `tile`.
static func _first(tile: Rect2, side: int) -> float:
	return (tile.position.y if side <= 1 else tile.position.x) + NavSource.CELL_SIZE * 0.5


## How many cells lie along `side` of `tile`.
static func _count(tile: Rect2, side: int) -> int:
	return roundi((tile.size.y if side <= 1 else tile.size.x) / NavSource.CELL_SIZE)


## `runs` along the `side` of `tile`, from the polygons `blocks` and `floors` that reach its two
## columns. A cell is a byte of `held`, found a line of cell centres at a time (`_fill`), not a
## point at a time. When the floor holds the whole band only a cell in a block can be held, and a
## band no floor reaches is held whole.
static func _side_squares(
	blocks: Array[PackedVector2Array],
	floors: Array[PackedVector2Array],
	tile: Rect2,
	side: int,
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var first := _first(tile, side)
	if floors.is_empty():
		var last := first + NavSource.CELL_SIZE * (_count(tile, side) - 1)
		out.append(run_inside(tile, side, first, last))
		return out
	var covered := _covers(floors, strip_across(tile, side).merge(strip_inside(tile, side)))
	if covered and blocks.is_empty():
		return out
	var held := PackedByteArray()
	held.resize(_count(tile, side))
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
	var first := _first(tile, side)
	var strip := strip_across(tile, side) if across else strip_inside(tile, side)
	var at := strip.get_center().x if along else strip.get_center().y
	var held := PackedByteArray()
	held.resize(_count(tile, side))
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
## each stretch of them one rectangle (`run_inside`).
static func _runs_of(
	held: PackedByteArray,
	tile: Rect2,
	side: int,
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var first := _first(tile, side)
	var run_from := -INF
	for k in held.size():
		var mid := first + NavSource.CELL_SIZE * k
		if held[k] == 1 and run_from == -INF:
			run_from = mid
		elif held[k] == 0 and run_from != -INF:
			out.append(run_inside(tile, side, run_from, mid - NavSource.CELL_SIZE))
			run_from = -INF
	if run_from != -INF:
		var last := first + NavSource.CELL_SIZE * (held.size() - 1)
		out.append(run_inside(tile, side, run_from, last))
	return out


## Set to 1 each cell of `cells` (the centres `first` and every `NavSource.CELL_SIZE` on, along the
## y axis when `vertical`, else the x axis, on the line `at` across it) that lies in one of
## `polygons` (what `Geometry2D.is_point_in_polygon` answers): the polygon's crossings with the
## line, paired in order, are the stretches inside it. A centre on or within `TIE_DISTANCE` of an
## edge is no stretch's to decide (the engine's answer on an edge is not the same at every point of
## it): it is asked of the engine, one call each.
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
			var centre := first + NavSource.CELL_SIZE * ties[i]
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


## The cells (of `count`, centres `first` and every `NavSource.CELL_SIZE` on) whose centre is in a
## stretch of `windows` (pairs: from, to).
static func _cells_in(windows: PackedFloat64Array, first: float, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(0, windows.size() - 1, 2):
		for k in range(
			maxi(ceili((windows[i] - first) / NavSource.CELL_SIZE), 0),
			mini(floori((windows[i + 1] - first) / NavSource.CELL_SIZE), count - 1) + 1,
		):
			out.append(k)
	return out


## Set to 1 the cells of `cells` whose centre lies between `low` and `high` (either order).
static func _mark(cells: PackedByteArray, low: float, high: float, first: float) -> void:
	if low > high:
		var swap := low
		low = high
		high = swap
	var from := maxi(ceili((low - first) / NavSource.CELL_SIZE), 0)
	var to := mini(floori((high - first) / NavSource.CELL_SIZE), cells.size() - 1)
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
