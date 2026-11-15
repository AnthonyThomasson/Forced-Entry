extends GameTest
## A flat (unlit, 3D albedo) canvas outlines a shape by darkening the pixel already there a step,
## not by drawing the painter's dark ring (the 3D post draws the outline; a dark ring doubles it
## and a side face reads black from the edge texel); a lit canvas still draws its ring in `c`. The
## painters that picked a light tone by hand (a sofa's ridge, a counter's splash edge, an
## appliance's lid) take the base tone on a flat one.

const Sofa := preload("res://scenes/objects/art/sofa_painter.gd")
const Counter := preload("res://scenes/objects/art/counter_painter.gd")
const INK := Color(0.02, 0.02, 0.02)
const BASE := Color(0.5, 0.4, 0.3)


func describe() -> Dictionary:
	return {
		"name": "A flat canvas outlines by darkening, not by a dark ring",
		"description": "outline on a zero-light canvas darkens the drawn edge pixel by "
			+ "ArtCanvasConfig.flat_outline_darken; a lit one writes the ring colour; a "
			+ "flat sofa and counter drop the hand-picked light tones.",
		"tags": ["art", "scripted"],
		"timeout": 20.0,
	}


func run(t: TestContext) -> void:
	var shape := PixelShape.rounded(Rect2i(1, 1, 10, 8), 0)
	var flat := PixelCanvas.new(12, 10, 1, Vector2.ZERO)
	flat.fill(shape, BASE, 1)
	flat.outline(shape, INK)
	t.check(
		_near(flat.at(1, 4), BASE.darkened(ArtCanvasConfig.flat_outline_darken)),
		"a flat ring is the pixel darkened a step (is %s)" % flat.at(1, 4),
	)
	t.check(_near(flat.at(5, 4), BASE), "the inside is as painted")
	var lit := PixelCanvas.new(12, 10, 1, Vector2(-1, -1))
	lit.fill(shape, BASE, 1)
	lit.outline(shape, INK)
	t.check(_near(lit.at(1, 4), INK), "a lit ring is the painter's colour")
	_hand_picked_tones(t)


## A flat sofa has no ridge pixel in the light tone, a flat counter no splash edge in it.
func _hand_picked_tones(t: TestContext) -> void:
	var tones := ArtSurfaceConfig.tones(BASE)
	for painter: Script in [Sofa, Counter]:
		var flat := PixelCanvas.new(64, 40, 3, Vector2.ZERO)
		painter.paint(flat, BASE, "", {})
		var lit := PixelCanvas.new(64, 40, 3, Vector2(-1, -1))
		painter.paint(lit, BASE, "", {})
		var path := painter.resource_path.get_file()
		t.check(
			_count(lit, tones.light) > _count(flat, tones.light),
			"%s: the light tone is drawn lit and less of it flat" % path,
		)


func _count(canvas: PixelCanvas, color: Color) -> int:
	var n := 0
	for y in canvas.h:
		for x in canvas.w:
			if _near(canvas.at(x, y), color):
				n += 1
	return n


## `a` is `b` to within the 8-bit image's rounding.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
