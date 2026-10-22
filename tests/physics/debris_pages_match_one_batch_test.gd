extends GameTest
## A debris chunk draws its resting chips in pages (`DebrisLayer.PAGE` chips each, oldest first, a
## canvas item each) instead of one batch, so landing and dropping chips repaint one page. The pages
## are drawn in age order with the same triangles, so they must paint exactly the one batch's
## pixels, under a light too. Run with a window (`tools/run_tests.sh --windowed
## --id=physics/debris_pages_match_one_batch`) it lays overlapping, half transparent chips of every
## shape across two chunks, renders them magnified drawn in one batch, in pages and in one batch
## again, drops the oldest past a lowered cap and renders again, and checks every pixel is the same
## each way. Headless it checks the pages hold the chunk's chips.

## Chips laid, and the cap that then drops the oldest of them.
const LAID := 150
const KEPT := 90
## The world rect the comparison view frames (both chunks' chips), and how much it magnifies it.
const FRAME := Rect2(70, 40, 130, 90)
const ZOOM := 4.0


func describe() -> Dictionary:
	return {
		"name": "Debris pages paint what one batch painted",
		"description": "Resting chips drawn in pages, oldest first, render the same pixels as the "
			+ "chunk's one batch, lit and after the cap drops the oldest.",
		"tags": ["debris", "draw", "physics"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.set_static(DebrisLayer, &"paged", true)
	s.lock_interaction([&"camera", &"pause", &"overlays"])


func run(t: TestContext) -> void:
	var cap_before: int = Despawner.max_scene_objects
	var layer := DebrisLayer.layer(t.world)
	t.world.add_child(_steady_light(Vector2(135, 110)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 78
	for i in LAID:
		_rest_one(layer, rng, i)
	await _repaint(t, layer)
	t.check(layer.marks_in(Vector2i(0, 0)).size() > 0 and layer.marks_in(Vector2i(1, 0)).size() > 0,
		"the chips lie across two chunks")
	t.check(_paged(layer) == _held(layer), "the pages hold every chunk's chips in order")

	if DisplayServer.get_name() == "headless":
		Despawner.max_scene_objects = cap_before
		return
	var view := SubViewport.new()
	view.size = Vector2i(FRAME.size * ZOOM)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(view)
	view.world_2d = t.world.get_viewport().world_2d  # The world's canvas, none of the overlays.
	view.canvas_transform = Transform2D(0.0, Vector2(ZOOM, ZOOM), 0.0, -FRAME.position * ZOOM)

	var before := await _three_ways(t, layer, view)
	Despawner.max_scene_objects = KEPT
	for i in 10:
		_rest_one(layer, rng, LAID + i)  # landing past the cap drops the oldest
	t.check(layer.count() == KEPT, "the cap dropped the oldest (%d held)" % layer.count())
	await _repaint(t, layer)
	t.check(_paged(layer) == _held(layer), "after the drop the pages still hold the chips in order")
	var after := await _three_ways(t, layer, view)
	Despawner.max_scene_objects = cap_before
	DebrisLayer.paged = true

	for images in [before, after]:
		var painted := 0
		for y in images[0].get_height():
			for x in images[0].get_width():
				painted += 1 if images[0].get_pixel(x, y).a > 0.0 else 0
		t.check(painted > 5_000, "the chips were rendered (%d pixels painted)" % painted)
		t.check(
			_differing(images[0], images[2]) == 0,
			"one batch drawn twice paints the same pixels (the chips hold still)",
		)
		t.expect_eq(_differing(images[0], images[1]), 0, "one batch, then pages: pixels differing")
		t.expect_eq(_differing(images[1], images[2]), 0, "pages, then one batch: pixels differing")


## Lay chip `i` within `FRAME`, its shape, turn, size and half transparent colour drawn from `rng`.
static func _rest_one(layer: DebrisLayer, rng: RandomNumberGenerator, i: int) -> void:
	var shapes := ["rect", "tri", "circle"]
	layer.rest(
		Vector2(rng.randf_range(FRAME.position.x + 6.0, FRAME.end.x - 6.0),
			rng.randf_range(FRAME.position.y + 6.0, FRAME.end.y - 6.0)),
		rng.randf() * TAU,
		Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.4, 1.0)),
		Vector2(rng.randf_range(2.0, 7.0), rng.randf_range(2.0, 7.0)),
		shapes[i % 3],
	)


## A plain point light over the chips, steady (no rhythm), its pool fading out from the middle.
static func _steady_light(at: Vector2) -> PointLight2D:
	var pool := GradientTexture2D.new()
	pool.fill = GradientTexture2D.FILL_RADIAL
	pool.fill_from = Vector2(0.5, 0.5)
	pool.fill_to = Vector2(1.0, 0.5)
	pool.width = 128
	pool.height = 128
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	pool.gradient = ramp
	var light := PointLight2D.new()
	light.texture = pool
	light.texture_scale = 1.5
	light.color = Color(1.0, 0.7, 0.4)
	light.energy = 1.2
	light.position = at  # the world node sits at the origin
	return light


## Render the chips in one batch, in pages, and in one batch again: the three images.
func _three_ways(t: TestContext, layer: DebrisLayer, view: SubViewport) -> Array[Image]:
	var images: Array[Image] = []
	for paged in [false, true, false]:
		DebrisLayer.paged = paged
		await _repaint(t, layer)
		await RenderingServer.frame_post_draw
		images.append(view.get_texture().get_image())
	return images


## Repaint every chunk and page of `layer`, and let the repaint reach the renderer.
func _repaint(t: TestContext, layer: DebrisLayer) -> void:
	for chunk in layer.get_children():
		chunk.queue_redraw()
		for page in chunk.get_children():
			page.queue_redraw()
	await t.frames(3)


## Every chunk's chips as its pages hold them, chunk by chunk.
static func _paged(layer: DebrisLayer) -> Array:
	var out: Array = []
	for cell in layer._chunks:
		for page in (layer._chunks[cell] as Node).get_children():
			if not page.is_queued_for_deletion():
				out.append_array(page.chips)
	return out


## Every chunk's chips as the layer files them, chunk by chunk.
static func _held(layer: DebrisLayer) -> Array:
	var out: Array = []
	for cell in layer._chunks:
		out.append_array(layer.marks_in(cell))
	return out


## How many pixels of `a` and `b` differ.
static func _differing(a: Image, b: Image) -> int:
	if a.get_data() == b.get_data():
		return 0
	var out := 0
	for y in a.get_height():
		for x in a.get_width():
			out += 0 if a.get_pixel(x, y) == b.get_pixel(x, y) else 1
	return out
