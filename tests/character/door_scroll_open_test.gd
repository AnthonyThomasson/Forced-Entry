extends GameTest
## DR7 (ticket #21): with Use (E) held on a door, each wheel notch turns the door by the brief's 20
## degrees, wheel up opening and down closing, between shut and fully open, and it stays where the
## scroll leaves it; the camera does not zoom meanwhile, and letting go of E after scrolling does
## not toggle the door. A trackpad's two-finger scroll turns it too, by the notches the camera
## counts it as. With E not held, or held with no door in reach, the wheel zooms as before.

## Degrees one wheel notch turns a door (the brief's number).
const NOTCH := 20.0
const CameraController = preload("res://scenes/general/camera_controller.gd")
const Pointer := preload("res://tests/_character/player_pointer_probe.gd")
## A trackpad scroll of this much (up), as the OS delivers it.
const PAN := -30.0
## Beside the shut door, aimed at it, and well away from it.
const BY_THE_DOOR := Vector2(370, 150)
const AT_THE_DOOR := Vector2(440, 150)
const FAR := Vector2(150, 400)
## Between the two doors, 31 px from each leaf: both in reach, the aim picks.
const BETWEEN := Vector2(370, 180)
const AT_THE_OTHER := Vector2(440, 230)
## The puppet beside the second door, a long way from the player: near enough the hinge to reach the
## leaf (48 px) still when three notches have turned it 60 degrees.
const PUPPET_SPOT := Vector2(390, 225)
## A zoom that has not moved, to this much.
const SAME_ZOOM := 0.001

## Where the mouse is on the screen, as `Pointer.aim` last put it.
var _pointer := Vector2.ZERO


func describe() -> Dictionary:
	return {
		"name": "Held Use and the wheel open a door by steps",
		"description": "E held on a door: wheel notches turn it 20 degrees each (up opens, down "
			+ "closes), the camera does not zoom, releasing leaves the angle; a trackpad scroll "
			+ "turns it too; with E not held, or no door in reach, the wheel zooms.",
		"tags": ["door", "player", "input", "camera", "keybinds"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])  # a person's wheel would change what is measured
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 800) },
	], [{
		"pos": Vector2(400, 150), "width": 52.0,
		"door": {
			"name": "d", "material": "hollow", "style": "flush",
			"hinge": Vector2(400, 130), "swing_into": Vector2.RIGHT,
		},
	}, {
		"pos": Vector2(400, 210), "width": 52.0,
		"door": {
			"name": "b", "material": "hollow", "style": "flush",
			"hinge": Vector2(400, 190), "swing_into": Vector2.RIGHT,
		},
	}])
	s.von_down()
	s.actor(&"you", &"player", BY_THE_DOOR)
	s.actor(&"hand", &"puppet", PUPPET_SPOT)


func run(t: TestContext) -> void:
	var you := t.actor(&"you")
	var door := t.object(&"d")
	var other := t.object(&"b")
	var camera := _own_camera(t, you)
	if not t.require(door != null and other != null, "the two doors are there"):
		return
	_pointer = await Pointer.aim(t, you, AT_THE_DOOR)
	await _camera_rests(t, camera)  # it settles on its framing
	var scroll_notches := await _notches_of_a_scroll(t, camera)
	_pointer = await Pointer.aim(t, you, AT_THE_DOOR)
	var zoom := camera.zoom.x
	await _wheel_steps(t, door, camera, zoom)
	await _trackpad_steps(t, door, camera, zoom, scroll_notches)
	await _limits_and_release(t, door, camera, zoom)
	await _zooms_when_the_door_does_not_take_it(t, you, door, camera)
	await _the_door_held_is_the_door_turned(t, you, door, other)
	await _the_puppet_works_a_door(t, t.puppet(&"hand"), other)


