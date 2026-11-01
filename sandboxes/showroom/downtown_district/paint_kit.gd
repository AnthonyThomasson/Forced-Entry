extends RefCounted
## Drawing helpers the showroom's painters share, over `PixelCanvas` (Art, interface 12): filled
## and bevelled blocks in the game's tone ramp (`ArtSurfaceConfig.tones`), alpha-blended marks for
## overlays, a wobbly thick line for painted strokes, and the wear that knocks paint off a layer.

const NEON_CYAN := Color(0.15, 0.92, 1.0)
const NEON_MAGENTA := Color(1.0, 0.2, 0.72)
const NEON_AMBER := Color(1.0, 0.72, 0.2)


## Fill `r` with `col` (a plain rectangle), raised to `height` for the cast shadows when set.
static func fill_rect(c: PixelCanvas, r: Rect2i, col: Color, height := -1) -> void:
	c.fill(PixelShape.rounded(r, 0), col, height)


## A bevelled, outlined block of `base` in `r`, `height` high for the cast shadows.
static func block(c: PixelCanvas, r: Rect2i, base: Color, height := 3, radius := 1) -> void:
	var t := ArtSurfaceConfig.tones(base)
	var s := PixelShape.rounded(r, radius)
	c.fill(s, base, height)
	c.bevel(s, 1, 1, t.highlight, t.dark)
	c.outline(s, t.outline)


## `col` laid over the pixel at (x, y) (alpha-blended; the pixel keeps its own coverage).
static func over(c: PixelCanvas, x: int, y: int, col: Color) -> void:
	if c.has(x, y):
		c.px(x, y, c.at(x, y).blend(col))


## `col` laid over every pixel of `r`.
static func over_rect(c: PixelCanvas, r: Rect2i, col: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			over(c, x, y, col)


## How something is painted: its colour, the `width` of a stroke (a glyph's scale, in px per glyph
## pixel), the chance `rough` a stamped pixel is skipped so an edge frays like a brush, and whether
## a glyph is cut `stencil`-style.
static func ink(col: Color, width := 1, rough := 0.0, stencil := false) -> Dictionary:
	return { "col": col, "width": width, "rough": rough, "stencil": stencil }


## A line from `a` to `b` painted with `ink` (alpha-blended).
static func stroke(c: PixelCanvas, a: Vector2i, b: Vector2i, ink_spec: Dictionary) -> void:
	var width: int = ink_spec["width"]
	var rough: float = ink_spec["rough"]
	var half := int(width / 2.0)
	for p in PixelShape.line_points(a, b):
		for dy in range(-half, width - half):
			for dx in range(-half, width - half):
				if rough <= 0.0 or c.rng.randf() >= rough:
					over(c, p.x + dx, p.y + dy, ink_spec["col"])


## Wear a painted layer: every drawn pixel loses `chance` of the time up to `depth` of its alpha,
## and `scratches` short lines are rubbed clean through it.
static func wear(c: PixelCanvas, chance: float, depth: float, scratches := 0) -> void:
	for y in c.h:
		for x in c.w:
			var col := c.at(x, y)
			if col.a > 0.0 and c.rng.randf() < chance:
				col.a *= 1.0 - c.rng.randf_range(depth * 0.4, depth)
				c.px(x, y, col)
	for _i in scratches:
		var a := Vector2i(c.rng.randi_range(0, c.w - 1), c.rng.randi_range(0, c.h - 1))
		var b := a + Vector2i(c.rng.randi_range(-18, 18), c.rng.randi_range(-8, 8))
		for p in PixelShape.line_points(a, b):
			var col := c.at(p.x, p.y)
			if col.a > 0.0:
				col.a *= 0.25
				c.px(p.x, p.y, col)


## Darken the already drawn pixels with `count` grime blotches of up to `radius` px.
static func grime(c: PixelCanvas, count: int, radius: int, amount: float) -> void:
	for _i in count:
		var o := Vector2i(c.rng.randi_range(0, c.w - 1), c.rng.randi_range(0, c.h - 1))
		var r := c.rng.randi_range(maxi(1, int(radius / 2.0)), radius)
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				var d := sqrt(x * x + y * y) / float(r)
				var p := o + Vector2i(x, y)
				if d <= 1.0 and c.rng.randf() < 0.7 - d * 0.4 and c.covered(p.x, p.y):
					c.px(p.x, p.y, c.at(p.x, p.y).darkened(amount * (1.0 - d * 0.6)))


## `count` rust specks of the run-down palette over the drawn pixels.
static func rust(c: PixelCanvas, count: int) -> void:
	for _i in count:
		var p := Vector2i(c.rng.randi_range(0, c.w - 1), c.rng.randi_range(0, c.h - 1))
		for _k in c.rng.randi_range(2, 6):
			if c.covered(p.x, p.y):
				var rust_col := Color(
					0.52,
					0.26,
					0.12,
				) if c.rng.randf() < 0.6 else Color(0.66, 0.36, 0.16)
				c.px(p.x, p.y, c.at(p.x, p.y).lerp(rust_col, 0.7))
			p += Vector2i(c.rng.randi_range(-1, 1), c.rng.randi_range(-1, 1))


## A 1px rectangle outline of `r` in `col`.
static func frame(c: PixelCanvas, r: Rect2i, col: Color) -> void:
	for x in range(r.position.x, r.end.x):
		c.px(x, r.position.y, col)
		c.px(x, r.end.y - 1, col)
	for y in range(r.position.y, r.end.y):
		c.px(r.position.x, y, col)
		c.px(r.end.x - 1, y, col)


## A disc of `col` centred on `p`.
static func disc(c: PixelCanvas, p: Vector2i, radius: int, col: Color, height := -1) -> void:
	c.fill(PixelShape.disc(p, radius), col, height)


## Scale the alpha of every drawn pixel by `alpha`: a layer painted in opaque paint, faded once, so
## strokes that overlap do not double up.
static func fade(c: PixelCanvas, alpha: float) -> void:
	for y in c.h:
		for x in c.w:
			var col := c.at(x, y)
			if col.a > 0.0:
				col.a *= alpha
				c.px(x, y, col)
