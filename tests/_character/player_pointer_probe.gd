extends RefCounted
## Shared helper for the tests that drive a `player` actor's aim and scroll (not a test itself):
## `const Pointer := preload("res://tests/_character/player_pointer_probe.gd")`. A player's aim is
## the mouse, so a test puts the mouse where a world point is on the screen. The test camera is
## still easing toward its framing and its zoom carries that point with it, so `aim` puts it there
## again each frame until the aim is on it. An injected wheel or pan event carries a position of its
## own (default (0, 0)) and so moves the mouse and the aim: `at` gives one the pointer's place.


## Turn the player `you` toward the world point `toward`: the mouse is put on the screen point it is
## at until the aim is within 3 px of it. Returns that screen point (what `at` places events on);
## the test fails if the aim never gets there.
static func aim(t: TestContext, you: Node, toward: Vector2) -> Vector2:
	var pointer := Vector2.ZERO
	for i in 120:
		var motion := InputEventMouseMotion.new()
		motion.position = you.get_viewport().get_canvas_transform() * toward
		motion.global_position = motion.position
		pointer = motion.position
		TestContext.inject(motion)
		await t.frames(1)
		if you.movement.aim_point.distance_to(toward) < 3.0:
			return pointer
	t.check(false, "the player aims at %s (aims at %s)" % [toward, you.movement.aim_point])
	return pointer


## Put the wheel or pan event `event` at the screen point `pointer` (from `aim`).
static func at(event: InputEvent, pointer: Vector2) -> void:
	event.position = pointer
	if event is InputEventMouse:
		event.global_position = pointer
