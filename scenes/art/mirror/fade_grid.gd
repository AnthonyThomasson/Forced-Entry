class_name FadeGrid
extends RefCounted
## Art domain, where the wall fade looks for the units near a focus (`wall_fade.gd`): a grid of
## `WallFadeConfig.cell` px cells, each holding every unit whose footprint (grown `half_width`)
## touches it. A fixed unit (a wall segment) is filed once; a movable one (furniture, a door) is
## filed too and re-filed when it is seen to have moved to other cells, a slice of the movable ones
## at a frame (`poll`), so a focus only ever asks the units in the cells it reaches.

const _NONE: Array = []

## How many (unit, cell) entries the grid holds: a test reads that a unit that left is in none.
var entries := 0
## The movable units, in the order they were filed.
var movable: Array[FadeUnit] = []
var _cells: Dictionary = {}
var _cursor := 0


## File `unit` by its box now: its cells, and the movable list when it can move.
func file(unit: FadeUnit) -> void:
	unit.span = _span_of(unit)
	_add(unit)
	if unit.movable:
		movable.append(unit)


## Take `unit` out of every cell it is in (and the movable list); `span` still says where it was.
func unfile(unit: FadeUnit) -> void:
	_remove(unit)
	if unit.movable:
		movable.erase(unit)


## The units filed in cell (`cx`, `cz`), none for a cell with none: never change what it returns.
func at(cx: int, cz: int) -> Array:
	return _cells.get(key_of(cx, cz), _NONE)


## Whether `unit` is in any cell.
func holds(unit: FadeUnit) -> bool:
	for cx in range(unit.span.position.x, unit.span.end.x):
		for cz in range(unit.span.position.y, unit.span.end.y):
			if at(cx, cz).has(unit):
				return true
	return false


## The cell a ground coordinate (3D units) is in.
func cell_of(coordinate: float) -> int:
	return floori(coordinate / (WallFadeConfig.cell * RenderConfig.unit))


## One number for a cell, for the dictionary (it needs more than 32 bits: do not store it narrower).
func key_of(cx: int, cz: int) -> int:
	return (cx + 32_768) * 65_536 + (cz + 32_768)


## Check the next slice of the movable units (a whole round every `WallFadeConfig.poll_frames`
## frames) and file again the ones whose anchor moved to other cells.
func poll() -> void:
	var count := movable.size()
	if count == 0:
		return
	var take := ceili(float(count) / float(maxi(WallFadeConfig.poll_frames, 1)))
	for i in take:
		_cursor = (_cursor + 1) % count
		var unit := movable[_cursor]
		if is_instance_valid(unit.anchor) and unit.anchor.global_transform != unit.last:
			unit.place()
			var span := _span_of(unit)
			if span != unit.span:
				_remove(unit)
				unit.span = span
				_add(unit)


## The cells `unit`'s box, grown `half_width`, touches.
func _span_of(unit: FadeUnit) -> Rect2i:
	var pad := WallFadeConfig.half_width * RenderConfig.unit
	var low := unit.box.lowest() - Vector2(pad, pad)
	var high := unit.box.highest() + Vector2(pad, pad)
	var first := Vector2i(cell_of(low.x), cell_of(low.y))
	return Rect2i(first, Vector2i(cell_of(high.x), cell_of(high.y)) - first + Vector2i.ONE)


## Put `unit` in every cell of its span.
func _add(unit: FadeUnit) -> void:
	for cx in range(unit.span.position.x, unit.span.end.x):
		for cz in range(unit.span.position.y, unit.span.end.y):
			var key := key_of(cx, cz)
			if not _cells.has(key):
				_cells[key] = []
			(_cells[key] as Array).append(unit)
			entries += 1


## Take `unit` out of every cell of its span it is in.
func _remove(unit: FadeUnit) -> void:
	for cx in range(unit.span.position.x, unit.span.end.x):
		for cz in range(unit.span.position.y, unit.span.end.y):
			var key := key_of(cx, cz)
			var filed: Array = _cells.get(key, _NONE)
			if not filed.has(unit):
				continue
			filed.erase(unit)
			entries -= 1
			if filed.is_empty():
				_cells.erase(key)
