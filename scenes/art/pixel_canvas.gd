class_name PixelCanvas extends RefCounted
## Pixel-art drawing surface (Art domain) that every painter draws on: an RGBA8 Image at
## art resolution plus coverage and height layers, and the primitives the painters compose —
## filled shapes, light-aware bevels, outlines, lines, cast shadows and material surface finishes
## (wood grain, brushed metal, stone flecks, glaze glare, fabric weave). Coordinates are integer
## art pixels; writes outside the image are ignored. Texture primitives touch only drawn pixels,
## so they never spill past a piece's silhouette. Fills run as native row spans and bevels visit
## only a shape's edge band, so large pieces stay cheap to paint.

const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
## Coverage-layer value for a drawn pixel.
const _ON := Color(1.0, 0.0, 0.0)

## The art, at art resolution.
var img: Image
## Image width (art px).
var w: int
## Image height (art px).
var h: int
## Seeded per texture, so a piece paints identically every time.
var rng := RandomNumberGenerator.new()
## Direction the light comes FROM, in this canvas's frame (normalized).
var light: Vector2
## Coverage layer (R8): non-zero where something is drawn.
var _cov: Image
## Height layer (R8): height above the floor per pixel; drives cast_shadows().
var _hgt: Image
## Snapshot of _cov for fast reads; refreshed when stale.
var _cov_bytes := PackedByteArray()
## Whether _cov changed since the snapshot.
var _cov_stale := true
## 1 per pixel a `glowing` drawing changed; empty until one does.
var _emit := PackedByteArray()


func _init(width: int, height: int, seed_value: int, light_from: Vector2) -> void:
	w = maxi(width, 1)
	h = maxi(height, 1)
	img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	_cov = Image.create(w, h, false, Image.FORMAT_R8)
	_hgt = Image.create(w, h, false, Image.FORMAT_R8)
	rng.seed = seed_value
	light = light_from.normalized()


# --- Pixels ----------------------------------------------------------------------------


