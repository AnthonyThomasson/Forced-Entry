class_name PixelShape extends RefCounted
## A pixel region rasterized from a point test into a mask (any shape, e.g. bowed()). Answers
## membership, its row spans (for filling), and per pixel how far in from the edge it sits and the
## outward normal there — from run lengths along the axes and diagonals, built on first use.
## Also the shapes' static factories: `rounded`, `ellipse` and `disc` (convex: `PixelConvexShape`),
## `bowed` (a mask), and `line_points`, the one Bresenham walk `PixelCanvas.line` draws along.

## Straight steps first, then diagonals: a diagonal only decides the edge where no straight
## step reaches it as soon (rounded corners).
const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]

## Bounding rect (absolute art px).
var bounds: Rect2i
## 1 per inside pixel of `bounds`.
var _mask := PackedByteArray()
## Steps to the first outside pixel (1 = edge ring); 0 outside.
var _depth := PackedByteArray()
## Outward edge normal at that depth.
var _normal := PackedVector2Array()


func _init(rect: Rect2i, test: Callable = Callable()) -> void:
	bounds = rect
	if not test.is_valid():
		return
	_mask.resize(maxi(rect.get_area(), 0))
	for y in rect.size.y:
		for x in rect.size.x:
			_mask[y * rect.size.x + x] = (1
					if test.call(rect.position.x + x, rect.position.y + y)
					else 0)


## `r` with its corners rounded to `radius` (0 = a plain rect).
static func rounded(r: Rect2i, radius: int) -> PixelShape:
	var rad := clampi(radius, 0, int(mini(r.size.x, r.size.y) / 2.0))
	var x0 := PackedInt32Array()
	var x1 := PackedInt32Array()
	var y0 := PackedInt32Array()
	var y1 := PackedInt32Array()
	for ly in r.size.y:
		var cut := _corner_cut(ly, r.size.y, rad)
		x0.append(r.position.x + cut if cut >= 0 else 0)
		x1.append(r.end.x - cut if cut >= 0 else 0)
	for lx in r.size.x:
		var cut := _corner_cut(lx, r.size.x, rad)
		y0.append(r.position.y + cut if cut >= 0 else 0)
		y1.append(r.end.y - cut if cut >= 0 else 0)
	return PixelConvexShape.new(r, x0, x1, y0, y1)


## How many px a rounded corner trims from each end of line `i` of `n` (rows or columns), or -1
## if the line is wholly outside. Inside means dx² + dy² ≤ rad² + rad from the corner centre.
static func _corner_cut(i: int, n: int, rad: int) -> int:
	if rad <= 0:
		return 0
	var d := i - clampi(i, rad, n - 1 - rad)
	if d == 0:
		return 0
	var allowance := rad * rad + rad - d * d
	if allowance < 0:
		return -1
	return maxi(0, rad - floori(sqrt(float(allowance))))


## The ellipse inscribed in `r`.
static func ellipse(r: Rect2i) -> PixelShape:
	var x0 := PackedInt32Array()
	var x1 := PackedInt32Array()
	var y0 := PackedInt32Array()
	var y1 := PackedInt32Array()
	for ly in r.size.y:
		var half := _ellipse_half(ly, r.size.y, r.size.x)
		x0.append(r.position.x + roundi(r.size.x * 0.5 - half))
		x1.append(r.position.x + roundi(r.size.x * 0.5 + half))
	for lx in r.size.x:
		var half := _ellipse_half(lx, r.size.x, r.size.y)
		y0.append(r.position.y + roundi(r.size.y * 0.5 - half))
		y1.append(r.position.y + roundi(r.size.y * 0.5 + half))
	return PixelConvexShape.new(r, x0, x1, y0, y1)


## Half the chord of an ellipse (`span` across, `n` lines along) through line `i`'s centre.
static func _ellipse_half(i: int, n: int, span: int) -> float:
	var v := (i + 0.5 - n * 0.5) / (n * 0.5)
	return 0.0 if absf(v) >= 1.0 else span * 0.5 * sqrt(1.0 - v * v)


## A circle of `radius` centred on `c`.
static func disc(c: Vector2i, radius: int) -> PixelShape:
	return ellipse(Rect2i(c - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1)))


## A rounded bar across `r` whose ends sag `bow` px toward +y (a curved chair rail); its
## thickness is r.size.y - bow.
static func bowed(r: Rect2i, radius: int, bow: int) -> PixelShape:
	var bar := Rect2i(r.position, Vector2i(r.size.x, maxi(1, r.size.y - bow)))
	var half := maxf(1.0, (r.size.x - 1) * 0.5)
	var test := func(x: int, y: int) -> bool:
		var t := (x - r.position.x - half) / half
		return _in_rounded(bar, radius, x, y - roundi(bow * t * t))
	return PixelShape.new(r, test)


## True if (x, y) lies inside `r` with its corners rounded to `radius`.
static func _in_rounded(r: Rect2i, radius: int, x: int, y: int) -> bool:
	if x < r.position.x or y < r.position.y or x >= r.end.x or y >= r.end.y:
		return false
	var rad := mini(radius, int(mini(r.size.x, r.size.y) / 2.0))
	if rad <= 0:
		return true
	var dx := x - clampi(x, r.position.x + rad, r.end.x - 1 - rad)
	var dy := y - clampi(y, r.position.y + rad, r.end.y - 1 - rad)
	return dx * dx + dy * dy <= rad * rad + rad


