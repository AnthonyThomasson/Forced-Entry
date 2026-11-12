extends RefCounted
## Shared helper for the tests that drive a `player` actor's aim and scroll (not a test itself):
## `const PlayerPointer := preload("res://tests/_character/player_pointer_probe.gd")`. A player's
## aim is the pointer, so a test injects (`Pointer.inject`, interface 26) the screen point where a
## world point is shown: the real mouse is not warped, so a windowed run's own mouse cannot override
## it. The test camera is still easing toward its framing and its zoom carries that point with it,
## so `aim` injects it again each frame until the aim is on it. The injection holds until
## `TestWorld.restore` (or a `Pointer.release()`). An injected wheel or pan event carries a position
## of its own (default (0, 0)), which `at` sets to the pointer's place.

## How many frames in a row the aim is on its point, and the screen point holds still, before `aim`
## returns: the camera's ease can carry the point through the target once, and the aim then drifts
## off it as the test goes on.
const HELD_FRAMES := 5
## How far (px) the screen point may move between frames and still count as held still.
const STILL := 0.5
## How many frames `aim` waits for the aim to settle on its point.
const GIVE_UP := 600


## Turn the player `you` toward the world point `toward`: the pointer is injected on the screen
## point it is at, again each frame, until the aim has been within 3 px of it and the screen point
## has held still for `HELD_FRAMES` frames in a row (the camera has settled). Returns that screen
## point (what `at` places events on); the test fails if the aim never settles there.
static func aim(t: TestContext, you: Node, toward: Vector2) -> Vector2:
	var pointer := Vector2.ZERO
	var held := 0
	for i in GIVE_UP:
		var was := pointer
		pointer = Pointer.screen_of(you, toward)
		Pointer.inject(pointer)
		await t.frames(1)
		var on_it: bool = you.movement.aim_point.distance_to(toward) < 3.0
		var still := i > 0 and pointer.distance_to(was) < STILL
		held = held + 1 if on_it and still else 0
		if held >= HELD_FRAMES:
			return pointer
	t.check(false, "the player aims at %s (aims at %s)" % [toward, you.movement.aim_point])
	return pointer


## Put the wheel or pan event `event` at the screen point `pointer` (from `aim`).
static func at(event: InputEvent, pointer: Vector2) -> void:
	event.position = pointer
	if event is InputEventMouse:
		event.global_position = pointer
