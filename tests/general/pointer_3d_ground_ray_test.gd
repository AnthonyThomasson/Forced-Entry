extends GameTest
## Pointer in the 3D render mode (#193 rule 5, interface 26): with the camera rig bound, a screen
## point is the camera ray meeting the ground plane y = 0, and the ground's place on the screen is
## the exact affine of the orthographic camera at its yaw, pitch and zoom, read through the
## DISPLAYED rect of the 3D view (so the picture's pixel size changes nothing). The expected pixels
## are worked by hand from the near top-down projection at pitch 80 (sin = 0.98481): for a ground
## step (dx, dy) the screen moves (dx cos(yaw) - dy sin(yaw), sin(pitch) * (dx sin(yaw) + dy
## cos(yaw))) per zoom, never by asking Pointer or the rig. Run at the window's own pixel (texel
## match off) and with the art's texels matched, at yaw 0, 45 and 120.

const SCREEN := Vector2i(640, 360)
const FOCUS := Vector2(1000.0, 500.0)
## sin of the 80 degree pitch: how much the ground's depth is foreshortened.
const DEPTH := 0.98481
## Per yaw: the screen step of 100 px of ground along +x and along +y, then the half extent of
## the ground the 640 x 360 screen shows along x and along y (the bounding rect of its corners),
## at zoom 1. Worked by hand: yaw 120 has cos -0.5 and sin 0.866025, so +x goes (-50, 85.287) and
## +y goes (-86.6025, -49.2404); the corners' ground x reaches 320 * 0.5 + 182.777 * 0.866025 =
## 318.29 and y reaches 320 * 0.866025 + 182.777 * 0.5 = 368.52 (182.777 = 180 / 0.98481).
const CASES := [
	{ "yaw": 0.0, "x": Vector2(100.0, 0.0), "y": Vector2(0.0, 98.481),
		"half": Vector2(320.0, 182.777) },
	{ "yaw": 45.0, "x": Vector2(70.711, 69.636), "y": Vector2(-70.711, 69.636),
		"half": Vector2(355.517, 355.517) },
	{ "yaw": 120.0, "x": Vector2(-50.0, 85.287), "y": Vector2(-86.6025, -49.2404),
		"half": Vector2(318.289, 368.517) },
]

var _screen: SubViewport
var _view: SubViewport
var _camera2d: Camera2D
var _rect: TextureRect
var _rig: Node3D


func describe() -> Dictionary:
	return {
		"name": "Pointer in 3D: the mouse is the camera ray meeting the ground",
		"description": "With the camera rig bound, world_of / screen_of / screen_transform / "
			+ "visible_world_rect follow the orthographic camera at yaw 0, 45 and 120, at the "
			+ "window's pixel and with the texels matched, through the displayed rect; "
			+ "inject keeps working; the rig leaving the tree gives the 2D body back.",
		"tags": ["pointer", "camera", "3d", "render"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()  # it builds its own rig and camera: the session shows none
	s.set_static(RenderConfig, &"texel_match", false)


func run(t: TestContext) -> void:
	_build(t)
	for matched: bool in [false, true]:
		RenderConfig.texel_match = matched
		for c: Dictionary in CASES:
			_rig.set("yaw", c["yaw"])
			await t.frames(3)
			_check_case(t, c, "yaw %s, texels matched %s" % [c["yaw"], matched])
	RenderConfig.texel_match = true
	_rig.set("yaw", 45.0)
	await t.frames(3)
	await _check_zoom_and_inject(t)
	_rig.queue_free()
	await t.frames(2)
	t.expect_eq(
		Pointer.screen_transform(_camera2d), _screen.get_canvas_transform(),
		"with the rig gone Pointer is the canvas transform again",
	)


func _build(t: TestContext) -> void:
	_screen = SubViewport.new()
	_screen.size = SCREEN
	_screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(_screen)
	_camera2d = Camera2D.new()
	_camera2d.position = FOCUS
	_screen.add_child(_camera2d)
	_camera2d.make_current()
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(_view)
	_rect = TextureRect.new()
	_rect.texture = _view.get_texture()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.add_child(_rect)
	_rig = CameraRig.new()
	_view.add_child(_rig)
	_rig.bind(_camera2d, _view, _rect)


func _check_case(t: TestContext, c: Dictionary, label: String) -> void:
	var middle := Vector2(SCREEN) * 0.5
	var x_step: Vector2 = c["x"]
	var y_step: Vector2 = c["y"]
	# The focus is mid-screen, and 100 px of ground along each axis lands where worked out.
	_near(t, Pointer.screen_of(_camera2d, FOCUS), middle, "focus mid-screen, " + label)
	_near(
		t, Pointer.screen_of(_camera2d, FOCUS + Vector2(100, 0)), middle + x_step,
		"+x 100 px, " + label,
	)
	_near(
		t, Pointer.screen_of(_camera2d, FOCUS + Vector2(0, 100)), middle + y_step,
		"+y 100 px, " + label,
	)
	# The mouse ray meets the ground at the point that screen point shows.
	_near(
		t,
		Pointer.world_of(_camera2d, middle + x_step),
		FOCUS + Vector2(100, 0),
		"world_of " + label,
	)
	_near(
		t, Pointer.world_of(_camera2d, middle + x_step + y_step), FOCUS + Vector2(100, 100),
		"world_of a diagonal, " + label,
	)
	# The transform is the same affine: its columns are the steps per px of ground.
	var transform := Pointer.screen_transform(_camera2d)
	_near(t, transform.x * 100.0, x_step, "screen_transform x column, " + label)
	_near(t, transform.y * 100.0, y_step, "screen_transform y column, " + label)
	_near(t, transform * FOCUS, middle, "screen_transform of the focus, " + label)
	# The visible rect is the bounding rect of the screen's four corners on the ground.
	var rect := Pointer.visible_world_rect(_camera2d)
	var half: Vector2 = c["half"]
	_near(t, rect.get_center(), FOCUS, "visible rect centred on the focus, " + label)
	_near(t, rect.size, half * 2.0, "visible rect size, " + label, 0.3)


## At zoom 2 (yaw 0) the same ground is twice the pixels: 100 px along +x is 200 px across and
## 100 px along +y is 2 * 98.481 = 196.96 down. A screen point injected for the mouse is read back
## as the ground point under it: 60 px right of the middle is 30 px of ground right of the focus.
func _check_zoom_and_inject(t: TestContext) -> void:
	_camera2d.zoom = Vector2(2.0, 2.0)
	_rig.set("yaw", 0.0)
	await t.frames(3)
	var middle := Vector2(SCREEN) * 0.5
	_near(
		t, Pointer.screen_of(_camera2d, FOCUS + Vector2(100, 0)), middle + Vector2(200.0, 0.0),
		"at zoom 2, +x 100 px",
	)
	_near(
		t, Pointer.screen_of(_camera2d, FOCUS + Vector2(0, 100)), middle + Vector2(0.0, 196.96),
		"at zoom 2, +y 100 px",
	)
	Pointer.inject(middle + Vector2(60.0, 0.0))
	_near(
		t,
		Pointer.screen_mouse(_camera2d),
		middle + Vector2(60.0, 0.0),
		"the injected screen point",
	)
	_near(t, Pointer.world_mouse(_camera2d), FOCUS + Vector2(30.0, 0.0), "the injected world point")
	Pointer.release()


func _near(
	t: TestContext, actual: Vector2, expected: Vector2, message: String, tolerance := 0.15
) -> void:
	t.check(
		actual.distance_to(expected) <= tolerance,
		"%s: %s, expected %s" % [message, actual, expected],
	)
