extends GameTest
## General's `FillBatch` draws plain-coloured polygons and discs as one triangle array where
## `draw_colored_polygon` and `draw_circle` drew one command each (the body's limbs and shadow,
## blood splats, resting chips, blood prints, wound marks). Headless (the suite) this checks what it
## hands the renderer: the triangles `Geometry2D.triangulate_polygon` cuts each polygon into, every
## disc as `draw_circle`'s 64-gon and every convex polygon given as such fanned from its first
## corner, each in its colour, in the order added (batching forced on, as it is with a window), and
## that under the headless display a batch hands each shape to its canvas as it comes and holds
## nothing. Run with a window (`tools/run_tests.sh --windowed
## --id=general/fill_batch_matches_draw_calls`) it also renders the same overlapping, half
## transparent shapes both ways, magnified, and checks every pixel is the same.

const SHAPES := 40


func describe() -> Dictionary:
	return {
		"name": "A fill batch draws what the draw calls drew",
		"description": "FillBatch holds each polygon's own triangles and draw_circle's 64-gon, in "
			+ "order; windowed, it renders the same pixels as the plain draw calls.",
		"tags": ["draw", "general"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.set_static(FillBatch, &"batching", true)


func run(t: TestContext) -> void:
	var shapes := _shapes()
	_check_batch(t, shapes)
	await _check_direct(t, shapes)
	if DisplayServer.get_name() == "headless":
		return
	await _check_pixels(t, shapes)


## `SHAPES` seeded shapes, `[kind, data, color]`: every third a disc (`circle`, data `[centre,
## radius]`), else every fifth a convex polygon (`convex`), the rest a star-ish ring (`poly`).
func _shapes() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var shapes: Array = []
	for i in SHAPES:
		var color := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.3, 1.0))
		var at := Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))
		if i % 3 == 0:
			shapes.append(["circle", [at, rng.randf_range(0.4, 2.5)], color])
		elif i % 5 == 0:
			shapes.append(["convex", _convex_ring(rng, at), color])
		else:
			shapes.append(["poly", _star(rng, at), color])
	return shapes


## A convex polygon round `at`, added uncut (`fill_convex`), drawn from `rng`.
func _convex_ring(rng: RandomNumberGenerator, at: Vector2) -> PackedVector2Array:
	var ring := PackedVector2Array()
	var corners := rng.randi_range(3, 14)
	var r := rng.randf_range(0.8, 2.6)
	for k in corners:
		ring.append(at
				+ Vector2.from_angle(TAU * k / corners) * r
					* Vector2(1.0, rng.randf_range(0.6, 1.0) if k == 0 else 1.0))
	return ring


## A star-ish, often concave ring round `at`, drawn from `rng`.
func _star(rng: RandomNumberGenerator, at: Vector2) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var count := rng.randi_range(3, 14)
	for k in count:
		poly.append(at + Vector2.from_angle(TAU * k / count) * rng.randf_range(0.6, 2.8))
	return poly


## What the batch hands the renderer: every shape's corners, each polygon's own triangles in order,
## each in its shape's colour.
func _check_batch(t: TestContext, shapes: Array) -> void:
	var batch := FillBatch.new(t.world)
	var want_points := PackedVector2Array()
	var want_indices := PackedInt32Array()
	var want_colors := PackedColorArray()
	for shape in shapes:
		var poly := _add_shape(batch, shape)
		if poly.is_empty():
			continue  # left to the engine: not a batch's
		want_indices.append_array(_triangles(shape[0], poly, want_points.size()))
		want_points.append_array(poly)
		for k in poly.size():
			want_colors.append(shape[2])
	var worst := 0.0
	for i in mini(want_points.size(), batch._points.size()):
		worst = maxf(worst, want_points[i].distance_to(batch._points[i]))
	t.check(
		batch._points.size() == want_points.size() and worst < 0.0001,
		"the batch holds every shape's corners (%d of %d, %.6f px off)"
			% [batch._points.size(), want_points.size(), worst],
	)
	t.check(
		batch._indices == want_indices,
		"and each polygon's own triangles, in order (%d indices of %d)"
			% [batch._indices.size(), want_indices.size()],
	)
	t.check(batch._colors == want_colors, "in each shape's colour")


