extends GameTest
## The spectator detail card stays inside the window: with a populated Von brain section it is no
## taller than the viewport leaves it, its sections scroll inside it with the mouse wheel (the card
## swallows the wheel, so the camera does not zoom) and the Point section can be scrolled into view.
## Geometry only: the card's and its sections' global rects against the viewport's.

const Inspector := preload("res://scenes/ui/hud/spectator_inspector.gd")
const OverlayToggles := preload("res://scenes/ui/overlays/overlay_toggles.gd")
const OrderMenu := preload("res://tests/_ai/order_menu_probe.gd")
const InspectorProbe := preload("res://tests/_ui/inspector_probe.gd")
const AT := Vector2(450, 250)
## The window the project opens at (project.godot), the "default window size" of the brief.
const WINDOW := Vector2(1152, 648)
## A reasoning text as long as the zones' own, so the Point section is tall.
const LONG_DESC := "cover from the doorway, a clear line along the hall, the route passes the " \
	+ "kitchen door, ally lane to the left, held by the sergeant, exposed for two seconds"


func describe() -> Dictionary:
	return {
		"name": "The detail card fits the window and scrolls",
		"description": "At the default window size a defender's card with a populated Von brain "
			+ "and a clicked point ends inside the viewport, scrolls its sections under the "
			+ "mouse wheel without zooming the camera and brings the Point section into view; a "
			+ "right-click on it still reaches the ground below.",
		"tags": ["ui", "inspector", "spectator"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.von_script([])
	s.lock_interaction([&"camera", &"pause"])
	s.actor(&"npc", &"defender", AT, { "movement:speed": 0.0, "facing": Vector2.RIGHT })
	s.actor(
		&"intruder",
		&"puppet",
		AT + Vector2(250, 0),
		{ "faction": &"invader", "max_health": 1_000_000.0, "facing": Vector2.LEFT },
	)


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	OrderMenu.player_screen(t, true)  # the project's window, headless or not
	var inspector := CanvasLayer.new()
	inspector.set_script(Inspector)
	t.world.add_child(inspector)
	inspector.call("setup", [npc], { "show_brain": true }, OverlayToggles.RESERVED_WIDTH)
	await t.seconds(1.5)
	var card := inspector.get_node_or_null("DetailCard") as Control
	if not t.require(card != null, "the inspector builds a DetailCard"):
		return
	var viewport := t.world.get_viewport().get_visible_rect().size
	t.expect_eq(viewport, WINDOW, "premise: the test window is the project's default size")
	await InspectorProbe.right_click(t, npc.global_position)
	if not t.require(card.visible, "a right-click opens the card"):
		return
	var brain := _body(card, "VON BRAIN")
	if not t.require(
			await t.until(func(): return _lines(brain) >= 6, 8.0),
			"premise: the Von brain section is populated (%d lines)" % _lines(brain),
	):
		return
	card.call("set_point", { "category": &"fire", "label": "kitchen door", "desc": LONG_DESC })
	await t.frames(3)
	await _check_scrolling(t, card, viewport)
	inspector.queue_free()


## The open `card` ends inside `viewport`, its sections scroll under the wheel and the Point section
## comes into view, the camera left alone.
func _check_scrolling(t: TestContext, card: Control, viewport: Vector2) -> void:
	var rect := card.get_global_rect()
	t.check(
		rect.position.y >= 0.0 and rect.end.y <= viewport.y,
		"the card ends inside the viewport (%s of %s)" % [rect, viewport],
	)
	var scroll := _first(card, "ScrollContainer") as ScrollContainer
	if not t.require(scroll != null, "the card's sections sit in a scroll container"):
		return
	var point := _body(card, "POINT")
	var tall := (scroll.get_child(0) as Control).get_combined_minimum_size().y
	t.check(
		tall > scroll.size.y,
		"premise: the sections are taller than the card shows (%.0f of %.0f)" % [
			scroll.size.y,
			tall,
		],
	)
	t.check(not _inside(point, scroll), "the Point section starts out of view")

	var zoom := t.world.get_viewport().get_canvas_transform().get_scale()
	var at := card.get_global_rect().get_center()
	await InspectorProbe.wheel(t, at, MOUSE_BUTTON_WHEEL_DOWN, 60)
	t.check(_inside(point, scroll), "wheeling down over the card scrolls the Point into view")
	rect = card.get_global_rect()
	t.check(rect.end.y <= viewport.y, "the card still ends inside the viewport: %s" % rect)
	t.check(
		t.world.get_viewport().get_canvas_transform().get_scale().is_equal_approx(zoom),
		"the card swallowed the wheel: the camera did not zoom",
	)
	await InspectorProbe.wheel(t, at, MOUSE_BUTTON_WHEEL_UP, 60)
	t.check(not _inside(point, scroll), "wheeling up scrolls back")
	await InspectorProbe.click_screen(t, at, MOUSE_BUTTON_RIGHT)
	t.check(not card.visible, "a right-click on the card passes through: empty ground closes it")


## The body label under the heading `heading` of `card`.
func _body(card: Control, heading: String) -> Label:
	var labels := card.find_children("*", "Label", true, false)
	for i in labels.size() - 1:
		if (labels[i] as Label).text == heading:
			return labels[i + 1] as Label
	return null


func _lines(label: Label) -> int:
	return 0 if label == null else label.text.count("\n") + 1


func _first(node: Node, type: String) -> Node:
	var found := node.find_children("*", type, true, false)
	return null if found.is_empty() else found[0]


## Whether `control`'s rect lies inside `container`'s rect.
func _inside(control: Control, container: Control) -> bool:
	return container.get_global_rect().encloses(control.get_global_rect())
