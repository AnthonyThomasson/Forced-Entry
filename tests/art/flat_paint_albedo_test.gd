extends GameTest
## `PixelArt.render_flat` is a painter's albedo for the 3D render (#193): no bevel, cast shadow or
## glare (the canvas has no light), canonical (one texture whatever angle the piece takes, no
## lighting step), under the `|flat` key so no 2D key or pixel changes, and warmable by a request
## with `"flat": true`. The painters that read the light directly (cabinet, plant, sofa) paint on.

const Probe := preload("res://tests/art/flat_probe_painter.gd")
const Cabinet := preload("res://scenes/objects/art/cabinet_painter.gd")
const Plant := preload("res://scenes/objects/art/plant_painter.gd")
const Sofa := preload("res://scenes/objects/art/sofa_painter.gd")
const Table := preload("res://scenes/objects/art/table_painter.gd")
const SIZE := Vector2(32, 24)
const COLOR := Color(0.5, 0.4, 0.3)
## Pixel hashes of fresh 2D paints of the Table above, taken before `render_flat` existed.
const GOLDEN_RENDER := { Vector2.DOWN: 488_484_433, Vector2.RIGHT: 1_056_853_277 }
const GOLDEN_TURNED := 959_718_415


func describe() -> Dictionary:
	return {
		"name": "A flat render is a painter's albedo",
		"description": "render_flat paints with no light: no bevel, cast shadow or glare, one "
			+ "texture whatever the angle, the |flat key, the 2D art untouched, warmable.",
		"tags": ["art", "cache", "scripted"],
		"timeout": 20.0,
	}


func run(t: TestContext) -> void:
	_two_d_untouched(t)
	_no_light_shading(t)
	_one_texture_for_every_angle(t)
	_key_and_emissive(t)
	_light_reading_painters(t)
	_warm(t)


## Rendering flat leaves the 2D art as it was: the keys keep their exact form, and a fresh
## (uncached) paint of the non-flat path has the pixels it had before `render_flat` existed.
func _two_d_untouched(t: TestContext) -> void:
	var opts := { "material": "wood" }
	var base := PixelArt._key(Table, SIZE, COLOR, opts)
	PixelArt.render_flat(Table, SIZE, COLOR, opts)
	for facing in [Vector2.DOWN, Vector2.RIGHT]:
		var key := base + "|f%d" % PixelArt._turns(facing)
		PixelArt._cache.erase(key)
		var fresh := PixelArt.render(Table, SIZE, COLOR, facing, opts)
		t.check(PixelArt._cache.get(key) == fresh, "render files %s under %s" % [facing, key])
		t.check(
			hash(fresh.get_image().get_data()) == GOLDEN_RENDER[facing],
			"a fresh 2D render facing %s has its old pixels (%d)" % [
				facing,
				hash(fresh.get_image().get_data()),
			],
		)
	var turned_key := base + "|a%.4f" % 1.5
	PixelArt._cache.erase(turned_key)
	PixelArt._turned_memo.clear()
	var turned := PixelArt.render_turned(Table, SIZE, COLOR, 1.5, opts)
	t.check(PixelArt._cache.get(turned_key) == turned, "render_turned files %s" % turned_key)
	t.check(
		hash(turned.get_image().get_data()) == GOLDEN_TURNED,
		"a fresh render_turned has its old pixels (%d)" % hash(turned.get_image().get_data()),
	)
	t.check(
		PixelArt._flat_key(base) == base + "|flat" and base + "|flat" != base + "|f0",
		"the flat key is the lit base key plus |flat, distinct from any 2D key",
	)


## The probe's bevels, cast shadow and glare leave no trace on a flat canvas: every pixel of the
## big block is its own colour (no finish: material "").
func _no_light_shading(t: TestContext) -> void:
	var flat := PixelArt.render_flat(Probe, SIZE, COLOR).get_image()
	var lit := PixelArt.render(Probe, SIZE, COLOR, Vector2.DOWN).get_image()
	var odd := 0
	var lit_odd := 0
	for y in flat.get_height():
		for x in flat.get_width():
			var f := flat.get_pixel(x, y)
			if f.a > 0.0 and not PixelCanvas._same(f, COLOR) and (x != 4 or y != 4):
				odd += 1
			var l := lit.get_pixel(x, y)
			if l.a > 0.0 and not PixelCanvas._same(l, COLOR) and (x != 4 or y != 4):
				lit_odd += 1
	t.check(lit_odd > 0, "the lit paint shades the block (bevel, cast shadow): %d" % lit_odd)
	t.check(odd == 0, "the flat paint has no bevel or cast shadow: %d shaded pixels" % odd)
	var glazed := PixelArt.render_flat(Probe, SIZE, COLOR, { "material": "ceramic" }).get_image()
	var glints := 0
	for y in glazed.get_height():
		for x in glazed.get_width():
			if glazed.get_pixel(x, y).v > COLOR.v + 0.3 and (x != 4 or y != 4):
				glints += 1
	t.check(glints == 0, "a glaze's glare is skipped on a flat canvas: %d" % glints)
	t.check(
		PixelCanvas._same(flat.get_pixel(4, 4), Color(1.0, 0.9, 0.2)),
		"a plain drawn pixel stays",
	)


