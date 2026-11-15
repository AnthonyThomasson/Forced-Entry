extends GameTest
## The sim's camera works in screen terms in the 3D render mode (#193 rule 5): a spectator's pan
## keys and the mouse at a screen edge pan the framing camera up, down, left or right ON THE SCREEN
## at any camera yaw, at the same speed on the screen whichever way it goes, a following camera
## leads toward the mouse on the screen, and the spectator's framing fits the combatants' extent on
## the screen at the current yaw. Judged by WORLD deltas worked by hand from the isometric
## projection (pitch 35.264, sin 0.57735): a ground step (dx, dy) shows as (dx cos(yaw) - dy
## sin(yaw), 0.57735 * (dx sin(yaw) + dy cos(yaw))) on the screen, so the ground direction that
## shows as screen up is (-sin(yaw), -cos(yaw)) and as screen right (cos(yaw), -sin(yaw)); one
## screen px up costs
## 1 / 0.57735 ground px and one right 1, so up is 1.732 times the ground distance of right. It runs
## in a window-sized `SubViewport` of its own (the test world's viewport is 64 px square).

const CameraController := preload("res://scenes/general/camera_controller.gd")
const RigProbe := preload("res://tests/_general/rig_probe.gd")
## The yaws the cases run at, in degrees: a quarter turn (world +x is screen down) and the default.
const YAWS := [90.0, 45.0]
const PAN := 0.5
const SIZE := Vector2i(1152, 648)
## The two combatants of the framing case are this far apart along the ground diagonal, and the
## framing's margin is held at a known value, so the fit is worked by hand: at yaw 45 the diagonal
## (d, d) shows straight down the screen, 0.57735 * 1.41421 * d = 0.81650 * d px tall at zoom 1, and
## the framing grows it by the margin each side.
const APART := 800.0
const MARGIN := 100.0

var _screen: SubViewport
var _camera: Camera2D
var _rig: CameraRig
var _a: Node2D
var _b: Node2D


func describe() -> Dictionary:
	return {
		"name": "The camera pans, leads and frames by the screen in 3D",
		"description": "At yaw 90 and 45 the spectator's up and right keys and the top screen "
			+ "edge pan the framing camera along the ground direction that shows as up or right, "
			+ "up a ground distance 1.732 times right's (the same speed on the screen), a "
			+ "following camera leads toward the mouse on the screen, and the framing fits the "
			+ "combatants' extent on the screen.",
		"tags": ["camera", "3d", "pan", "input"],
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])
	s.arena(Rect2(0, 0, 3000, 2000), { "floor": "concrete" })
	s.set_static(CameraConfig, &"frame_margin", MARGIN)


func run(t: TestContext) -> void:
	_screen = SubViewport.new()
	_screen.size = SIZE
	_screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(_screen)
	_a = _combatant(Vector2(1400, 1000))
	_a.name = "Player"  # the controller's default target
	_b = _combatant(Vector2(1600, 1000))
	_camera = Camera2D.new()
	_camera.set_script(CameraController)
	_screen.add_child(_camera)
	_camera.make_current()
	_camera.frame([_a, _b])
	_rig = RigProbe.open(_screen, _camera, YAWS[0])
	await t.seconds(2.0)
	for yaw: float in YAWS:
		_rig.yaw = yaw
		await t.frames(3)
		await _pan_by_keys(t, yaw)
		await _pan_by_edge(t, yaw)
		await _lead_toward_the_mouse(t, yaw)
	await _framing_fits_the_screen_extent(t)


func _combatant(at: Vector2) -> Node2D:
	var node := Node2D.new()
	node.position = at
	_screen.add_child(node)
	return node


## The ground direction that shows as screen up at `yaw`, and as screen right (worked by hand).
func _ground_up(yaw: float) -> Vector2:
	return Vector2(-sin(deg_to_rad(yaw)), -cos(deg_to_rad(yaw)))


func _ground_right(yaw: float) -> Vector2:
	return Vector2(cos(deg_to_rad(yaw)), -sin(deg_to_rad(yaw)))