## True if (x, y) is on the image.
func has(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


## The pixel at (x, y), or CLEAR off the image.
func at(x: int, y: int) -> Color:
	return img.get_pixel(x, y) if has(x, y) else CLEAR


## The coverage as it stands: one byte per pixel, row by row (`y * w + x`), non-zero where something
## is drawn. A snapshot: drawing after the call does not change it. For a painter that reads the
## coverage of every pixel (`covered` per pixel is the slow way to do that).
func coverage() -> PackedByteArray:
	covered(0, 0)  # Refresh the snapshot.
	return _cov_bytes


## True if something is drawn at (x, y).
func covered(x: int, y: int) -> bool:
	if not has(x, y):
		return false
	if _cov_stale:
		_cov_bytes = _cov.get_data()
		_cov_stale = false
	return _cov_bytes[y * w + x] != 0


## Set the pixel at (x, y) (ignored off the image); a non-negative `height` also raises it.
func px(x: int, y: int, c: Color, height: int = -1) -> void:
	if not has(x, y):
		return
	img.set_pixel(x, y, c)
	_cov.set_pixel(x, y, _ON if c.a > 0.0 else CLEAR)
	_cov_stale = true
	if height >= 0:
		_hgt.set_pixel(x, y, _height_color(height))


## Run `draw` (a Callable taking no arguments, drawing on this canvas) as the drawing of something
## that gives light (a screen's face, a tube, a bulb, an LED): every pixel it changes within `area`
## (the whole canvas when empty) is marked emissive, so `emissive()` (and `PixelArt.emissive`) can
## hand it to a caller that draws it unshaded.
func glowing(draw: Callable, area := Rect2i()) -> void:
	var r := (Rect2i(0, 0, w, h)
			if area.size == Vector2i.ZERO
			else area.intersection(Rect2i(0, 0, w, h)))
	if r.size.x <= 0 or r.size.y <= 0:
		draw.call()
		return
	var before := img.get_region(r).get_data()
	draw.call()
	var after := img.get_region(r).get_data()
	if _emit.is_empty():
		_emit.resize(w * h)
	var row := r.size.x * 4
	for ry in r.size.y:
		var a := ry * row
		if before.slice(a, a + row) == after.slice(a, a + row):
			continue  # A row the drawing left as it was (most of them).
		var row_start := (r.position.y + ry) * w + r.position.x
		for rx in r.size.x:
			var k := a + rx * 4
			if before.decode_u32(k) != after.decode_u32(k):
				_emit[row_start + rx] = 1


## The emissive pixels (`glowing`) as they stand in the art now, transparent elsewhere, or null when
## nothing was drawn glowing.
func emissive() -> Image:
	if _emit.is_empty():
		return null
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(CLEAR)
	var any := false
	for i in w * h:
		if _emit[i] != 0:
			var x := i % w
			var y := int(i / float(w))
			out.set_pixel(x, y, img.get_pixel(x, y))
			any = true
	return out if any else null


## Fill a shape; a non-negative `height` also raises those pixels.
func fill(s: PixelShape, c: Color, height: int = -1) -> void:
	var sp := s.spans()
	var image := Rect2i(0, 0, w, h)
	var hc := _height_color(height)
	for i in range(0, sp.size(), 3):
		var r := Rect2i(sp[i + 1], sp[i], sp[i + 2] - sp[i + 1], 1).intersection(image)
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		img.fill_rect(r, c)
		_cov.fill_rect(r, _ON if c.a > 0.0 else CLEAR)
		if height >= 0:
			_hgt.fill_rect(r, hc)
	_cov_stale = true


## Recolor the already-drawn pixels of `r`.
func paint_over(r: Rect2i, c: Color) -> void:
	var rr := r.intersection(Rect2i(0, 0, w, h))
	if rr.size.x <= 0 or rr.size.y <= 0:
		return
	var solid := Image.create(rr.size.x, rr.size.y, false, Image.FORMAT_RGBA8)
	solid.fill(c)
	img.blit_rect_mask(solid, img.get_region(rr), Rect2i(Vector2i.ZERO, rr.size), rr.position)


## A 1px line from `a` to `b` (Bresenham).
func line(a: Vector2i, b: Vector2i, c: Color, height: int = -1) -> void:
	for p in PixelShape.line_points(a, b):
		px(p.x, p.y, c, height)


# --- Shading ---------------------------------------------------------------------------


## Shade the rings `from_k`..`to_k` in from a shape's edge: edges facing the light take `lit`,
## edges facing away take `unlit` (swap them for a recess). Side-on edges are left alone.
func bevel(s: PixelShape, from_k: int, to_k: int, lit: Color, unlit: Color) -> void:
	var pts := s.edge_pixels(to_k)
	for i in range(0, pts.size(), 2):
		var x := pts[i]
		var y := pts[i + 1]
		if not has(x, y):
			continue
		var k := s.depth(x, y)
		if k < from_k or k > to_k:
			continue
		var d := s.normal(x, y).dot(light)
		if d > 0.3:
			img.set_pixel(x, y, lit)
		elif d < -0.3:
			img.set_pixel(x, y, unlit)


## Like bevel(), but relative to what is already drawn: edges facing the light are lightened by
## `lift`, edges facing away darkened by `drop` — for shapes in several colors (a head of hair and
## skin) that should share one shading.
func bevel_relative(s: PixelShape, from_k: int, to_k: int, lift: float, drop: float) -> void:
	var pts := s.edge_pixels(to_k)
	for i in range(0, pts.size(), 2):
		var x := pts[i]
		var y := pts[i + 1]
		if not has(x, y):
			continue
		var k := s.depth(x, y)
		if k < from_k or k > to_k:
			continue
		var d := s.normal(x, y).dot(light)
		if d > 0.3:
			img.set_pixel(x, y, img.get_pixel(x, y).lightened(lift))
		elif d < -0.3:
			img.set_pixel(x, y, img.get_pixel(x, y).darkened(drop))


## A 1px ring just inside a shape's edge, each pixel darkened by `amount` from what is drawn.
func outline_relative(s: PixelShape, amount: float) -> void:
	var pts := s.edge_pixels(1)
	for i in range(0, pts.size(), 2):
		var x := pts[i]
		var y := pts[i + 1]
		if has(x, y) and s.depth(x, y) == 1:
			img.set_pixel(x, y, img.get_pixel(x, y).darkened(amount))


## A 1px ring just inside a shape's edge.
func outline(s: PixelShape, c: Color) -> void:
	var pts := s.edge_pixels(1)
	for i in range(0, pts.size(), 2):
		var x := pts[i]
		var y := pts[i + 1]
		if has(x, y) and s.depth(x, y) == 1:
			img.set_pixel(x, y, c)


## Darken each drawn pixel that a taller neighbour, toward the light, overshadows: a part `k` px
## toward the light that stands at least `k` higher shades it (up to cast_shadow_px away).
func cast_shadows() -> void:
	var step := Vector2i(roundi(light.x), roundi(light.y))
	var reach := maxi(0, ArtCanvasConfig.cast_shadow_px)
	if step == Vector2i.ZERO or reach == 0:
		return
	var hb := _hgt.get_data()
	covered(0, 0)  # Refresh the coverage snapshot.
	var shade := ArtCanvasConfig.cast_shadow_darken
	for y in h:
		for x in w:
			var i := y * w + x
			if _cov_bytes[i] == 0:
				continue
			var own := hb[i]
			for k in range(1, reach + 1):
				var qx := x + step.x * k
				var qy := y + step.y * k
				if qx < 0 or qy < 0 or qx >= w or qy >= h:
					break
				var j := qy * w + qx
				if _cov_bytes[j] != 0 and hb[j] >= own + k:
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(shade))
					break


