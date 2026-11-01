extends GameTest
## The test result banner sits over the world a test plays in, so a click on the banner's text or
## padding falls through to that world (a test clicking a doorway framed under the banner reaches
## it); only its buttons stop the mouse. Real mouse events on a banner showing a verdict.

const Banner := preload("res://scenes/ui/testing/test_result_hud.gd")
const InspectorProbe := preload("res://tests/_ui/inspector_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Test result banner lets clicks through to the world except on its buttons",
		"description": "A right-click on the banner's status, checks or padding reaches the "
			+ "world's unhandled input; a click on its Pause button presses it and stays there.",
		"tags": ["test browser", "ui"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	var root_window := t.world.get_window()
	var window_size := root_window.size
	root_window.size = Vector2i(1280, 720)  # the headless viewport is too small to lay it out
	t.world.tree_exiting.connect(func() -> void: root_window.size = window_size)
	var catcher := Catcher.new()
	t.world.add_child(catcher)
	var banner := Banner.new()
	t.world.add_child(banner)
	var paused: Array = [0]
	banner.pause_requested.connect(func() -> void: paused[0] += 1)
	banner.show_result({
		"status": "FAIL", "time": 0.5,
		"checks": [{ "message": "the right-click opens the menu", "ok": false }],
	})
	await t.frames(4)

	var panel := banner.get_child(0) as Control
	var spots := {
		"its status": banner._status.get_global_rect().get_center(),
		"its checks": banner._details.get_global_rect().get_center(),
		"its padding": panel.get_global_rect().position + Vector2(4, 4),
	}
	for what: String in spots:
		var at: Vector2 = spots[what]
		catcher.presses.clear()
		await InspectorProbe.click_screen(t, at, MOUSE_BUTTON_RIGHT)
		t.check(
			catcher.presses.size() == 1,
			"a right-click on %s at %s reaches the world (%d presses)" % [
				what, str(at), catcher.presses.size(),
			],
		)

	catcher.presses.clear()
	await InspectorProbe.click_screen(
		t,
		banner._pause.get_global_rect().get_center(),
		MOUSE_BUTTON_LEFT,
	)
	t.expect_eq(paused[0], 1, "a click on the Pause button presses it")
	t.check(catcher.presses.is_empty(), "a click on the Pause button stays out of the world")


## Stands in for the world under the banner: the presses that reach unhandled input.
class Catcher:
	extends Node

	var presses: Array = []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			presses.append(event.position)
