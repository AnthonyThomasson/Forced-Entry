extends RefCounted
## Shared helpers for the UI inspector and overlay-scope tests (not a test itself):
## `const InspectorProbe := preload("res://tests/_ui/inspector_probe.gd")`. Real mouse input (a
## click at a world point's place on screen or at a screen point, wheel notches), and the read-outs
## of which actors of the four-NPC scope worlds (`SIDES`) show an overlay property. Only the
## published surface of the overlays is read: their `show_<x>` properties, found by name on the
## actor's children.

## The four NPCs of the scope tests and the side each is on, in the order every read-out lists them.
const SIDES := {
	&"d1": &"defender", &"d2": &"defender", &"i1": &"invader", &"i2": &"invader",
}


## A click (press and release) of `button` at world point `at`'s place on screen.
static func click(t: TestContext, at: Vector2, button: MouseButton) -> void:
	await click_screen(t, Pointer.screen_of(t.world, at), button)


## A right-click at world point `at`'s place on screen.
static func right_click(t: TestContext, at: Vector2) -> void:
	await click(t, at, MOUSE_BUTTON_RIGHT)


## A click (press and release) of `button` at screen point `screen`, a motion there first.
static func click_screen(t: TestContext, screen: Vector2, button: MouseButton) -> void:
	await _move_to(t, screen)
	for pressed: bool in [true, false]:
		await _button(t, screen, button, pressed)
	await t.frames(1)


## `count` wheel notches of `button` (`MOUSE_BUTTON_WHEEL_UP` / `_DOWN`) with the pointer at screen
## point `screen`.
static func wheel(t: TestContext, screen: Vector2, button: MouseButton, count: int) -> void:
	await _move_to(t, screen)
	for i in count:
		await _button(t, screen, button, true)
	await t.frames(2)


## The ids of the `SIDES` actors with an overlay whose property `prop` is on, in `SIDES` order.
static func lit(t: TestContext, prop: String) -> Array:
	var out: Array = []
	for id: StringName in SIDES:
		for overlay in overlays_with(t.actor(id), prop):
			if bool(overlay.get(prop)):
				out.append(String(id))
	return out


## Every child of `character` that has the property `prop`.
static func overlays_with(character: Node, prop: String) -> Array:
	return character.get_children().filter(func(c): return prop in c)


## The body label under the section heading `heading` (shown upper-cased, `"POINT"`) of the detail
## `card`, or null.
static func section(card: Control, heading: String) -> Label:
	var labels := card.find_children("*", "Label", true, false)
	for i in labels.size() - 1:
		if (labels[i] as Label).text == heading:
			return labels[i + 1] as Label
	return null


static func _move_to(t: TestContext, screen: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	TestContext.inject(motion)
	await t.frames(1)


static func _button(
		t: TestContext, screen: Vector2, button: MouseButton, pressed: bool,
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = screen
	event.global_position = screen
	TestContext.inject(event)
	await t.frames(1)
