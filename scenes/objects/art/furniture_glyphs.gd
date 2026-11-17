class_name FurnitureGlyphs
extends RefCounted
## Objects domain, the lit marks of a lettered 3D piece (`domain-art/meshes.md`): the
## pixel font and the brush-stroke characters the painters draw (`glyphs.gd`) as the points a mesh
## puts a small block at, so a menu board's text and a glyph sign's characters are the 2D art's own
## shapes. Points are in the painter's pixels from the glyph's top-left corner.

const Glyphs = preload("res://scenes/objects/art/glyphs.gd")


## The lit pixels of `text` in the pixel font, one point per pixel, the way `Glyphs.draw` lays them.
static func pixels(text: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in text.length():
		var rows: Array = Glyphs.FONT.get(text[i], [])
		for gy in rows.size():
			for gx in Glyphs.COLS:
				if rows[gy][gx] == "#":
					out.append(Vector2(i * Glyphs.ADVANCE + gx, gy))
	return out


## The points along the brush strokes of the character `ch`, drawn in a box of `size` px (the
## painter's ten-unit grid scaled to it), `spacing` px apart.
static func strokes(ch: String, size: float, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var step := size / 10.0
	for stroke: Array in Glyphs.HANZI.get(ch, []):
		for k in stroke.size() - 1:
			var from := _point(stroke[k]) * step
			var to := _point(stroke[k + 1]) * step
			var count := maxi(1, int(from.distance_to(to) / maxf(0.1, spacing)))
			for s in count + 1:
				out.append(from.lerp(to, float(s) / float(count)))
	return out


## The 2D point a `[x, y]` pair of a stroke names.
static func _point(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))
