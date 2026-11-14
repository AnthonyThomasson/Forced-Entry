extends GameTest
## Holding a camera-turn key turns the 3D camera round its focus (#193 rule 4, interface 27):
## E one way and Q the other, smoothly at `RenderConfig.turn_speed_degrees` (90 degrees a second
## by default), free of any snap, and releasing stops it where it is. The focus stays put on the
## screen while it turns. A world with no 3D rig (the 2D render) is not turned by the keys. The
## expected angles are the spec's 90 degrees a second times the time held, not the rig's formula.

const SCREEN := Vector2i(640, 360)
const FOCUS := Vector2(1000.0, 500.0)

var _screen: SubViewport
var _view: SubViewport
var _camera2d: Camera2D
var _rig: Node3D


func describe() -> Dictionary:
	return {
		"name": "Holding Q / E turns the 3D camera round its focus",
		"description": "E turns the rig's yaw one way and Q the other at the tunable speed "
			+ "(90 degrees a second), freely; releasing stops it; the focus stays mid-screen; "
			+ "with no rig (2D) the keys turn nothing.",
		"tags": ["camera", "3d", "render", "input"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])  # a person's keys would change what is measured
	s.set_static(RenderConfig, &"internal_lines", 0)
	s.set_static(RenderConfig, &"turn_speed_degrees", 90.0)


func run(t: TestContext) -> void:
	Keybinds.bindings.reset_all()
	await _two_d_world_is_not_turned(t)
	_build(t)
	await t.frames(3)
	var start: float = _rig.get("yaw")
	t.expect_near(start, RenderConfig.yaw_degrees, 0.01, "it starts at the configured yaw")

	await t.seconds(0.5)
	t.expect_near(_rig.get("yaw"), start, 0.01, "no key held: it does not turn")

	Input.action_press("camera_turn_right")
	await t.seconds(0.2)
	var after_a_moment: float = _rig.get("yaw")
	t.expect_near(
		_turned(start, after_a_moment), 18.0, 3.0, "E held 0.2 s turns about 18 degrees (free yaw)"
	)
	await t.seconds(0.8)
	var held_a_second: float = _rig.get("yaw")
	t.expect_near(
		_turned(start, held_a_second), 90.0, 3.0, "E held one second turns about 90 degrees"
	)
	Input.action_release("camera_turn_right")
	await t.frames(2)
	var stopped: float = _rig.get("yaw")
	await t.seconds(0.3)
	t.expect_near(_rig.get("yaw"), stopped, 0.01, "released: it stays where it stopped")

	Input.action_press("camera_turn_left")
	await t.seconds(0.5)
	Input.action_release("camera_turn_left")
	await t.frames(2)
	var back: float = _rig.get("yaw")
	t.expect_near(
		_turned(stopped, back), -45.0, 3.0, "Q held half a second turns 45 degrees the other way"
	)

	await _speed_is_tunable(t)
	await _focus_stays_put(t)


## A world with no rig: holding a turn key leaves what Pointer shows unchanged.
func _two_d_world_is_not_turned(t: TestContext) -> void:
	var camera := Camera2D.new()
	camera.position = FOCUS
	t.world.add_child(camera)
	camera.make_current()
	await t.frames(3)
	var before := Pointer.screen_transform(t.world)
	Input.action_press("camera_turn_right")
	await t.seconds(0.5)
	Input.action_release("camera_turn_right")
	t.check(
		Pointer.screen_transform(t.world).is_equal_approx(before),
		"with no 3D rig the turn keys change nothing",
	)
	camera.queue_free()
	await t.frames(2)


func _speed_is_tunable(t: TestContext) -> void:
	RenderConfig.turn_speed_degrees = 30.0
	var before: float = _rig.get("yaw")
	Input.action_press("camera_turn_right")
	await t.seconds(1.0)
	Input.action_release("camera_turn_right")
	await t.frames(2)
	t.expect_near(
		_turned(before, _rig.get("yaw")), 30.0, 2.0, "at 30 degrees a second, one second is 30"
	)


## Turning is about the focus: it stays mid-screen at every yaw the key passes through.
func _focus_stays_put(t: TestContext) -> void:
	RenderConfig.turn_speed_degrees = 90.0
	Input.action_press("camera_turn_right")
	var middle := Vector2(SCREEN) * 0.5
	for i in 4:
		await t.seconds(0.25)
		var at := Pointer.screen_of(_camera2d, FOCUS)
		t.check(at.distance_to(middle) < 0.2, "the focus stays mid-screen (%s)" % at)
	Input.action_release("camera_turn_right")
	await t.frames(2)


## The signed turn from `from` to `to` in degrees, through the wrap at 360.
func _turned(from: float, to: float) -> float:
	return wrapf(to - from, -180.0, 180.0)


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
	var rect := TextureRect.new()
	rect.texture = _view.get_texture()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.add_child(rect)
	_rig = CameraRig.new()
	_view.add_child(_rig)
	_rig.bind(_camera2d, _view, rect)