## A soft glare: short diagonal streaks of `glint` near the lit corner of `s` (glaze, glass).
func glare(s: PixelShape, glint: Color, streaks: int = 2) -> void:
	var r := s.bounds
	var corner := Vector2(r.position) + Vector2(r.size) * (Vector2(0.5, 0.5) + light * 0.32)
	var along := Vector2(light.y, -light.x)  # Across the light: streaks run perpendicular to it.
	var length := mini(r.size.x, r.size.y) * 0.35
	for i in streaks:
		var off := -light * (i * 3.0)
		var a := Vector2i((corner + off - along * length * 0.5).round())
		var b := Vector2i((corner + off + along * length * (0.5 - i * 0.2)).round())
		_line_inside(s, a, b, glint)


## A line clipped to shape `s`.
func _line_inside(s: PixelShape, a: Vector2i, b: Vector2i, c: Color) -> void:
	for p in PixelShape.line_points(a, b):
		if s.has(p.x, p.y) and has(p.x, p.y):
			img.set_pixel(p.x, p.y, c)


# --- Surface finishes ------------------------------------------------------------------


## Texture a freshly filled shape (still in `base`) by its material: wood grain, brushed metal,
## stone flecks, glaze or glass glare, fabric weave or a faint plastic grain. `along_x` runs grain
## and brushing along x; `wraps` makes them wrap at the image edges (seamless tiles).
func surface(
	s: PixelShape,
	material: String,
	base: Color,
	along_x: bool = true,
	wraps: bool = false,
) -> void:
	match material:
		"wood":
			grain(
				s,
				ArtSurfaceConfig.wood_grain_density,
				base.darkened(0.12),
				base.lightened(0.07),
				{ "along_x": along_x, "wraps": wraps },
			)
		"metal":
			grain(
				s,
				ArtSurfaceConfig.metal_brush_density,
				base.lightened(0.07),
				base.darkened(0.05),
				{ "along_x": along_x, "wraps": wraps },
			)
		"stone":
			speckle(s.bounds, base, ArtSurfaceConfig.stone_fleck_density, 0.16)
			speckle(s.bounds, base, ArtSurfaceConfig.stone_fleck_density * 0.5, 0.3)
		"ceramic":
			speckle(s.bounds, base, 0.02, 0.03)
			glare(s, base.lightened(0.45), 2)
		"glass":
			glare(s, base.lightened(0.55), 3)
		"fabric":
			speckle(s.bounds, base, ArtSurfaceConfig.fabric_speckle)
		"plastic", "electronics":
			speckle(s.bounds, base, 0.04, 0.04)