## The points of a 1 px line from `a` to `b` (Bresenham), `a` first and `b` last.
static func line_points(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := (b - a).abs()
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := d.x - d.y
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		var e2 := err * 2
		if e2 > -d.y:
			err -= d.y
			p.x += sx
		if e2 < d.x:
			err += d.x
			p.y += sy
	return out


## True if (x, y) is inside the shape.
func has(x: int, y: int) -> bool:
	var lx := x - bounds.position.x
	var ly := y - bounds.position.y
	if lx < 0 or ly < 0 or lx >= bounds.size.x or ly >= bounds.size.y:
		return false
	return _mask[ly * bounds.size.x + lx] == 1


## How many steps in from the edge (x, y) sits (1 = the edge ring), or 0 if outside.
func depth(x: int, y: int) -> int:
	if _depth.is_empty():
		_build_edges()
	return _depth[_index(x, y)] if has(x, y) else 0


## The outward edge normal nearest (x, y) (unit; ZERO outside).
func normal(x: int, y: int) -> Vector2:
	if _depth.is_empty():
		_build_edges()
	return _normal[_index(x, y)] if has(x, y) else Vector2.ZERO


## The inside runs of each row, as flat [y, x0, x1) triples.
func spans() -> PackedInt32Array:
	var out := PackedInt32Array()
	var bw := bounds.size.x
	for ly in bounds.size.y:
		var x := 0
		while x < bw:
			if _mask[ly * bw + x] == 0:
				x += 1
				continue
			var x0 := x
			while x < bw and _mask[ly * bw + x] == 1:
				x += 1
			out.append_array([
				bounds.position.y + ly,
				bounds.position.x + x0,
				bounds.position.x + x,
			])
	return out


## The inside pixels within `k` of the edge (depth 1..k), each once, as flat [x, y] pairs.
func edge_pixels(k: int) -> PackedInt32Array:
	if _depth.is_empty():
		_build_edges()
	var out := PackedInt32Array()
	var i := 0
	for ly in bounds.size.y:
		for lx in bounds.size.x:
			var d := _depth[i]
			if d != 0 and d <= k:
				out.append(bounds.position.x + lx)
				out.append(bounds.position.y + ly)
			i += 1
	return out


## Mask index of (x, y), which must lie inside the bounds.
func _index(x: int, y: int) -> int:
	return (y - bounds.position.y) * bounds.size.x + (x - bounds.position.x)


## Per step direction, sweep the mask so each inside pixel learns how many inside pixels run on
## from it that way; the first outside pixel is one past that run. Depth is the nearest exit
## over the straight steps (diagonals only where strictly sooner); the normal sums the exiting
## steps. Each sweep walks the rows and columns away from the pixel it reads, so a pixel's
## neighbour that way is done before it.
func _build_edges() -> void:
	var runs: Array[PackedInt32Array] = []
	for d in STEPS:
		runs.append(_run_along(d))
	_fill_edges(runs)


## Per inside pixel, how many inside pixels run on from it in step direction `d`.
func _run_along(d: Vector2i) -> PackedInt32Array:
	var bh := bounds.size.y
	var run := PackedInt32Array()
	run.resize(bounds.size.x * bh)
	var y := bh - 1 if d.y > 0 else 0
	var y_step := -1 if d.y > 0 else 1
	for _row in bh:
		var qy := y + d.y
		if qy >= 0 and qy < bh:
			_sweep_row(run, d, y)
		y += y_step
	return run


## `_run_along`'s sweep of row `y` into `run`, away from the neighbour each pixel reads.
func _sweep_row(run: PackedInt32Array, d: Vector2i, y: int) -> void:
	var bw := bounds.size.x
	var x_from := bw - 1 if d.x > 0 else 0
	var x_step := -1 if d.x > 0 else 1
	# The columns whose neighbour that way is inside the bounds.
	var x_lo := 1 if d.x < 0 else 0
	var x_hi := bw - 2 if d.x > 0 else bw - 1
	var step := d.y * bw + d.x
	var i := y * bw + x_from
	var x := x_from
	for _col in bw:
		if x >= x_lo and x <= x_hi and _mask[i] == 1 and _mask[i + step] == 1:
			run[i] = run[i + step] + 1
		x += x_step
		i += x_step


## Depth and normal of every inside pixel from the runs along each of `STEPS`, in its order.
func _fill_edges(runs: Array[PackedInt32Array]) -> void:
	var n := _mask.size()
	_depth.resize(n)
	_normal.resize(n)
	for i in n:
		if _mask[i] == 0:
			continue
		var k := mini(mini(runs[0][i], runs[1][i]), mini(runs[2][i], runs[3][i])) + 1
		var k_diag := mini(mini(runs[4][i], runs[5][i]), mini(runs[6][i], runs[7][i])) + 1
		# The straight steps decide, or the diagonals where strictly sooner.
		var first := 0
		if k_diag < k:
			k = k_diag
			first = 4
		var sum := Vector2.ZERO
		for j in range(first, first + 4):
			if runs[j][i] + 1 == k:
				sum += Vector2(STEPS[j])
		_depth[i] = mini(k, 255)
		_normal[i] = sum.normalized()
