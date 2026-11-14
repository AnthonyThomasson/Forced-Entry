extends GameTest
## The 3D camera rig (#193 rule 3, General, interface 27): an orthographic `Camera3D` at the
## isometric pitch that frames what the sim's `Camera2D` frames. The `Camera2D` stays the focus,
## zoom and shake source, so the rig reads its screen centre (the focus plus its shake offset) and
## its zoom, and turns the ground (x, 0, y) of the mirror into the screen at 1 px per world unit at
## zoom 1. Checked by where the camera projects ground points on the 2D screen the rig serves: the
## focus at its centre, ground +x and +y at the true isometric slope (tan 30 degrees, from the
## spec's 35.264 degree pitch at 45 degrees of yaw), a height straight up, the zoom as a scale, the
## shake as a move, and the yaw as the property the next jobs turn. The expected pixels are the
## isometric projection worked by hand (cos 45 = 0.7071, sin 35.264 = 0.5774), not the rig's
## formula. Headless proves the maths, not the look (the dummy renderer draws nothing).

const SCREEN := Vector2i(640, 360)
const FOCUS := Vector2(1000.0, 500.0)
## Screen pixels one 2D pixel of ground moves, at yaw 45 and pitch 35.264, along +x and +y of the
## ground (the screen's x then y): the 2:1-ish diamond of the true isometric view.
const ALONG_X := Vector2(0.70711, 0.40825)
const ALONG_Y := Vector2(-0.70711, 0.40825)
## The pitch's foreshortening of the ground's depth, sin 35.264, and a height's lift, cos 35.264.
const DEPTH := 0.57735
const LIFT := 0.81650

var _screen: SubViewport
var _view: SubViewport
var _camera2d: Camera2D
var _rect: TextureRect
var _rig: Node3D


func describe() -> Dictionary:
	return {
		"name": "The 3D camera rig frames the Camera2D's focus at the isometric pitch",
		"description": "Ground points project from the 2D camera's focus at the isometric slope, "
			+ "heights lift straight up, the zoom scales, a shake moves the view and the yaw is "
			+ "a property; the camera is orthographic.",
		"tags": ["camera", "3d", "render"],
		"timeout": 8.0,
	}


func run(t: TestContext) -> void:
	_build(t)
	await t.frames(4)
	var camera := _rig.get("camera") as Camera3D
	if not t.require(camera != null, "the rig has a Camera3D"):
		return
	t.check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "the camera is orthographic")
	t.check(_view.get_camera_3d() == camera, "it is the 3D view's current camera")
	_check_focus(t, camera)
	_check_isometric(t, camera)
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


## At yaw 45 and the isometric pitch: ground +x runs down-right and ground +y down-left, 0.7071
## px across and 0.4082 px down for each px of ground; a height lifts straight up by cos(pitch).
func _check_isometric(t: TestContext, camera: Camera3D) -> void:
	var middle := Vector2(SCREEN) * 0.5
	var x_run := _on_screen(camera, FOCUS + Vector2(100, 0)) - middle
	var y_run := _on_screen(camera, FOCUS + Vector2(0, 100)) - middle
	t.expect_near(x_run.x, ALONG_X.x * 100.0, 0.2, "100 px along +x: %.1f px across" % x_run.x)
	t.expect_near(x_run.y, ALONG_X.y * 100.0, 0.2, "100 px along +x: %.1f px down" % x_run.y)
	t.expect_near(y_run.x, ALONG_Y.x * 100.0, 0.2, "100 px along +y: %.1f px across" % y_run.x)
	t.expect_near(y_run.y, ALONG_Y.y * 100.0, 0.2, "100 px along +y: %.1f px down" % y_run.y)
	var up := middle - _on_screen(camera, FOCUS, 40.0)
	t.expect_near(up.y, 40.0 * LIFT, 0.2, "40 units of height lift the point %.1f px" % up.y)
	t.expect_near(up.x, 0.0, 0.2, "a height moves straight up the screen")


## Twice the zoom: twice the pixels for the same ground.
func _check_zoom(t: TestContext, camera: Camera3D) -> void:
	_camera2d.zoom = Vector2(2.0, 2.0)
	await t.frames(3)
	var middle := Vector2(SCREEN) * 0.5
	var x_run := _on_screen(camera, FOCUS + Vector2(50, 0)) - middle
	t.expect_near(x_run.x, ALONG_X.x * 100.0, 0.3, "at zoom 2, 50 px along +x is 100 px of screen")
	t.expect_near(x_run.y, ALONG_X.y * 100.0, 0.3, "at zoom 2 the depth scales too")
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


## The yaw is a property (degrees): at 0 the ground's +x runs straight right and +y straight down
## the screen, foreshortened by sin(pitch).
func _check_yaw(t: TestContext, camera: Camera3D) -> void:
	_rig.set("yaw", 0.0)
	await t.frames(3)
	var middle := Vector2(SCREEN) * 0.5
	var focus := _camera2d.get_screen_center_position()
	var x_run := _on_screen(camera, focus + Vector2(100, 0)) - middle
	var y_run := _on_screen(camera, focus + Vector2(0, 100)) - middle
	t.expect_near(x_run.x, 100.0, 0.3, "yaw 0: +x runs 100 px across")
	t.expect_near(x_run.y, 0.0, 0.3, "yaw 0: +x runs level")
	t.expect_near(y_run.x, 0.0, 0.3, "yaw 0: +y runs straight down")
	t.expect_near(y_run.y, 100.0 * DEPTH, 0.3, "yaw 0: +y runs 100 * sin(pitch) px down")
