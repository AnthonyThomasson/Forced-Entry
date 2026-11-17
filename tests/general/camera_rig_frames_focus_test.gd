extends GameTest
## The 3D camera rig (#193 rule 3, General, interface 27): an orthographic `Camera3D` at the near
## top-down pitch (80 degrees) that frames what the sim's `Camera2D` frames. The `Camera2D` stays
## the focus, zoom and shake source, so the rig reads its screen centre (the focus plus its shake
## offset) and its zoom, and turns the ground (x, 0, y) of the mirror into the screen at 1 px per
## world unit at zoom 1. Checked by where the camera projects ground points on the 2D screen the rig
## serves: the focus at its centre, at the default yaw (north up) ground +x straight across and +y
## down foreshortened by sin 80 = 0.98481, a height lifting by cos 80 = 0.17365, the zoom as a scale
## whose picture pixel is a whole number of screen pixels and one art pixel at 1x to 3x, the shake
## as a move, and the yaw as a property (at 45 degrees too). The expected pixels are worked by hand,
## not the rig's formula. Headless proves the maths, not the look (the dummy renderer draws
## nothing).

const SCREEN := Vector2i(640, 360)
const FOCUS := Vector2(1000.0, 500.0)
## Screen pixels one 2D pixel of ground moves at yaw 45 and pitch 80, along +x and +y of the ground
## (the screen's x then y): cos 45 across, sin 80 times sin 45 down.
const ALONG_X := Vector2(0.70711, 0.69636)
const ALONG_Y := Vector2(-0.70711, 0.69636)
## The pitch's foreshortening of the ground's depth, sin 80, and a height's lift, cos 80.
const DEPTH := 0.98481
const LIFT := 0.17365

var _screen: SubViewport
var _view: SubViewport
var _camera2d: Camera2D
var _rect: TextureRect
var _rig: Node3D


