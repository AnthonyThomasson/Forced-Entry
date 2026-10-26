class_name PixelConvexShape extends PixelShape
## A shape convex along both axes (rounded rects, ellipses), kept as one span per row and per
## column. Membership, depth (the nearest of the four axis exits) and normal are O(1), and the
## edge band is enumerated directly from the span ends.

## Per row: first inside x (absolute); an empty row has x1 <= x0.
var _x0 := PackedInt32Array()
## Per row: one past the last inside x.
var _x1 := PackedInt32Array()
## Per column: first inside y (absolute).
var _y0 := PackedInt32Array()
## Per column: one past the last inside y.
var _y1 := PackedInt32Array()


func _init(rect: Rect2i, x0: PackedInt32Array, x1: PackedInt32Array, y0: PackedInt32Array,
		y1: PackedInt32Array) -> void:
	super(rect)
	_x0 = x0
	_x1 = x1
	_y0 = y0
	_y1 = y1


## True if (x, y) is inside the shape.
func has(x: int, y: int) -> bool:
	var ly := y - bounds.position.y
	if ly < 0 or ly >= bounds.size.y:
		return false
	return x >= _x0[ly] and x < _x1[ly]


## How many steps in from the edge (x, y) sits (1 = the edge ring), or 0 if outside.
func depth(x: int, y: int) -> int:
	if not has(x, y):
		return 0
	var ly := y - bounds.position.y
	var lx := x - bounds.position.x
	var m := mini(mini(x - _x0[ly], _x1[ly] - 1 - x), mini(y - _y0[lx], _y1[lx] - 1 - y))
	return maxi(1, m + 1)


## The outward edge normal nearest (x, y): the sum of the axis directions exiting soonest.
func normal(x: int, y: int) -> Vector2:
	if not has(x, y):
		return Vector2.ZERO
	var ly := y - bounds.position.y
	var lx := x - bounds.position.x
	var d := [x - _x0[ly], _x1[ly] - 1 - x, y - _y0[lx], _y1[lx] - 1 - y]
	var m: int = mini(mini(d[0], d[1]), mini(d[2], d[3]))
	var sum := Vector2.ZERO
	for i in 4:
		if d[i] == m:
			sum += Vector2(STEPS[i])
	return sum.normalized()


## The inside run of each row, as flat [y, x0, x1) triples.
func spans() -> PackedInt32Array:
	var out := PackedInt32Array()
	for ly in bounds.size.y:
		if _x1[ly] > _x0[ly]:
			out.append_array([bounds.position.y + ly, _x0[ly], _x1[ly]])
	return out


## Pixels within `k` of a row end or a column end (each listed once), as flat [x, y] pairs.
func edge_pixels(k: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for ly in bounds.size.y:
		var a := _x0[ly]
		var b := _x1[ly]
		if b <= a:
			continue
		var y := bounds.position.y + ly
		var left_end := mini(a + k, b)
		for x in range(a, left_end):
			out.append_array([x, y])
		for x in range(maxi(b - k, left_end), b):
			out.append_array([x, y])
	for lx in bounds.size.x:
		var a := _y0[lx]
		var b := _y1[lx]
		if b <= a:
			continue
		var x := bounds.position.x + lx
		var top_end := mini(a + k, b)
		for y in range(a, top_end) + range(maxi(b - k, top_end), b):
			if not has(x, y):
				continue
			var ly: int = y - bounds.position.y
			if x - _x0[ly] < k or _x1[ly] - 1 - x < k:
				continue  # The row pass already listed it.
			out.append_array([x, y])
	return out
