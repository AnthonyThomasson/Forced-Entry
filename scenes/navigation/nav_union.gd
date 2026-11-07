class_name NavUnion extends RefCounted
## Navigation domain: the fusing of overlapping footprints into one outline each, the costliest
## step of gathering a bake. Two footprints whose boxes are apart cannot fuse, so each is merged
## only with the kept outlines whose boxes share one of the cells of a coarse grid with it: a
## district's few hundred pieces cost the merges of the pieces that touch, not a box test against
## every other. The result is the one a merge of every footprint against every kept one gives,
## outline for outline (`tests/navigation/furniture_union_fast_path_test.gd`).

## A grid cell's side, px: a piece of furniture is a cell or so.
const CELL := 128.0

## The outlines fused so far: each kept outline by id, its box and the grid cells its box reaches.
var _kept := {}
var _boxes := {}
var _cells := {}
var _next_id := 0


## `outlines` with every overlapping set fused into one polygon, in the order the fused polygons
## were made. An enclosed gap in a union is filled in.
static func fuse(outlines: Array) -> Array:
	var fusion := NavUnion.new()
	fusion.add_all(outlines)
	return fusion.result()


## Fuse `outlines` in too, in order: a fusion fed its outlines in chunks, a frame at a time, has
## the result one fed them all at once has.
func add_all(outlines: Array) -> void:
	for outline in outlines:
		var cur: PackedVector2Array = outline
		var box := NavSource.outline_bounds(cur)
		var fused := _fuse_with_one(cur, box)
		while not fused.is_empty():
			cur = fused
			box = NavSource.outline_bounds(cur)
			fused = _fuse_with_one(cur, box)
		_kept[_next_id] = cur
		_boxes[_next_id] = box
		for cell in _cells_of(box):
			if not _cells.has(cell):
				_cells[cell] = []
			_cells[cell].append(_next_id)
		_next_id += 1


## The fused outlines, in the order they were made.
func result() -> Array:
	var ids := _kept.keys()
	ids.sort()
	return ids.map(func(id: int) -> PackedVector2Array: return _kept[id])


## `cur` (its box `box`) fused with the first kept outline, lowest id first, that it overlaps and
## forms one polygon with; that outline is dropped from the kept ones. Empty when none.
func _fuse_with_one(cur: PackedVector2Array, box: Rect2) -> PackedVector2Array:
	var near := {}
	for cell in _cells_of(box):
		for id in _cells.get(cell, []):
			near[id] = true
	var ids := near.keys()
	ids.sort()
	for id in ids:
		if not box.intersects(_boxes[id]):
			continue
		var merged := Geometry2D.merge_polygons(cur, _kept[id])
		var outer: Array = merged.filter(_is_outer)
		if outer.size() != 1:
			continue
		for cell in _cells_of(_boxes[id]):
			_cells[cell].erase(id)
		_kept.erase(id)
		_boxes.erase(id)
		return outer[0]
	return PackedVector2Array()


## Whether `poly` is an outer ring of a merge (not a hole in it).
static func _is_outer(poly: PackedVector2Array) -> bool:
	return not Geometry2D.is_polygon_clockwise(poly)


## The grid cells `box` reaches.
static func _cells_of(box: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var first := Vector2i((box.position / CELL).floor())
	var last := Vector2i((box.end / CELL).floor())
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			out.append(Vector2i(x, y))
	return out