## Nudge a sample of the pixels of exactly color `base` in `r` a shade lighter or darker.
func speckle(r: Rect2i, base: Color, density: float, amount: float = 0.07) -> void:
	var rr := r.intersection(Rect2i(0, 0, w, h))
	if rr.size.x <= 0 or rr.size.y <= 0:
		return
	for _i in roundi(rr.get_area() * density):
		var x := rr.position.x + rng.randi_range(0, rr.size.x - 1)
		var y := rr.position.y + rng.randi_range(0, rr.size.y - 1)
		if _same(img.get_pixel(x, y), base):
			img.set_pixel(
				x,
				y,
				base.lightened(amount) if rng.randf() < 0.5 else base.darkened(amount),
			)


## True if a stored (8-bit) pixel holds `col`, allowing for the rounding the image applied.
static func _same(stored: Color, col: Color) -> bool:
	const TOLERANCE := 1.5 / 255.0
	return absf(stored.r - col.r) < TOLERANCE and absf(stored.g - col.g) < TOLERANCE \
			and absf(stored.b - col.b) < TOLERANCE and absf(stored.a - col.a) < TOLERANCE


## Wood grain over the drawn pixels of shape `s`, `density` streaks per px of its bounds: long,
## gently wandering streaks, each a `dark` line with the odd `pale` fleck beside it. `opts`:
## `along_x` (bool, default true: the streaks run along x, else along y) and `wraps` (bool, default
## false: a streak continues past the far end back at the near end, so a tile repeats seamlessly).
func grain(s: PixelShape, density: float, dark: Color, pale: Color, opts: Dictionary = {}) -> void:
	var along_x: bool = opts.get("along_x", true)
	var wraps: bool = opts.get("wraps", false)
	var r := s.bounds
	var length := r.size.x if along_x else r.size.y
	var across := r.size.y if along_x else r.size.x
	if length < 2 or across < 1:
		return
	covered(0, 0)  # Refresh the coverage snapshot.
	var streaks := maxi(1, roundi(r.get_area() * density))
	for _s in streaks:
		var a := rng.randi_range(0, across - 1)
		var run := rng.randi_range(maxi(2, int(length * 4 / 10.0)), maxi(2, length))
		var start := (rng.randi_range(0, length - 1)
				if wraps
				else rng.randi_range(0, maxi(0, length - run)))
		_grain_streak(s, Vector3i(start, run, a), dark, pale, opts)


## One streak of `grain` over shape `s`: `walk` = (its start along, its run, where it starts
## across), wandering across as it goes; `opts` as `grain`'s.
func _grain_streak(
	s: PixelShape,
	walk: Vector3i,
	dark: Color,
	pale: Color,
	opts: Dictionary,
) -> void:
	var along_x: bool = opts.get("along_x", true)
	var wraps: bool = opts.get("wraps", false)
	var r := s.bounds
	var length := r.size.x if along_x else r.size.y
	var across := r.size.y if along_x else r.size.x
	var a := walk.z
	for i in walk.y:
		if rng.randf() < 0.05:
			a = clampi(a + (1 if rng.randf() < 0.5 else -1), 0, across - 1)
		var along := (walk.x + i) % length if wraps else walk.x + i
		var p := _grain_point(r, along_x, along, a)
		if s.has(p.x, p.y) and _drawn(p):
			img.set_pixel(p.x, p.y, dark)
		if a + 1 < across and rng.randf() < 0.08:
			var q := _grain_point(r, along_x, along, a + 1)
			if s.has(q.x, q.y) and _drawn(q):
				img.set_pixel(q.x, q.y, pale)


## Image point `along`/`across` a grain rect's axes.
static func _grain_point(r: Rect2i, along_x: bool, along: int, across: int) -> Vector2i:
	return r.position + (Vector2i(along, across) if along_x else Vector2i(across, along))


## Coverage at `p` from the current snapshot (callers refresh it first).
func _drawn(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and _cov_bytes[p.y * w + p.x] != 0


## A wood knot centred on (x, y): a dark heart in a ring of grain.
func knot(x: int, y: int, heart: Color, ring: Color) -> void:
	for p in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
			Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
		if covered(x + p.x, y + p.y):
			img.set_pixel(x + p.x, y + p.y, ring)
	for dx in [-1, 0, 1]:
		if covered(x + dx, y):
			img.set_pixel(x + dx, y, heart)


## The height layer's encoding of `height` (rounded up so the byte reads back exactly).
static func _height_color(height: int) -> Color:
	return Color((clampi(height, 0, 255) + 0.5) / 255.0, 0.0, 0.0)