## E held: notches turn the door 20 degrees each, the camera stays, and letting go leaves it.
func _wheel_steps(t: TestContext, door: Node, camera: Camera2D, zoom: float) -> void:
	Input.action_press(Keybinds.USE)
	await t.frames(2)
	for i in 3:
		await _wheel(t, MOUSE_BUTTON_WHEEL_UP)
	await _settle(t)
	t.expect_near(door.angle(), 3.0 * NOTCH, 0.1, "three notches up turn the door 60 degrees")
	await _wheel(t, MOUSE_BUTTON_WHEEL_DOWN)
	await _settle(t)
	t.expect_near(door.angle(), 2.0 * NOTCH, 0.1, "a notch down turns it back to 40 degrees")
	t.expect_near(camera.zoom.x, zoom, SAME_ZOOM, "the camera did not zoom meanwhile")
	Input.action_release(Keybinds.USE)
	await _settle(t)
	t.expect_near(door.angle(), 2.0 * NOTCH, 0.1, "letting go of E leaves the door where it is")


## E not held: how many notches the camera counts a trackpad scroll of `PAN` for, read off its zoom
## (a notch scales it by `CameraConfig.zoom_step`); it comes out a few notches (false: the
## scroll did nothing, and the door's share is then judged against none).
func _notches_of_a_scroll(t: TestContext, camera: Camera2D) -> float:
	var before := camera.zoom.x
	_scroll(PAN)
	await _zoom_settles(t, camera, before)
	var notches := log(camera.zoom.x / before) / log(CameraConfig.zoom_step)
	t.check(notches > 1.0, "a trackpad scroll up zooms the camera in (%.2f notches)" % notches)
	return notches


## E held again: a trackpad scroll turns the door by the notches the camera counts it for, and back.
func _trackpad_steps(
	t: TestContext, door: Node, camera: Camera2D, zoom: float, scroll_notches: float
) -> void:
	Input.action_press(Keybinds.USE)
	await t.frames(2)
	_scroll(PAN)
	await _settle(t)
	t.expect_near(
		door.angle(),
		2.0 * NOTCH + scroll_notches * NOTCH,
		0.5,
		"a trackpad scroll opens it by the notches the camera counts it for",
	)
	_scroll(-PAN)
	await _settle(t)
	t.expect_near(door.angle(), 2.0 * NOTCH, 0.5, "the scroll back shuts it by as many")
	t.expect_near(camera.zoom.x, zoom, SAME_ZOOM, "the camera did not zoom for the trackpad")


## Still held: the door stops at fully open and at shut, and letting go after scrolling does not
## toggle it.
func _limits_and_release(t: TestContext, door: Node, camera: Camera2D, zoom: float) -> void:
	for i in 2:
		await _wheel(t, MOUSE_BUTTON_WHEEL_UP)
	await _settle(t)
	t.expect_near(door.angle(), 80.0, 0.1, "two notches more take it to 80 degrees")
	await _wheel(t, MOUSE_BUTTON_WHEEL_UP)
	await _settle(t)
	t.expect_near(door.angle(), 90.0, 0.1, "the notch that would pass it stops at fully open")
	for i in 12:
		await _wheel(t, MOUSE_BUTTON_WHEEL_UP)
	await _settle(t)
	t.expect_near(door.angle(), 90.0, 0.1, "it stops at fully open")
	for i in 12:
		await _wheel(t, MOUSE_BUTTON_WHEEL_DOWN)
	await _settle(t)
	t.expect_near(door.angle(), 0.0, 0.1, "and at shut")
	Input.action_release(Keybinds.USE)
	await _settle(t)
	t.expect_near(door.angle(), 0.0, 0.1, "letting go after scrolling does not toggle it")
	t.expect_near(camera.zoom.x, zoom, SAME_ZOOM, "the camera stayed put through all of it")


## E not held, and E held with no door in reach: the wheel zooms as before, the door stays.
func _zooms_when_the_door_does_not_take_it(
	t: TestContext, you: Node, door: Node, camera: Camera2D
) -> void:
	var zoom := camera.zoom.x
	await _wheel(t, MOUSE_BUTTON_WHEEL_UP)
	await _wheel(t, MOUSE_BUTTON_WHEEL_UP)
	await _zoom_settles(t, camera, zoom)
	t.check(camera.zoom.x > zoom * 1.15, "with E not held the wheel zooms the camera")
	t.expect_near(door.angle(), 0.0, 0.1, "and the door does not move")
	you.global_position = FAR
	await t.frames(3)
	zoom = camera.zoom.x
	Input.action_press(Keybinds.USE)
	await t.frames(2)
	await _wheel(t, MOUSE_BUTTON_WHEEL_UP)
	await _wheel(t, MOUSE_BUTTON_WHEEL_UP)
	await _zoom_settles(t, camera, zoom)
	Input.action_release(Keybinds.USE)
	t.check(camera.zoom.x > zoom * 1.15, "with E held and no door in reach the wheel zooms")
	t.expect_near(door.angle(), 0.0, 0.1, "and the door does not move")