func describe() -> Dictionary:
	return {
		"name": "The 3D camera rig frames the Camera2D's focus at the near top-down pitch",
		"description": "Ground points project from the 2D camera's focus at the 80 degree pitch, "
			+ "heights lift straight up, the zoom scales and sets the picture's pixel to the "
			+ "art's, "
			+ "a shake moves the view and the yaw is a property; the camera is orthographic.",
		"tags": ["camera", "3d", "render"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()  # it builds its own rig and camera: the session shows none


func run(t: TestContext) -> void:
	_build(t)
	await t.frames(4)
	var camera := _rig.get("camera") as Camera3D
	if not t.require(camera != null, "the rig has a Camera3D"):
		return
	t.check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "the camera is orthographic")
	t.check(_view.get_camera_3d() == camera, "it is the 3D view's current camera")
	_check_focus(t, camera)
	_check_default(t, camera)
	await _check_zoom(t, camera)
	await _check_shake_and_follow(t, camera)
	await _check_yaw(t, camera)


## The 2D screen (a SubViewport) with the sim's `Camera2D` on `FOCUS`, the picture of the 3D view
## on a TextureRect in it, and the 3D view with the rig.
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


## Where a ground point of the 2D world shows on the 2D screen: through the 3D camera, then the
## picture's place and size on the screen.
func _on_screen(camera: Camera3D, ground: Vector2, height := 0.0) -> Vector2:
	var in_view := camera.unproject_position(Vector3(ground.x, height, ground.y))
	return _rect.position + in_view * _rect.size / Vector2(_view.size)


func _check_focus(t: TestContext, camera: Camera3D) -> void:
	var at := _on_screen(camera, FOCUS)
	var middle := Vector2(SCREEN) * 0.5
	t.expect_near(at.x, middle.x, 0.1, "the 2D camera's focus is at the screen's centre x")
	t.expect_near(at.y, middle.y, 0.1, "the 2D camera's focus is at the screen's centre y")


## At the default yaw (0, north up) and the 80 degree pitch: ground +x runs straight across, ground
## +y down by sin(pitch) px for each px of ground; a height lifts straight up by cos(pitch).
func _check_default(t: TestContext, camera: Camera3D) -> void:
	t.expect_near(float(_rig.get("yaw")), 0.0, 0.001, "the rig starts at north")
	t.expect_near(RenderConfig.pitch_degrees, 80.0, 0.001, "the pitch is 80 degrees")
	var middle := Vector2(SCREEN) * 0.5
	var x_run := _on_screen(camera, FOCUS + Vector2(100, 0)) - middle
	var y_run := _on_screen(camera, FOCUS + Vector2(0, 100)) - middle
	t.expect_near(x_run.x, 100.0, 0.2, "100 px along +x: %.1f px across" % x_run.x)
	t.expect_near(x_run.y, 0.0, 0.2, "100 px along +x: %.1f px down" % x_run.y)
	t.expect_near(y_run.x, 0.0, 0.2, "100 px along +y: %.1f px across" % y_run.x)
	t.expect_near(y_run.y, DEPTH * 100.0, 0.2, "100 px along +y: %.1f px down" % y_run.y)
	var up := middle - _on_screen(camera, FOCUS, 40.0)
	t.expect_near(up.y, 40.0 * LIFT, 0.2, "40 units of height lift the point %.1f px" % up.y)
	t.expect_near(up.x, 0.0, 0.2, "a height moves straight up the screen")


## Twice the zoom: twice the pixels for the same ground, and the picture's pixel is the art's: at
## zoom 1, 2 and 3 a picture pixel is one art pixel (a 2D px of ground) shown 1, 2 and 3 screen
## pixels wide; at 0.5 it covers two art pixels in one screen pixel.
func _check_zoom(t: TestContext, camera: Camera3D) -> void:
	var middle := Vector2(SCREEN) * 0.5
	for zoom: float in [1.0, 2.0, 3.0, 0.5]:
		_camera2d.zoom = Vector2(zoom, zoom)
		await t.frames(3)
		var x_run := _on_screen(camera, FOCUS + Vector2(50, 0)) - middle
		t.expect_near(x_run.x, 50.0 * zoom, 0.3, "at zoom %s, 50 px along +x" % zoom)
		var y_run := _on_screen(camera, FOCUS + Vector2(0, 50)) - middle
		t.expect_near(y_run.y, 50.0 * zoom * DEPTH, 0.3, "at zoom %s the depth scales too" % zoom)
		t.expect_near(
			float(_rig.call("texel")), 2.0 if zoom < 1.0 else 1.0, 0.001,
			"at zoom %s a picture pixel covers %s art pixels" % [zoom, 2.0 if zoom < 1.0 else 1.0],
		)
		var shown_scale := maxf(roundf(zoom), 1.0)
		t.expect_near(_rect.size.x / float(_view.size.x), shown_scale, 0.001,
			"at zoom %s a picture pixel is %s screen pixels" % [zoom, shown_scale])
	_camera2d.zoom = Vector2.ONE
	await t.frames(3)


## The 2D camera's shake offset (it moves the picture, not the camera's own position) and a move
## of the camera both move the 3D view with it.
func _check_shake_and_follow(t: TestContext, camera: Camera3D) -> void:
	var middle := Vector2(SCREEN) * 0.5
	_camera2d.offset = Vector2(40.0, -25.0)
	await t.frames(3)
	var shaken := _on_screen(camera, FOCUS + Vector2(40.0, -25.0))
	t.expect_near(shaken.x, middle.x, 0.2, "a shake offset is followed (x)")
	t.expect_near(shaken.y, middle.y, 0.2, "a shake offset is followed (y)")
	_camera2d.offset = Vector2.ZERO
	_camera2d.position = FOCUS + Vector2(300.0, 120.0)
	await t.frames(3)
	var moved := _on_screen(camera, FOCUS + Vector2(300.0, 120.0))
	t.expect_near(moved.x, middle.x, 0.2, "the rig follows the camera as it moves (x)")
	t.expect_near(moved.y, middle.y, 0.2, "the rig follows the camera as it moves (y)")


## The yaw is a property (degrees): at 45 the ground's +x runs down-right and +y down-left, 0.7071
## px across and 0.6964 px down for each px of ground.
func _check_yaw(t: TestContext, camera: Camera3D) -> void:
	_rig.set("yaw", 45.0)
	await t.frames(3)
	var middle := Vector2(SCREEN) * 0.5
	var focus := _camera2d.get_screen_center_position()
	var x_run := _on_screen(camera, focus + Vector2(100, 0)) - middle
	var y_run := _on_screen(camera, focus + Vector2(0, 100)) - middle
	t.expect_near(x_run.x, ALONG_X.x * 100.0, 0.3, "yaw 45: +x runs %.1f px across" % x_run.x)
	t.expect_near(x_run.y, ALONG_X.y * 100.0, 0.3, "yaw 45: +x runs %.1f px down" % x_run.y)
	t.expect_near(y_run.x, ALONG_Y.x * 100.0, 0.3, "yaw 45: +y runs %.1f px across" % y_run.x)
	t.expect_near(y_run.y, ALONG_Y.y * 100.0, 0.3, "yaw 45: +y runs %.1f px down" % y_run.y)