## Back to the automatic framing, settled, with the camera where it is (the world delta of a pan is
## read from here).
func _settle(t: TestContext) -> Vector2:
	_camera.frame([_a, _b])
	await t.seconds(CameraConfig.manual_hold + 3.0)
	return _camera.global_position


## Each pan key moves the focus along the ground direction that shows as its way on the screen, and
## up goes 1.732 times as far over the ground as right (the same distance on the screen).
func _pan_by_keys(t: TestContext, yaw: float) -> void:
	var travelled := {}
	for step: Dictionary in [
		{ "key": Keybinds.CAMERA_UP, "name": "up", "dir": _ground_up(yaw) },
		{ "key": Keybinds.CAMERA_RIGHT, "name": "right", "dir": _ground_right(yaw) },
	]:
		var home := await _settle(t)
		Input.action_press(step["key"])
		await t.seconds(PAN)
		Input.action_release(step["key"])
		var moved := _camera.global_position - home
		var want: Vector2 = step["dir"]
		travelled[step["name"]] = moved.length()
		t.check(
			moved.length() > 20.0 and moved.normalized().distance_to(want) < 0.05,
			"at yaw %d the %s key pans the ground along %s (moved %s)" % [
				yaw,
				step["name"],
				want,
				moved,
			],
		)
	t.check(
		absf(travelled["up"] / maxf(travelled["right"], 0.001) - 1.0 / 0.57735) < 0.09,
		"at yaw %d up pans 1.732 times the ground of right (%.0f and %.0f px)" % [
			yaw,
			travelled["up"],
			travelled["right"],
		],
	)


## The mouse against the top edge pans the ground that shows as up.
func _pan_by_edge(t: TestContext, yaw: float) -> void:
	var home := await _settle(t)
	var event := InputEventMouseMotion.new()
	event.position = Vector2(float(SIZE.x) * 0.5, 2.0)
	_camera.call("_input", event)
	await t.seconds(PAN)
	_camera.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	var moved := _camera.global_position - home
	t.check(
		moved.length() > 20.0 and moved.normalized().distance_to(_ground_up(yaw)) < 0.05,
		"at yaw %d the top edge pans the ground along %s (moved %s)" % [
			yaw,
			_ground_up(yaw),
			moved,
		],
	)


## Following a target with the mouse at the right of the screen: the focus leads along the ground
## that shows as right, not along world +x.
func _lead_toward_the_mouse(t: TestContext, yaw: float) -> void:
	_camera.frame([])
	_camera.set("_player", _a)
	Pointer.inject(Vector2(float(SIZE.x) - 4.0, float(SIZE.y) * 0.5))
	await t.seconds(3.0)
	var lead := _camera.global_position - _a.global_position
	Pointer.release()
	t.check(
		lead.length() > 40.0 and lead.normalized().distance_to(_ground_right(yaw)) < 0.05,
		"at yaw %d the focus leads along the ground that shows as right (%s)" % [yaw, lead],
	)


## The spectator's framing zooms to the combatants' extent on the screen at yaw 45, where two
## combatants on the ground diagonal stand one above the other: the fit is the screen height over
## (0.8165 * apart + 2 margins), not the world box's.
func _framing_fits_the_screen_extent(t: TestContext) -> void:
	_rig.yaw = 45.0
	_b.global_position = _a.global_position + Vector2(APART, APART)
	_camera.frame([_a, _b])
	await t.seconds(4.0)
	var want := float(SIZE.y) / (0.8165 * APART + 2.0 * MARGIN)
	t.check(
		absf(_camera.zoom.x - want) < 0.03,
		"the framing zoom fits the screen extent at yaw 45 (%.3f, worked %.3f)" % [
			_camera.zoom.x,
			want,
		],
	)
	var middle := (_a.global_position + _b.global_position) * 0.5
	t.check(
		_camera.global_position.distance_to(middle) < 5.0,
		"and centres on them (%s, %s)" % [_camera.global_position, middle],
	)
