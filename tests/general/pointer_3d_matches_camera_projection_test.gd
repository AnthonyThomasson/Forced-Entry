extends GameTest
## Pointer in 3D against the engine's own projection (#193 turn-ctl, interface 26): the screen point
## `Pointer.screen_of` gives a world point is where the 3D camera draws it, i.e. the displayed
## rect's corner plus `Camera3D.unproject_position` of the ground point `(x, 0, y) * unit` scaled
## from the picture's pixels to the rect's. Pointer builds its affine from the camera's pose and
## size; the engine projects through its own matrices, so the two agree only if Pointer's maths is
## right. Checked at both oversample settings (the 3D viewport rendered once or twice the picture),
## at an odd yaw (137) and a zoom other than 1, at points near the focus and far from the origin.

const SCREEN := Vector2i(640, 360)
const FOCUS := Vector2(1000.0, 500.0)
const YAW := 137.0
const ZOOM := 1.7
## Ground points as offsets from the focus, and the largest error allowed in px of screen.
const OFFSETS := [
	Vector2(0.0, 0.0),
	Vector2(120.0, -60.0),
	Vector2(-300.0, 210.0),
	Vector2(2500.0, 1800.0),
	Vector2(-4000.0, 3500.0),
]
const TOLERANCE := 0.01

var _screen: SubViewport
var _view: SubViewport
var _camera2d: Camera2D
var _rect: TextureRect


func describe() -> Dictionary:
	return {
		"name": "Pointer in 3D agrees with the 3D camera's own projection",
		"description": "Pointer.screen_of matches the displayed rect's corner plus the Camera3D's "
			+ "unproject_position scaled to the rect, at oversample 1 and 2, yaw 137 and zoom "
			+ "1.7, near the focus and far from the origin.",
		"tags": ["pointer", "camera", "3d", "render"],
		"timeout": 12.0,
	}


func run(t: TestContext) -> void:
	for oversample: int in [1, 2]:
		var rig := _build(t, oversample)
		await t.frames(3)
		_check_points(t, rig, oversample)
		rig.queue_free()
		_view.queue_free()
		_rect.queue_free()
		_screen.queue_free()
		await t.frames(2)


func _build(t: TestContext, oversample: int) -> CameraRig:
	_screen = SubViewport.new()
	_screen.size = SCREEN
	_screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(_screen)
	_camera2d = Camera2D.new()
	_camera2d.position = FOCUS
	_camera2d.zoom = Vector2(ZOOM, ZOOM)
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
	var rig := CameraRig.new()
	rig.yaw = YAW
	rig.oversample = oversample
	_view.add_child(rig)
	rig.bind(_camera2d, _view, _rect)
	return rig


func _check_points(t: TestContext, rig: CameraRig, oversample: int) -> void:
	t.check(
		_view.size == rig.internal_size() * oversample,
		"premise: the 3D viewport is the picture times %d (%s)" % [oversample, _view.size],
	)
	var worst := 0.0
	for offset: Vector2 in OFFSETS:
		var world := FOCUS + offset
		var ground := Vector3(world.x, 0.0, world.y) * RenderConfig.unit
		var drawn := rig.camera.unproject_position(ground)
		var expected := _rect.global_position + drawn * _rect.size / Vector2(_view.size)
		var got := Pointer.screen_of(_camera2d, world)
		worst = maxf(worst, got.distance_to(expected))
	t.check(
		worst <= TOLERANCE,
		"oversample %d: screen_of is where the camera draws the point (worst error %.5f px)" % [
			oversample,
			worst,
		],
	)
