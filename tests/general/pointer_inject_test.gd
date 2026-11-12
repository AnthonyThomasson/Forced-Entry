extends GameTest
## Pointer: `inject` stands a screen point in for the mouse wherever its position is polled, on a
## human-driven player's world: `screen_mouse` and `world_mouse` give the injected point (and the
## world point under it, by hand from the camera) while it is set, re-injecting moves it, the real
## mouse is not warped, and `release` (or `TestWorld.restore`) reads the real mouse again.

const TestWorldScript := preload("res://scenes/testing/test_world.gd")
## The camera's position and zoom: the screen's middle shows CAMERA_AT, a world pixel is ZOOM.
const CAMERA_AT := Vector2(300.0, 200.0)
const ZOOM := 2.0
## Where the real mouse is put (a motion event), and the two points injected over it.
const REAL := Vector2(200.0, 150.0)
const FIRST := Vector2(700.0, 400.0)
const SECOND := Vector2(90.0, 30.0)
## Where the real mouse moves meanwhile.
const MOVED := Vector2(230.0, 150.0)


func describe() -> Dictionary:
	return {
		"name": "Pointer injects a screen point for the mouse",
		"description": "A human-driven player's world: while a screen point is injected, "
			+ "screen_mouse and world_mouse give it, the real mouse is not warped, and release or "
			+ "TestWorld.restore read the real mouse again.",
		"tags": ["pointer", "player", "input"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])  # a person's wheel or camera keys would change what is measured
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"you", &"player", Vector2(300, 200))


func run(t: TestContext) -> void:
	var you := t.actor(&"you")
	var camera := Camera2D.new()
	camera.position = CAMERA_AT
	camera.zoom = Vector2(ZOOM, ZOOM)
	t.world.add_child(camera)
	camera.make_current()  # only the current camera moves the viewport's view
	await t.frames(3)

	_move_real_mouse(REAL)
	await t.frames(2)
	if not t.require(
		you.get_viewport().get_mouse_position().is_equal_approx(REAL),
		"the real mouse is where the test put it",
	):
		return
	_the_real_mouse_when_nothing_is_injected(t, you)
	await _an_injected_point_stands_in(t, you)
	_release_reads_the_real_mouse(t, you)
	_restore_releases(t, you)


## The world point under the pointer is worked out by hand: the screen's middle shows the camera's
## position, and a world pixel is ZOOM screen pixels.
func _world_under(you: Node, screen: Vector2) -> Vector2:
	return CAMERA_AT + (screen - you.get_viewport().get_visible_rect().size / 2.0) / ZOOM


func _the_real_mouse_when_nothing_is_injected(t: TestContext, you: Node) -> void:
	t.expect_eq(
		Pointer.screen_mouse(you),
		REAL,
		"with nothing injected the pointer is the real mouse",
	)
	t.expect_eq(
		Pointer.world_mouse(you), _world_under(you, REAL), "its world point is under it",
	)


## An injected point is the pointer, holds through frames, is replaced by the next inject, and
## moves the real mouse nowhere; a motion event does not move it either.
func _an_injected_point_stands_in(t: TestContext, you: Node) -> void:
	var viewport := you.get_viewport()
	Pointer.inject(FIRST)
	t.expect_eq(Pointer.screen_mouse(you), FIRST, "an injected point is the pointer")
	t.expect_eq(
		Pointer.world_mouse(you), _world_under(you, FIRST), "the world point is under it",
	)
	await t.frames(3)
	t.expect_eq(Pointer.screen_mouse(you), FIRST, "it holds through frames")
	t.expect_eq(viewport.get_mouse_position(), REAL, "the inject did not warp the real mouse")

	Pointer.inject(SECOND)
	t.expect_eq(
		Pointer.world_mouse(you), _world_under(you, SECOND), "injecting again moves the pointer",
	)
	t.expect_eq(viewport.get_mouse_position(), REAL, "the real mouse is still where it was")

	_move_real_mouse(MOVED)
	await t.frames(2)
	t.expect_eq(
		Pointer.screen_mouse(you),
		SECOND,
		"a motion event does not move an injected pointer",
	)


## After `release` the real mouse is read again, where it went meanwhile.
func _release_reads_the_real_mouse(t: TestContext, you: Node) -> void:
	Pointer.release()
	t.expect_eq(Pointer.screen_mouse(you), MOVED, "after release the real mouse is read again")
	t.expect_eq(Pointer.world_mouse(you), _world_under(you, MOVED), "and the world point under it")


## A harness restore releases an injected pointer, so no test leaks one into the next.
func _restore_releases(t: TestContext, you: Node) -> void:
	Pointer.inject(FIRST)
	var world := TestWorldScript.new()
	world.restore()
	world.free()
	t.expect_eq(Pointer.screen_mouse(you), MOVED, "TestWorld.restore releases an injected pointer")


## A mouse-motion event at `at`, as the OS delivers one.
func _move_real_mouse(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	TestContext.inject(motion)
