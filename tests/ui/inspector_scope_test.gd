extends GameTest
## The overlay bar's "Show on" scope in a spectator match (`SpectatorInspector.set_scope`): two
## defenders and two invaders, the vision overlay toggled on. With nothing selected, the scope
## `defenders` shows the defenders' overlays and not the invaders'; `selected` shows none until an
## NPC is right-clicked and then only that NPC's; under `defenders` a right-clicked invader shows
## its overlays too, and drops them again when the selection is cleared. The clicks are real mouse
## input at a world point's place on screen (once the framing camera has settled).

const Inspector := preload("res://scenes/ui/hud/spectator_inspector.gd")
const OverlayToggles := preload("res://scenes/ui/overlays/overlay_toggles.gd")
const SIDES := {
	&"d1": &"defender", &"d2": &"defender", &"i1": &"invader", &"i2": &"invader",
}
## Empty ground, far from every NPC.
const GROUND := Vector2(150, 460)


func describe() -> Dictionary:
	return {
		"name": "The inspector shows overlays by scope and selection",
		"description": "Two defenders and two invaders with the vision overlay on: scope "
			+ "defenders shows the defenders' overlays, selected shows none until a right-click "
			+ "and then the clicked NPC's, and under defenders a right-clicked invader shows "
			+ "its overlays too.",
		"tags": ["ui", "inspector", "spectator", "overlay"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"ai.vision", false)
	s.von_down()
	s.lock_interaction([&"camera", &"pause"])
	for i in SIDES.size():
		var id: StringName = SIDES.keys()[i]
		s.actor(
			id,
			SIDES[id],
			Vector2(150 + 230 * i, 250),
			{ "movement:speed": 0.0, "max_health": 1_000_000.0 },
		)


func run(t: TestContext) -> void:
	var inspector := CanvasLayer.new()
	inspector.set_script(Inspector)
	t.world.add_child(inspector)
	var npcs: Array = SIDES.keys().map(func(id): return t.actor(id))
	inspector.call("setup", npcs, { "show_vision": true }, OverlayToggles.RESERVED_WIDTH)
	await t.seconds(1.5)  # the framing camera settles, so a point's place on screen holds still

	inspector.call("set_scope", "defenders")
	t.expect_eq(_lit(t), ["d1", "d2"], "scope defenders, nothing selected: the defenders show")

	inspector.call("set_scope", "selected")
	t.expect_eq(_lit(t), [], "scope selected, nothing selected: none shows")
	await _right_click(t, t.actor(&"i1").global_position)
	t.expect_eq(_lit(t), ["i1"], "a right-click then shows that NPC alone")

	inspector.call("set_scope", "defenders")
	t.expect_eq(_lit(t), ["d1", "d2", "i1"], "under defenders the selected invader shows too")
	await _right_click(t, t.actor(&"i2").global_position)
	t.expect_eq(_lit(t), ["d1", "d2", "i2"], "selecting another invader moves the extra one")
	await _right_click(t, GROUND)
	t.expect_eq(_lit(t), ["d1", "d2"], "and clearing the selection drops it")

	inspector.call("set_scope", "invaders")
	t.expect_eq(_lit(t), ["i1", "i2"], "scope invaders: the invaders show")
	inspector.call("set_flag", "show_vision", false)
	t.expect_eq(_lit(t), [], "a toggle turned off reaches the NPCs that show")
	inspector.call("set_flag", "show_vision", true)
	t.expect_eq(_lit(t), ["i1", "i2"], "and on again, only on the scope's NPCs")
	inspector.queue_free()


## The ids of the actors whose vision overlay is on, in the order of `SIDES`.
func _lit(t: TestContext) -> Array:
	var out: Array = []
	for id: StringName in SIDES:
		for child in t.actor(id).get_children():
			if "show_vision" in child and bool(child.get("show_vision")):
				out.append(String(id))
	return out


## A right-click (press and release) at world point `at`'s place on screen.
func _right_click(t: TestContext, at: Vector2) -> void:
	var screen := t.world.get_viewport().get_canvas_transform() * at
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	TestContext.inject(motion)
	await t.frames(1)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_RIGHT
		click.pressed = pressed
		click.position = screen
		click.global_position = screen
		TestContext.inject(click)
		await t.frames(1)
	await t.frames(1)
