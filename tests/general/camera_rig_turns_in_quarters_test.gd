extends GameTest
## A press of a camera-turn key turns the 3D camera a quarter round its focus (#193 phase 2b G16,
## interface 27): E one way and Q the other, eased, ending exactly on north, east, south or west, so
## it only ever rests on a cardinal. It starts at north (yaw 0, up the screen as in 2D); a second
## press while it turns queues another quarter; holding a key does not turn on; the focus stays put
## on the screen mid-turn. A world with no 3D rig (the 2D render) is not turned by the keys. The
## expected angles are the spec's multiples of 90 degrees, not the rig's formula.

const SCREEN := Vector2i(640, 360)
const FOCUS := Vector2(1000.0, 500.0)
## Long enough for a quarter at the default easing (about 0.4 s) with room to spare.
const QUARTER := 0.8

var _screen: SubViewport
var _view: SubViewport
var _camera2d: Camera2D
var _rig: Node3D


func describe() -> Dictionary:
	return {
		"name": "Pressing Q / E turns the 3D camera a quarter round its focus",
		"description": "E steps the rig's yaw a quarter one way and Q the other, eased, resting "
			+ "only on a cardinal; it starts at north; presses queue; holding does not repeat; the "
			+ "focus "
			+ "stays mid-screen; with no rig (2D) the keys turn nothing.",
		"tags": ["camera", "3d", "render", "input"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])  # a person's keys would change what is measured
	s.set_static(CameraTurnConfig, &"step_degrees", 90.0)
	s.set_static(CameraTurnConfig, &"speed_degrees", 540.0)


func run(t: TestContext) -> void:
	Keybinds.bindings.reset_all()
	await _two_d_world_is_not_turned(t)
	_build(t)
	await t.frames(3)
	t.expect_near(_rig.get("yaw"), 0.0, 0.01, "it starts at north, yaw 0")
	t.expect_eq(RenderConfig.yaw_degrees, 0.0, "the configured start is north")

	await t.seconds(0.5)
	t.expect_near(_rig.get("yaw"), 0.0, 0.01, "no key pressed: it does not turn")

	await _press(t, "camera_turn_right", 0.15)
	var midway: float = _rig.get("yaw")
	t.check(midway > 5.0 and midway < 90.0, "mid-turn it is between the cardinals (%f)" % midway)
	t.check(_rig.call("turning"), "and it reports turning")
	await t.seconds(QUARTER)
	t.expect_near(_rig.get("yaw"), 90.0, 0.001, "E turned a quarter and rests on east")
	t.check(not _rig.call("turning"), "and no longer turning")

	Input.action_press("camera_turn_right")
	await t.seconds(QUARTER)
	t.expect_near(_rig.get("yaw"), 180.0, 0.001, "pressed again it turned another quarter")
	await t.seconds(QUARTER)
	t.expect_near(_rig.get("yaw"), 180.0, 0.001, "held on, it does not turn on")
	Input.action_release("camera_turn_right")
	await t.frames(2)

	await _press(t, "camera_turn_left", QUARTER)
	t.expect_near(_rig.get("yaw"), 90.0, 0.001, "Q turned a quarter the other way")

	await _presses_queue(t)
	await _turn_through_north(t)
	await _speed_is_tunable(t)
	await _focus_stays_put(t)
	await _setting_the_yaw_is_a_rest(t)


## Press the key for one frame's worth, let go, and wait `seconds`.
func _press(t: TestContext, action: String, seconds: float) -> void:
	Input.action_press(action)
	await t.frames(2)
	Input.action_release(action)
	await t.seconds(seconds)


## Two quick presses are two quarters, and they end on a cardinal.
func _presses_queue(t: TestContext) -> void:
	var before: float = _rig.get("yaw")
	await _press(t, "camera_turn_right", 0.05)
	await _press(t, "camera_turn_right", QUARTER * 2.0)
	t.expect_near(
		absf(_turned(before, _rig.get("yaw"))), 180.0, 0.001, "two presses are a half turn, at rest"
	)


## From north a turn left rests on west (270), and the yaw stays in [0, 360).
func _turn_through_north(t: TestContext) -> void:
	_rig.set("yaw", 0.0)
	await _press(t, "camera_turn_left", QUARTER)
	t.expect_near(_rig.get("yaw"), 270.0, 0.001, "left of north is west, 270")
	await _press(t, "camera_turn_right", QUARTER)
	t.expect_near(_rig.get("yaw"), 0.0, 0.001, "and right of west is north again")


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


## A faster turn arrives sooner: at 2000 degrees a second a quarter is done in 0.2 s.
func _speed_is_tunable(t: TestContext) -> void:
	CameraTurnConfig.speed_degrees = 2000.0
	CameraTurnConfig.ease_rate = 100.0
	_rig.set("yaw", 0.0)
	await _press(t, "camera_turn_right", 0.2)
	t.expect_near(_rig.get("yaw"), 90.0, 0.001, "at 2000 degrees a second a quarter takes 0.2 s")
	CameraTurnConfig.speed_degrees = 540.0
	CameraTurnConfig.ease_rate = 10.0


## Turning is about the focus: it stays mid-screen at every yaw the key passes through.
func _focus_stays_put(t: TestContext) -> void:
	_rig.set("yaw", 0.0)
	Input.action_press("camera_turn_right")
	await t.frames(2)
	Input.action_release("camera_turn_right")
	var middle := Vector2(SCREEN) * 0.5
	for i in 5:
		await t.seconds(0.1)
		var at := Pointer.screen_of(_camera2d, FOCUS)
		t.check(at.distance_to(middle) < 0.2, "the focus stays mid-screen (%s)" % at)
	await t.seconds(QUARTER)


## Setting the yaw by hand puts the turn's target there too: no turn is left to finish.
func _setting_the_yaw_is_a_rest(t: TestContext) -> void:
	_rig.set("yaw", 180.0)
	await t.seconds(0.5)
	t.expect_near(_rig.get("yaw"), 180.0, 0.001, "a yaw set by hand stays")


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
