extends GameTest
## Screen-relative controls (#193 rule 5): in the 3D render mode WASD moves the human relative to
## the screen, so W goes up the screen at any camera yaw; a driver seated in a vehicle keeps raw
## keys (W throttle, A / D steer: G7), never turned by the camera. Judged by where the player shows
## on the screen (through `Pointer.screen_of`, the camera's own view) and by the car's own front,
## not by the rotation the controller applies. With no rig (the 2D render) W is up the world.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")
const RigProbe := preload("res://tests/_general/rig_probe.gd")
const YAW := 90.0
## Held long enough to cross well over 20 px of screen at walking pace.
const WALK := 0.5

var _camera: Camera2D


func describe() -> Dictionary:
	return {
		"name": "WASD is screen-relative in 3D; a seated driver's keys stay raw",
		"description": "At yaw 90 the human's W goes up the screen and D right, whatever the "
			+ "world axes; in 2D W is up the world; a driver seated in a car still drives with "
			+ "W as throttle, along the car's front, at that yaw.",
		"tags": ["camera", "3d", "input", "player", "vehicle"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])
	s.arena(Rect2(0, 0, 4000, 1600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(2600, 800))
	s.actor(&"you", &"player", Vector2(1000, 800))


func run(t: TestContext) -> void:
	_camera = Camera2D.new()
	_camera.position = Vector2(1000, 800)
	t.world.add_child(_camera)
	_camera.make_current()
	await t.frames(3)
	var you := t.actor(&"you")
	await _two_d_w_is_up_the_world(t, you)
	var rig := RigProbe.open(t.world, _camera, YAW)
	await t.frames(3)
	await _walks_by_the_screen(t, you)
	await _driver_keeps_raw_keys(t, you)
	rig.queue_free()


## No rig: a world with no turned camera, W is -y in the world (up the screen).
func _two_d_w_is_up_the_world(t: TestContext, you: Node2D) -> void:
	var start := you.global_position
	Input.action_press(Keybinds.MOVE_UP)
	await t.seconds(WALK)
	Input.action_release(Keybinds.MOVE_UP)
	await t.frames(3)
	var moved := you.global_position - start
	t.check(moved.y < -20.0 and absf(moved.x) < 2.0, "in 2D W moves up the world (%s)" % moved)
	you.global_position = start
	await t.frames(3)


## Yaw 90: W must move the player up the screen (screen y falls, screen x holds) and D to the right.
func _walks_by_the_screen(t: TestContext, you: Node2D) -> void:
	for step: Dictionary in [
		{ "key": Keybinds.MOVE_UP, "name": "W", "dir": Vector2.UP },
		{ "key": Keybinds.MOVE_DOWN, "name": "S", "dir": Vector2.DOWN },
		{ "key": Keybinds.MOVE_RIGHT, "name": "D", "dir": Vector2.RIGHT },
		{ "key": Keybinds.MOVE_LEFT, "name": "A", "dir": Vector2.LEFT },
	]:
		_camera.global_position = Vector2(1000, 800)
		you.global_position = Vector2(1000, 800)
		await t.frames(4)
		var before := Pointer.screen_of(you, you.global_position)
		Input.action_press(step["key"])
		await t.seconds(WALK)
		Input.action_release(step["key"])
		await t.frames(3)
		var shown := Pointer.screen_of(you, you.global_position) - before
		var want: Vector2 = step["dir"]
		t.check(
			shown.length() > 20.0 and shown.normalized().distance_to(want) < 0.05,
			"at yaw 90 %s moves the player %s on the screen (moved %s)" % [
				step["name"],
				want,
				shown,
			],
		)


## Seated driver at yaw 90: W is throttle along the car's front, not rotated into the screen's up.
func _driver_keeps_raw_keys(t: TestContext, you: Node2D) -> void:
	if not Probe.ready(t, &"car", [&"you"]):
		return
	var car := t.vehicle(&"car") as Node2D
	you.global_position = VehicleFrame.stand_point(car, &"front_left")
	_camera.global_position = car.global_position
	await t.seconds(0.4)
	Input.action_press(Keybinds.INTERACT)
	await t.frames(2)
	Input.action_release(Keybinds.INTERACT)
	if not t.require(
		await t.until(func(): return you.use.is_in_vehicle(), 6.0), "the player gets in the car"
	):
		return
	await t.seconds(0.5)
	var start := car.global_position
	var front := VehicleFrame.forward(car)
	Input.action_press(Keybinds.MOVE_UP)
	await t.seconds(1.5)
	Input.action_release(Keybinds.MOVE_UP)
	var moved := car.global_position - start
	t.check(
		moved.dot(front) > 30.0,
		"W is throttle along the car's front, at yaw 90 (%.0f px along it)" % moved.dot(front),
	)
	t.check(
		absf(moved.dot(VehicleFrame.right(car))) < 0.2 * maxf(moved.dot(front), 1.0),
		"and straight, not turned by the camera (%.0f px sideways)" % moved.dot(
			VehicleFrame.right(car)
		),
	)
