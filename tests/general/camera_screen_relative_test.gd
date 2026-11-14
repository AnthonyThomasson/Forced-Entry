extends GameTest
## The sim's camera works in screen terms in the 3D render mode (#193 rule 5): a spectator's pan
## keys and the mouse at a screen edge pan the framing camera up, down, left or right ON THE SCREEN
## at any camera yaw, and a following camera leads toward the mouse on the screen. Judged by where
## the camera's focus shows against where it was, through `Pointer.screen_of` (the 3D camera's own
## view), at yaw 90, where world +x is screen down and world +y is screen left. It runs in a
## window-sized `SubViewport` of its own (the test world's viewport is 64 px square).

const CameraController := preload("res://scenes/general/camera_controller.gd")
const RigProbe := preload("res://tests/_general/rig_probe.gd")
const YAW := 90.0
const PAN := 0.5
const SIZE := Vector2i(1152, 648)

var _screen: SubViewport
var _camera: Camera2D
var _a: Node2D
var _b: Node2D


func describe() -> Dictionary:
	return {
		"name": "The camera pans and leads by the screen in 3D",
		"description": "At yaw 90 the spectator's up key and the top screen edge pan the framing "
			+ "camera up the screen, the right key right, and a following camera leads to the "
			+ "right of the screen when the mouse is there.",
		"tags": ["camera", "3d", "pan", "input"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])
	s.arena(Rect2(0, 0, 3000, 2000), { "floor": "concrete" })


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
	RigProbe.open(_screen, _camera, YAW)
	await t.seconds(2.0)
	await _pan_by_keys(t)
	await _pan_by_edge(t)
	await _lead_toward_the_mouse(t)


func _combatant(at: Vector2) -> Node2D:
	var node := Node2D.new()
	node.position = at
	_screen.add_child(node)
	return node


## How the camera's focus has moved on the screen since `home` (a world point).
func _on_screen(home: Vector2) -> Vector2:
	return Pointer.screen_of(_camera, _camera.global_position) - Pointer.screen_of(_camera, home)


## Each pan key moves the focus the way it names on the screen, whatever the yaw.
func _pan_by_keys(t: TestContext) -> void:
	for step: Dictionary in [
		{ "key": Keybinds.CAMERA_UP, "name": "up", "dir": Vector2.UP },
		{ "key": Keybinds.CAMERA_RIGHT, "name": "right", "dir": Vector2.RIGHT },
	]:
		_camera.frame([_a, _b])  # back to the automatic framing
		await t.seconds(CameraConfig.manual_hold + 3.0)
		var home := _camera.global_position
		Input.action_press(step["key"])
		await t.seconds(PAN)
		Input.action_release(step["key"])
		var shown := _on_screen(home)
		var want: Vector2 = step["dir"]
		t.check(
			shown.length() > 20.0 and shown.normalized().distance_to(want) < 0.05,
			"at yaw 90 the %s key pans %s on the screen (moved %s)" % [step["name"], want, shown],
		)


## The mouse against the top edge pans the focus up the screen.
func _pan_by_edge(t: TestContext) -> void:
	_camera.frame([_a, _b])
	await t.seconds(CameraConfig.manual_hold + 3.0)
	var home := _camera.global_position
	var event := InputEventMouseMotion.new()
	event.position = Vector2(float(SIZE.x) * 0.5, 2.0)
	_camera.call("_input", event)
	await t.seconds(PAN)
	_camera.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	var shown := _on_screen(home)
	t.check(
		shown.length() > 20.0 and shown.normalized().distance_to(Vector2.UP) < 0.05,
		"the top edge pans up the screen (moved %s)" % shown,
	)


## Following a target with the mouse at the right of the screen: the focus leads to the right of
## the target on the screen, not along world +x (which is screen down at yaw 90).
func _lead_toward_the_mouse(t: TestContext) -> void:
	_camera.frame([])
	_camera.set("_player", _a)
	Pointer.inject(Vector2(float(SIZE.x) - 4.0, float(SIZE.y) * 0.5))
	await t.seconds(3.0)
	var lead := Pointer.screen_of(_camera, _camera.global_position) - Pointer.screen_of(
		_camera, _a.global_position
	)
	Pointer.release()
	t.check(
		lead.x > 40.0 and absf(lead.y) < 0.1 * lead.x,
		"the focus leads to the right on the screen, not down (%s)" % lead,
	)
