extends GameTest
## The character painters' flat read (#193 phase 2b, Character): painted for the 3D render
## (`PixelArt.render_flat`, a canvas with no light) the fist, the shoulders and the head
## draw no outline ring of their own (the pixel post outlines the figure, so a ring would be a
## second outline) and no hand-picked light tone; painted lit for the 2D they draw the ring as
## they always did. The look's colours are the same either way. The shoe's toe cap ring and polished
## toe, the boot shaft's rim highlight and the vest's panel and pouch rings are checked by their own
## tones: a lit render holds them, a flat one none.

const BodyPainter := preload("res://scenes/character/body/art/body_painter.gd")
const HeadPainter := preload("res://scenes/character/body/art/head_painter.gd")
const HandPainter := preload("res://scenes/character/body/art/hand_painter.gd")
const LimbPainter := preload("res://scenes/character/body/art/limb_painter.gd")
const VestFacePainter := preload("res://tests/character/vest_face_painter.gd")
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
	_check_tones(t)
	_check_unringed(t)
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


## The tones a lit render draws by hand and a flat one leaves out: the number of pixels of `tone`
## (a tone of the part's colour) in each.
func _check_tones(t: TestContext) -> void:
	var shoe := Color(0.45, 0.30, 0.18)
	var plain := { "look": PixelArt.handle({ "style": "plain" }) }
	var police := { "look": PixelArt.handle({ "style": "plain", "police": true }) }
	var carrier := Color(0.15, 0.62, 0.22)
	var vest := {
		"look": PixelArt.handle({
			"vest": "carrier", "vest_col": carrier, "front_cover": carrier, "back_cover": carrier,
			"shirt": SHIRT, "style": "plain",
		}),
	}
	var cases := [
		["the shoe's toe cap ring", LimbPainter, Vector2(9, 16), shoe, _foot(plain, "foot"),
			[ArtSurfaceConfig.tones(shoe).outline]],
		["the polished toe's highlight", LimbPainter, Vector2(9, 16), shoe, _foot(police, "foot"),
			[ArtSurfaceConfig.tones(shoe).highlight]],
		["the boot shaft's rim highlight", LimbPainter, Vector2(9, 12), shoe,
			_foot(plain, "shaft"), [ArtSurfaceConfig.tones(shoe).highlight]],
		["the vest's panel and pouch rings", BodyPainter, Vector2(28, 28), SHIRT, vest,
			[
				ArtSurfaceConfig.tones(carrier).outline,
				ArtSurfaceConfig.tones(carrier.darkened(0.18)).outline,
			]],
	]
	for spec: Array in cases:
		var painter: Script = spec[1]
		var lit := _count(
			PixelArt.render(painter, spec[2], spec[3], Vector2.DOWN, spec[4]),
			spec[5],
		)
		var flat := _count(PixelArt.render_flat(painter, spec[2], spec[3], spec[4]), spec[5])
		t.check(lit > 0, "%s is drawn lit (%d pixels)" % [spec[0], lit])
		t.expect_eq(flat, 0, "%s is not drawn flat" % spec[0])


## No painter's flat render takes a ring from the canvas's own outline rule (a flat canvas darkens
## the pixel an `outline()` call would ring, `ArtCanvasConfig.flat_outline_darken`, so a painter's
## own ring would be darkened over twice): the flat render is the same with the darkening off. The
## shoe, the vest's front panel and flank and the head; the fist's thumb, the shoulders' neck ring
## and the few small rings of one style's detail keep the rule's 12% (a shade, not a line).
func _check_unringed(t: TestContext) -> void:
	var shoe := Color(0.45, 0.30, 0.18)
	var carrier := Color(0.15, 0.62, 0.22)
	var vest := PixelArt.handle({
		"vest": "carrier", "vest_col": carrier, "front_cover": carrier, "back_cover": carrier,
		"shirt": SHIRT, "style": "plain",
	})
	var cases := {
		&"shoe": [LimbPainter, Vector2(9, 16), shoe, _foot({
			"look": PixelArt.handle({ "style": "plain" }),
		}, "foot")],
		&"police shoe": [LimbPainter, Vector2(9, 16), shoe, _foot({
			"look": PixelArt.handle({ "style": "plain", "police": true }),
		}, "foot")],
		&"vest front": [VestFacePainter, Vector2(20, 24), SHIRT, { "look": vest, "face": "front" }],
		&"vest flank": [VestFacePainter, Vector2(10, 24), SHIRT, { "look": vest, "face": "side" }],
		&"head": CASES[&"head"],
	}
	var darken := ArtCanvasConfig.flat_outline_darken
	var kept := PixelArt._cache.duplicate()  # what the other tests painted, put back after
	for name: StringName in cases:
		var spec: Array = cases[name]
		ArtCanvasConfig.flat_outline_darken = darken
		PixelArt._cache.clear()  # the cache holds the render made with the other setting
		var with := PixelArt.render_flat(spec[0], spec[1], spec[2], spec[3]).get_image()
		ArtCanvasConfig.flat_outline_darken = 0.0
		PixelArt._cache.clear()
		var without := PixelArt.render_flat(spec[0], spec[1], spec[2], spec[3]).get_image()
		ArtCanvasConfig.flat_outline_darken = darken
		t.check(
			with.get_data() == without.get_data(),
			"the flat %s is the same with the canvas's flat outline off: it draws no ring" % name,
		)
	PixelArt._cache = kept


## `opts` of a shoe or boot part.
func _foot(opts: Dictionary, part: String) -> Dictionary:
	var made := opts.duplicate()
	made["part"] = part
	return made


## How many pixels of `texture` are one of `colours` (to within two of the 8 bits).
func _count(texture: Texture2D, colours: Array) -> int:
	var image := texture.get_image()
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			for colour: Color in colours:
				var off := Vector3(pixel.r - colour.r, pixel.g - colour.g, pixel.b - colour.b)
				if off.length() < 0.012:
					count += 1
					break
	return count


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