## Adds `shape` to `batch`; returns the corners it stands for (a disc's 64-gon), empty for a polygon
## that cannot be triangulated (left to the engine).
func _add_shape(batch: FillBatch, shape: Array) -> PackedVector2Array:
	var poly: PackedVector2Array
	if shape[0] == "convex":
		poly = shape[1]
		batch.fill_convex(poly, shape[2])
	elif shape[0] == "poly":
		poly = shape[1]
		if Geometry2D.triangulate_polygon(poly).is_empty():
			return PackedVector2Array()
		batch.fill(poly, shape[2])
	else:
		var centre: Vector2 = shape[1][0]
		var radius: float = shape[1][1]
		batch.circle(centre, radius, shape[2])
		poly = PackedVector2Array()
		for k in 64:
			poly.append(centre + Vector2(cos(TAU * k / 64.0), sin(TAU * k / 64.0)) * radius)
	return poly


## The triangles of a shape of `kind` with corners `poly`, its first corner at index `base`.
func _triangles(kind: String, poly: PackedVector2Array, base: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if kind == "poly":
		for index in Geometry2D.triangulate_polygon(poly):
			out.append(base + index)
	else:
		# a convex polygon or the 64-gon: the fan from its first corner
		for k in range(1, poly.size() - 1):
			out.append_array([base, base + k, base + k + 1])
	return out


## Unbatched (the headless display's way), a batch holds nothing: each shape is drawn as it comes.
func _check_direct(t: TestContext, shapes: Array) -> void:
	var direct := Direct.new()
	direct.shapes = shapes
	t.world.add_child(direct)
	await t.until(func() -> bool: return direct.drawn, 1.0)
	t.check(
		direct.drawn and direct.held == 0,
		"unbatched, a batch holds nothing: each shape was drawn as it came (%d held)" % direct.held,
	)


## Windowed: the shapes rendered with the plain draw calls and batched give the same pixels.
func _check_pixels(t: TestContext, shapes: Array) -> void:
	var images := []
	for batched in [false, true]:
		images.append(await _render(t, shapes, batched))
	var differing := 0
	var painted := 0
	var a: Image = images[0]
	var b: Image = images[1]
	for y in a.get_height():
		for x in a.get_width():
			painted += 1 if a.get_pixel(x, y).a > 0.0 else 0
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				differing += 1
	t.check(painted > 10_000, "the shapes were rendered (%d pixels painted)" % painted)
	t.check(
		differing == 0,
		"rendered, %d of %d pixels differ from the plain draw calls"
			% [differing, a.get_width() * a.get_height()],
	)


## The image of `shapes` rendered magnified in a viewport of their own, `batched` or not.
func _render(t: TestContext, shapes: Array, batched: bool) -> Image:
	var view := SubViewport.new()
	view.size = Vector2i(600, 600)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(view)
	view.canvas_transform = Transform2D(0.0, Vector2(60.0, 60.0), 0.0, Vector2(300.0, 300.0))
	var node := Shapes.new()
	node.shapes = shapes
	node.batched = batched
	view.add_child(node)
	await t.frames(3)
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


class Shapes:
	extends Node2D

	var shapes: Array = []  # [kind ("poly" | "circle"), data, color]
	var batched := false

	func _draw() -> void:
		var batch := FillBatch.new(self)
		for shape in shapes:
			if shape[0] == "poly" or shape[0] == "convex":
				if not batched:
					draw_colored_polygon(shape[1], shape[2])
				elif shape[0] == "poly":
					batch.fill(shape[1], shape[2])
				else:
					batch.fill_convex(shape[1], shape[2])
			elif batched:
				batch.circle(shape[1][0], shape[1][1], shape[2])
			else:
				draw_circle(shape[1][0], shape[1][1], shape[2])
		batch.flush()


## Draws the shapes through a batch with batching off (the headless display's way), noting what the
## batch held.
class Direct:
	extends Node2D

	var shapes: Array = []
	var drawn := false
	var held := 0

	func _draw() -> void:
		FillBatch.batching = false  # restored after the test
		var batch := FillBatch.new(self)
		for shape in shapes:
			if shape[0] == "circle":
				batch.circle(
					shape[1][0],
					shape[1][1],
					shape[2],
					Transform2D(0.3, Vector2(2.0, 5.0)),
				)
				batch.circle(shape[1][0], shape[1][1], shape[2])
			else:
				batch.fill(shape[1], shape[2])
				batch.fill_convex(shape[1], shape[2])
			held += batch._points.size()
		batch.flush()
		FillBatch.batching = true
		drawn = true
