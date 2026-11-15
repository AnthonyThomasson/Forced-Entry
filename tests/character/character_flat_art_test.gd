extends GameTest
## The character painters' flat read (#193 phase 2b, Character): painted for the 3D render
## (`PixelArt.render_flat`, a canvas with no light) the fist, the shoulders and the head
## draw no outline ring of their own (the pixel post outlines the figure, so a ring would be a
## second outline) and no hand-picked light tone; painted lit for the 2D they draw the ring as
## they always did. The look's colours are the same either way.

const BodyPainter := preload("res://scenes/character/body/art/body_painter.gd")
const HeadPainter := preload("res://scenes/character/body/art/head_painter.gd")
const HandPainter := preload("res://scenes/character/body/art/hand_painter.gd")
const SKIN := Color(0.80, 0.62, 0.48)
const SHIRT := Color(0.30, 0.38, 0.52)
## The painter, its canvas, its colour and its options.
const CASES := {
	&"hand": [HandPainter, Vector2(10, 10), Color(0.55, 0.45, 0.38), {}],
	&"shoulders": [BodyPainter, Vector2(28, 28), SHIRT, {}],
	&"head": [HeadPainter, Vector2(30, 30), SKIN, {}],
}


func describe() -> Dictionary:
	return {
		"name": "The character painters' flat read drops the outline rings",
		"description": "A flat render of the fist, shoulders and head has a lighter rim than "
			+ "the lit render of each (no outline ring).",
		"tags": ["art", "character", "scripted", "3d"],
		"timeout": 20.0,
	}


func run(t: TestContext) -> void:
	for name: StringName in CASES:
		var spec: Array = CASES[name]
		var painter: Script = spec[0]
		var size: Vector2 = spec[1]
		var color: Color = spec[2]
		var opts: Dictionary = spec[3]
		var lit := _rim(PixelArt.render(painter, size, color, Vector2.DOWN, opts))
		var flat := _rim(PixelArt.render_flat(painter, size, color, opts))
		t.check(
			flat > lit + 0.02,
			"the flat %s's rim is lighter than the lit one's, which has its ring (%.3f over %.3f)"
				% [name, flat, lit],
		)
		t.check(
			PixelArt.render_flat(painter, size, color, opts)
				== PixelArt.render_flat(painter, size, color, opts),
			"the flat %s is one cached texture" % name,
		)


## The mean luminance of the pixels of `texture` on its silhouette's edge (a drawn pixel beside a
## clear one or the border): an outline ring darkens it.
func _rim(texture: Texture2D) -> float:
	var image := texture.get_image()
	var total := 0.0
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a < 0.5 or not _on_edge(image, x, y):
				continue
			total += image.get_pixel(x, y).get_luminance()
			count += 1
	return total / maxf(count, 1.0)


## Whether the pixel (`x`, `y`) of `image` has a clear neighbour or lies on the border.
func _on_edge(image: Image, x: int, y: int) -> bool:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var at: Vector2i = Vector2i(x, y) + step
		if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(at):
			return true
		if image.get_pixel(at.x, at.y).a < 0.5:
			return true
	return false
