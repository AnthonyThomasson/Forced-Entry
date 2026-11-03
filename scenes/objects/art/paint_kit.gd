extends RefCounted
## Drawing helpers the tower painters share (Objects domain, private): plain filled rectangles and
## discs, 1 px frames, and the marks of painted text and paint (an alpha-blended stroke, a fade,
## wear that knocks paint off a layer). Blocks with a bevel and outline are `TechPainter.box`.


## `col` over the whole of `r`, `height` tall for the cast shadows when given.
static func fill_rect(c: PixelCanvas, r: Rect2i, col: Color, height := -1) -> void:
	c.fill(PixelShape.rounded(r, 0), col, height)


## A disc of `col` centred on `p`.
static func disc(c: PixelCanvas, p: Vector2i, radius: int, col: Color, height := -1) -> void:
	c.fill(PixelShape.disc(p, radius), col, height)


## A 1 px outline of `r` in `col`.
static func frame(c: PixelCanvas, r: Rect2i, col: Color) -> void:
	for x in range(r.position.x, r.end.x):
		c.px(x, r.position.y, col)
		c.px(x, r.end.y - 1, col)
	for y in range(r.position.y, r.end.y):
		c.px(r.position.x, y, col)
		c.px(r.end.x - 1, y, col)


## `col` laid over the pixel at (x, y), alpha-blended (the pixel keeps its own coverage).
static func over(c: PixelCanvas, x: int, y: int, col: Color) -> void:
	if c.has(x, y):
		c.px(x, y, c.at(x, y).blend(col))


## `col` laid over every pixel of `r`.
static func over_rect(c: PixelCanvas, r: Rect2i, col: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			over(c, x, y, col)


## How a mark is painted: its colour, the `width` of a stroke (a glyph's scale, px per glyph
## pixel), the chance `rough` a stamped pixel is skipped so an edge frays like a brush, and whether
## a glyph is cut `stencil`-style.
static func ink(col: Color, width := 1, rough := 0.0, stencil := false) -> Dictionary:
	return { "col": col, "width": width, "rough": rough, "stencil": stencil }


## A line from `a` to `b` painted with `ink_spec` (an `ink`), alpha-blended.
static func stroke(c: PixelCanvas, a: Vector2i, b: Vector2i, ink_spec: Dictionary) -> void:
	var width: int = ink_spec["width"]
	var rough: float = ink_spec["rough"]
	var half := int(width / 2.0)
	for p in PixelShape.line_points(a, b):
		for dy in range(-half, width - half):
			for dx in range(-half, width - half):
				if rough <= 0.0 or c.rng.randf() >= rough:
					over(c, p.x + dx, p.y + dy, ink_spec["col"])


## Scale the alpha of every drawn pixel by `alpha`: a layer painted opaque, faded once, so strokes
## that overlap do not double up.
static func fade(c: PixelCanvas, alpha: float) -> void:
	for y in c.h:
		for x in c.w:
			var col := c.at(x, y)
			if col.a > 0.0:
				col.a *= alpha
				c.px(x, y, col)


## Fade and wear a painted layer, as the floor-marking painters end: `fade` by `opacity`, `wear` by
## `wear_chance`, `wear_depth` and `wear_scratches`, each taken from `opts` when it names it, else
## from `defaults` (a painter's config).
static func age(c: PixelCanvas, opts: Dictionary, defaults: Dictionary) -> void:
	var look := defaults.merged(opts, true)
	fade(c, look["opacity"])
	wear(c, look["wear_chance"], look["wear_depth"], look["wear_scratches"])


## Wear a painted layer: every drawn pixel loses up to `depth` of its alpha `chance` of the time,
## and `scratches` short lines are rubbed through it.
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