## Between two doors, E pressed aimed at the first and the aim then moved to the second: the wheel
## and the release turn the door E went down on, not the one the aim is nearest now.
func _the_door_held_is_the_door_turned(
	t: TestContext, you: Node, door: Node, other: Node
) -> void:
	you.global_position = BETWEEN
	_pointer = await Pointer.aim(t, you, Vector2(440, 150))
	Input.action_press(Keybinds.USE)
	await t.frames(2)
	_pointer = await Pointer.aim(t, you, AT_THE_OTHER)
	t.check(you.use.doors.door_in_reach() == other, "the aim is nearest the second door now")
	await _wheel(t, MOUSE_BUTTON_WHEEL_UP)
	await _wheel(t, MOUSE_BUTTON_WHEEL_UP)
	await _settle(t)
	t.expect_near(door.angle(), 2.0 * NOTCH, 0.1, "the wheel turned the door E went down on")
	t.expect_near(other.angle(), 0.0, 0.1, "and not the one the aim is on")
	Input.action_release(Keybinds.USE)
	await _settle(t)
	t.expect_near(door.angle(), 2.0 * NOTCH, 0.1, "its release after scrolling toggles neither")
	t.expect_near(other.angle(), 0.0, 0.1, "the other stays shut")


## The puppet's `turn_door` is the wheel with E held and its `use` a tap (it ends with the door
## open), on the door it is aimed at.
func _the_puppet_works_a_door(t: TestContext, puppet: Node, other: Node) -> void:
	puppet.aim_at(Vector2(440, 210))
	await t.frames(3)
	puppet.turn_door(3.0)
	await _settle(t)
	t.expect_near(other.angle(), 3.0 * NOTCH, 0.1, "the puppet's turn_door turns the door 60")
	puppet.use()
	await _settle(t)
	t.expect_near(other.angle(), 90.0, 0.1, "its use swings the ajar door fully open")


## A camera of the test's own following the player: it starts at no wheel zoom, where the suite's
## camera, shared by every test of the process and by this one's repeats, keeps the zoom the last
## test left it at (and may be at its limit).
func _own_camera(t: TestContext, you: Node) -> Camera2D:
	var camera := Camera2D.new()
	camera.set_script(CameraController)
	camera.target_path = NodePath("../" + str(t.world.get_path_to(you)))
	t.world.add_child(camera)
	camera.make_current()
	return camera


## Wait for the camera's zoom to move off `before` and then to come to rest: it eases a step a frame
## and a loaded machine paints fewer frames in a second of the test's time.
func _zoom_settles(t: TestContext, camera: Camera2D, before: float) -> void:
	await t.until(func(): return absf(camera.zoom.x - before) > 0.001, 5.0)
	var last := -1.0
	for i in 600:
		await t.frames(1)
		if absf(camera.zoom.x - last) < 0.00005:
			return
		last = camera.zoom.x


## Wait for the camera's zoom to hold still for a few frames (it has come to its framing).
func _camera_rests(t: TestContext, camera: Camera2D) -> void:
	var still := 0
	var last := -1.0
	for i in 900:
		await t.frames(1)
		still = still + 1 if absf(camera.zoom.x - last) < 0.00005 else 0
		last = camera.zoom.x
		if still >= 10:
			return


## Let a swing finish.
func _settle(t: TestContext) -> void:
	await t.seconds(DoorConfig.swing_time + 0.3)


## One wheel notch, as the OS delivers it (with the pointer where it is: an event's position moves
## the mouse), and a frame for it to land.
func _wheel(t: TestContext, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	Pointer.at(event, _pointer)
	TestContext.inject(event)
	await t.frames(1)


## A two-finger trackpad scroll of `amount` (negative = up), as the OS delivers it.
func _scroll(amount: float) -> void:
	var event := InputEventPanGesture.new()
	event.delta = Vector2(0.0, amount)
	Pointer.at(event, _pointer)
	TestContext.inject(event)
