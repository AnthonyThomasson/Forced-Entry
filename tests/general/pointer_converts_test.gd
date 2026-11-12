extends GameTest
## Pointer: a screen point and a world point convert both ways through the viewport's view, and
## the visible rect is the world the viewport shows. Under a camera at a known position and zoom
## the expected points are worked out by hand from what a Camera2D is (its position sits at the
## screen's centre and one world pixel is `zoom` screen pixels), never by asking Pointer. A node in
## another viewport converts by that viewport's own view; with no camera, by the identity.

## The camera's position, and the two zooms it is read at.
const CAMERA_AT := Vector2(300.0, 200.0)
const ZOOM_IN := 2.0
const ZOOM_OUT := 0.5
## A world point 10 px right and 20 px up of the camera's position.
const BESIDE := Vector2(10.0, -20.0)
## The size of the standalone viewport (no camera).
const SIDE_SIZE := Vector2i(400, 300)
const TOLERANCE := 0.01


func describe() -> Dictionary:
	return {
		"name": "Pointer converts screen and world points",
		"description": "Under a camera at a known position and zoom, world_of / screen_of / "
			+ "screen_transform / visible_world_rect give the hand-worked values and convert both "
			+ "ways; a node of another viewport converts by that viewport's view.",
		"tags": ["pointer", "camera"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])  # a person's wheel or camera keys would change what is measured
	s.arena(Rect2(0, 0, 800, 500))


func run(t: TestContext) -> void:
	var camera := Camera2D.new()
	camera.position = CAMERA_AT
	t.world.add_child(camera)
	camera.make_current()  # only the current camera moves the viewport's view
	var size := t.world.get_viewport().get_visible_rect().size
	if not t.require(size.x > 0.0 and size.y > 0.0, "the viewport has a size"):
		return

	for zoom: float in [ZOOM_IN, ZOOM_OUT]:
		camera.zoom = Vector2(zoom, zoom)
		await t.frames(3)  # the viewport takes the camera's view
		_points_convert(t, size, zoom)
		_the_view_is_the_rect_and_transform(t, size, zoom)
	await _another_viewport_without_a_camera(t)


## The camera's position is the screen's centre `size / 2` and a world pixel is `zoom` screen
## pixels, so a world point `w` shows at `size / 2 + (w - CAMERA_AT) * zoom`.
func _points_convert(t: TestContext, size: Vector2, zoom: float) -> void:
	var ctx: Node = t.world
	var label := " at zoom %s" % zoom
	var centre := size / 2.0
	var screen := centre + BESIDE * zoom

	t.expect_eq(
		Pointer.screen_of(ctx, CAMERA_AT),
		centre,
		"the camera's point is mid-screen" + label,
	)
	t.expect_eq(
		Pointer.world_of(ctx, centre),
		CAMERA_AT,
		"mid-screen is the camera's point" + label,
	)
	t.expect_eq(
		Pointer.screen_of(ctx, CAMERA_AT + BESIDE),
		screen,
		"screen_of a point beside" + label,
	)
	t.expect_eq(
		Pointer.world_of(ctx, screen),
		CAMERA_AT + BESIDE,
		"world_of that screen point" + label,
	)
	t.expect_eq(
		Pointer.screen_of(ctx, Vector2.ZERO),
		centre - CAMERA_AT * zoom,
		"the world's origin is the camera's position times zoom off the middle" + label,
	)
	for p: Vector2 in [Vector2.ZERO, Vector2(-37.5, 412.0), Vector2(799.0, 1.0)]:
		var back := Pointer.world_of(ctx, Pointer.screen_of(ctx, p))
		t.check(back.distance_to(p) < TOLERANCE, "world %s comes back%s" % [p, label])


## The world → screen transform maps by the same rule and scales by the zoom; the visible rect is
## the world the viewport shows: `size / zoom` across with the camera's position in the middle.
func _the_view_is_the_rect_and_transform(t: TestContext, size: Vector2, zoom: float) -> void:
	var ctx: Node = t.world
	var label := " at zoom %s" % zoom
	var transform := Pointer.screen_transform(ctx)
	t.expect_eq(
		transform * (CAMERA_AT + BESIDE),
		size / 2.0 + BESIDE * zoom,
		"screen_transform" + label,
	)
	t.expect_near(transform.get_scale().x, zoom, TOLERANCE, "screen_transform's scale" + label)

	var rect := Pointer.visible_world_rect(ctx)
	t.expect_eq(rect.size, size / zoom, "the visible rect is the screen over the zoom" + label)
	t.expect_eq(rect.get_center(), CAMERA_AT, "the camera is mid visible rect" + label)
	t.expect_eq(rect.position, CAMERA_AT - size / zoom / 2.0, "the visible rect's corner" + label)


## A node of a standalone viewport with no camera converts by the identity over that viewport's own
## rect, not by the main viewport's camera view.
func _another_viewport_without_a_camera(t: TestContext) -> void:
	var side := SubViewport.new()
	side.size = SIDE_SIZE
	var node := Node2D.new()
	side.add_child(node)
	t.world.add_child(side)
	await t.frames(2)
	var p := Vector2(123.0, 45.0)
	t.expect_eq(Pointer.world_of(node, p), p, "with no camera a screen point is the world point")
	t.expect_eq(Pointer.screen_of(node, p), p, "with no camera a world point is the screen point")
	t.expect_eq(Pointer.screen_transform(node), Transform2D.IDENTITY, "with no camera the identity")
	t.expect_eq(
		Pointer.visible_world_rect(node),
		Rect2(Vector2.ZERO, Vector2(SIDE_SIZE)),
		"the visible rect is the standalone viewport's own",
	)
	side.queue_free()
