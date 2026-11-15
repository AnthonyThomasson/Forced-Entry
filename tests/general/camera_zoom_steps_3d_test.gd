extends GameTest
## In the 3D render mode the zoom is one of the whole steps of `Zoom3dConfig.steps` (#193
## phase 2b G15, 0.5, 1, 2 and 3), so a picture pixel is a whole number of screen pixels and one art
## pixel at 1x: a following camera starts at 1x, each wheel notch (and each whole notch of a
## trackpad's scroll) is one step, held within the steps there are, and the spectator's framing
## takes the largest step not over the fit (so everyone stays in view). In 2D the zoom is still
## continuous (`camera_wheel_zoom_test.gd`).

const CameraController = preload("res://scenes/general/camera_controller.gd")
const RigProbe = preload("res://tests/_general/rig_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "In 3D the zoom snaps to whole steps",
		"description": "A following 3D camera starts at 1x and the wheel steps it 2x, 3x (and "
			+ "stops), "
			+ "then back down through 1x to 0.5x; a trackpad's fractions gather into one step; the "
			+ "framing takes the whole step under the fit.",
		"tags": ["camera", "zoom", "input", "3d", "render"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])
	s.arena(Rect2(0, 0, 1600, 900))
	s.actor(&"a", &"puppet", Vector2(700, 450))
	s.actor(&"b", &"puppet", Vector2(1100, 450))
	s.set_static(CameraConfig, &"frame_margin", 100.0)


func run(t: TestContext) -> void:
	var cam := Camera2D.new()
	cam.set_script(CameraController)
	cam.target_path = ^".."  # follow the world root
	t.world.add_child(cam)
	cam.make_current()
	RigProbe.open(t.world, cam, 0.0)
	await t.seconds(0.4)
	t.expect_eq(cam.zoom.x, 1.0, "a following 3D camera starts at 1x")

	for expected: float in [2.0, 3.0, 3.0]:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
		await t.frames(3)
		t.expect_eq(
			cam.zoom.x,
			expected,
			"a wheel notch up steps to %s (and stops at 3)" % expected,
		)
	for expected: float in [2.0, 1.0, 0.5, 0.5]:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
		await t.frames(3)
		t.expect_eq(cam.zoom.x, expected, "a wheel notch down steps to %s" % expected)
	for expected: float in [1.0, 2.0]:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
		await t.frames(3)
		t.expect_eq(cam.zoom.x, expected, "a notch up from the bottom steps to %s" % expected)

	# a trackpad's scroll up of 20 units is 0.6 of a notch at 0.03 a unit: no step yet, then a step
	_scroll(cam, -20.0)
	await t.frames(3)
	t.expect_eq(cam.zoom.x, 2.0, "0.6 of a notch is no step")
	_scroll(cam, -20.0)
	await t.frames(3)
	t.expect_eq(cam.zoom.x, 3.0, "1.2 notches gathered is a step")

	await _framing_takes_the_step_under_the_fit(t, cam)


## Two combatants 400 px apart plus a 100 px margin each side, 600 px, on a 64 px square test
## viewport fit at 0.107: under the smallest step, so 0.5; spread over a window the fit is the
## window over 600.
func _framing_takes_the_step_under_the_fit(t: TestContext, cam: Camera2D) -> void:
	cam.set("_steps", ZoomSteps.new())  # the wheel's steps so far are forgotten
	cam.frame([t.actor(&"a"), t.actor(&"b")])
	await t.seconds(1.0)
	var size := cam.get_viewport_rect().size
	var fit := minf(size.x / 600.0, size.y / 600.0)
	var steps := Zoom3dConfig.steps
	var want := steps[0]
	for step: float in steps:
		if step <= fit * 1.001:
			want = step
	t.expect_eq(
		cam.zoom.x,
		want,
		"the framing zoom is the largest step not over the fit %.2f" % fit,
	)
	t.check(
		steps.has(cam.zoom.x) and (cam.zoom.x <= fit * 1.001 or cam.zoom.x == steps[0]),
		"and it never shows less than the fit unless it is the smallest step",
	)


## A two-finger trackpad scroll of `amount` (negative = up), handed to the camera as one event (the
## input singleton may also turn a pan gesture into wheel notches, which would be two scrolls).
func _scroll(cam: Camera2D, amount: float) -> void:
	var event := InputEventPanGesture.new()
	event.delta = Vector2(0.0, amount)
	cam.call("_unhandled_input", event)


## One wheel notch, as the OS delivers it.
func _wheel(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	TestContext.inject(event)