## One texture per piece and look, whatever the light or the angle: the light direction is not an
## input, and the pixels are those of a paint on a zero-light canvas.
func _one_texture_for_every_angle(t: TestContext) -> void:
	var opts := { "material": "wood" }
	var first := PixelArt.render_flat(Table, SIZE, COLOR, opts)
	var first_data := first.get_image().get_data()
	var light := ArtCanvasConfig.light_from
	var steps := ArtCanvasConfig.turn_steps
	for i in steps:
		ArtCanvasConfig.light_from = light.rotated(TAU * i / steps)
		var again := PixelArt.render_flat(Table, SIZE, COLOR, opts)
		t.check(again == first, "step %d of the light gets the same texture" % i)
	ArtCanvasConfig.light_from = light
	PixelArt._cache.erase(PixelArt._flat_key(PixelArt._key(Table, SIZE, COLOR, opts)))
	ArtCanvasConfig.light_from = light.rotated(1.0)
	var repainted := PixelArt.render_flat(Table, SIZE, COLOR, opts)
	ArtCanvasConfig.light_from = light
	t.check(
		repainted.get_image().get_data() == first_data,
		"a repaint under another world light has the same pixels",
	)
	var lit := PixelArt.render(Table, SIZE, COLOR, Vector2.DOWN, opts)
	t.check(lit.get_image().get_data() != first_data, "the lit art differs from the albedo")


## The key is the lit key plus `|flat`; the emissive twin is the glowing pixels, null when none.
func _key_and_emissive(t: TestContext) -> void:
	var opts := { "material": "metal" }
	var flat := PixelArt.render_flat(Probe, SIZE, COLOR, opts)
	var key := PixelArt._key(Probe, SIZE, COLOR, opts) + "|flat"
	t.check(PixelArt._cache.get(key) == flat, "the texture is cached under the |flat key")
	var glow := PixelArt.emissive_flat(Probe, SIZE, COLOR, opts)
	t.check(glow != null, "a glowing painter has an emissive twin")
	if glow != null:
		var g := glow.get_image()
		t.check(g.get_pixel(4, 4).a > 0.0, "the twin holds the glowing pixel")
		t.check(g.get_pixel(10, 10).a == 0.0, "and is clear elsewhere")
	t.check(
		PixelArt.emissive_flat(Table, SIZE, COLOR, { "material": "wood" }) == null,
		"a painter that glows nothing has no twin",
	)


## Painters that read `c.light` directly paint a fixed neutral side: the same pixels whatever the
## world light, and not the lit paint's.
func _light_reading_painters(t: TestContext) -> void:
	var light := ArtCanvasConfig.light_from
	for painter: Script in [Cabinet, Plant, Sofa]:
		var name := painter.resource_path.get_file()
		var size := Vector2(40, 28)
		var key := PixelArt._flat_key(PixelArt._key(painter, size, COLOR, {}))
		var image := PixelArt.render_flat(painter, size, COLOR).get_image()
		var drawn := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.0:
					drawn += 1
		t.check(drawn > 0, "%s draws something" % name)
		for turn in [1.0, 2.5, 4.0]:
			PixelArt._cache.erase(key)
			ArtCanvasConfig.light_from = light.rotated(turn)
			var again := PixelArt.render_flat(painter, size, COLOR).get_image()
			ArtCanvasConfig.light_from = light
			t.check(
				again.get_data() == image.get_data(),
				"%s flat pixels ignore a world light turned by %s" % [name, turn],
			)
		var lit := PixelArt.render(painter, size, COLOR, Vector2.DOWN).get_image()
		t.check(lit.get_data() != image.get_data(), "%s flat is not the lit paint" % name)


## A flat warm request is filed under the |flat key with the synchronous paint's pixels.
func _warm(t: TestContext) -> void:
	var opts := { "material": "stone" }
	var painters: Array[Script] = [Probe, Table]
	var requests: Array = []
	var references: Array[PackedByteArray] = []
	var keys: Array[String] = []
	for painter in painters:
		var texture := PixelArt.render_flat(painter, SIZE, COLOR, opts)
		references.append(texture.get_image().get_data())
		var key := PixelArt._flat_key(PixelArt._key(painter, SIZE, COLOR, opts))
		keys.append(key)
		PixelArt._cache.erase(key)
		PixelArt._emissive.erase(key)
		requests.append({
			"painter": painter, "size": SIZE, "color": COLOR, "opts": opts, "flat": true,
		})
	PixelArt.warm(requests)
	PixelArt.finish_warming()
	for i in requests.size():
		t.check(PixelArt._cache.has(keys[i]), "flat request %d is cached by the warm" % i)
		var again := PixelArt.render_flat(painters[i], SIZE, COLOR, opts)
		t.check(
			again.get_image().get_data() == references[i],
			"flat request %d has the synchronous paint's pixels" % i,
		)
	t.check(
		PixelArt.emissive_flat(Probe, SIZE, COLOR, opts) != null,
		"a warmed flat request keeps its emissive twin",
	)
