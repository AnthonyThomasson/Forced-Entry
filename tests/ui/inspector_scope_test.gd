extends GameTest
## The overlay bar's "Show on" scope in a spectator match (`SpectatorInspector.set_scope`): two
## defenders and two invaders, the vision overlay toggled on. With nothing selected, the scope
## `defenders` shows the defenders' overlays and not the invaders'; `selected` shows none until an
## NPC is right-clicked and then only that NPC's; under `defenders` a right-clicked invader shows
## its overlays too, and drops them again when the selection is cleared. The clicks are real mouse
## input at a world point's place on screen (once the framing camera has settled).
##
## The brain overlay's labels (`brain_labels`) follow the selection, not the scope: on the selected
## NPC alone, under any scope, cleared on deselect and moved to another NPC selected. So does the
## brain overlay's drawing (`BrainDebug.drawn()`): with the brain toggle on, only the right-clicked
## NPC draws anything of it (bars, ring and labels), whatever the scope; nothing selected, none
## does.

const Inspector := preload("res://scenes/ui/hud/spectator_inspector.gd")
const OverlayToggles := preload("res://scenes/ui/overlays/overlay_toggles.gd")
const InspectorProbe := preload("res://tests/_ui/inspector_probe.gd")
const SIDES := InspectorProbe.SIDES
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
	inspector.call(
		"setup",
		npcs,
		{ "show_vision": true, "show_brain": true },
		OverlayToggles.RESERVED_WIDTH,
	)
	await t.seconds(1.5)  # the framing camera settles, so a point's place on screen holds still

	inspector.call("set_scope", "defenders")
	t.expect_eq(_lit(t), ["d1", "d2"], "scope defenders, nothing selected: the defenders show")
	t.expect_eq(_labelled(t), [], "nothing selected: no brain labels, though the defenders show")
	await t.frames(3)
	t.expect_eq(
		_brain_drawing(t),
		[],
		"nothing selected: no brain draws anything, though the defenders show",
	)

	await _check_selection(t, inspector)

	inspector.call("set_scope", "invaders")
	t.expect_eq(_lit(t), ["i1", "i2"], "scope invaders: the invaders show")
	inspector.call("set_flag", "show_vision", false)
	t.expect_eq(_lit(t), [], "a toggle turned off reaches the NPCs that show")
	inspector.call("set_flag", "show_vision", true)
	t.expect_eq(_lit(t), ["i1", "i2"], "and on again, only on the scope's NPCs")
	inspector.queue_free()


## Right-clicks under the scopes `selected` then `defenders`: who shows, who has brain labels and
## whose brain draws, as the selection moves and clears.
func _check_selection(t: TestContext, inspector: CanvasLayer) -> void:
	inspector.call("set_scope", "selected")
	t.expect_eq(_lit(t), [], "scope selected, nothing selected: none shows")
	await InspectorProbe.right_click(t, t.actor(&"i1").global_position)
	t.expect_eq(_lit(t), ["i1"], "a right-click then shows that NPC alone")
	t.expect_eq(_labelled(t), ["i1"], "and puts the brain labels on it")
	await _brain_drawn(t, &"i1")
	t.expect_eq(_brain_drawing(t), ["i1"], "and its brain draws, the others' draw nothing")

	inspector.call("set_scope", "defenders")
	t.expect_eq(_lit(t), ["d1", "d2", "i1"], "under defenders the selected invader shows too")
	t.expect_eq(_labelled(t), ["i1"], "the defenders shown by the scope have no brain labels")
	await t.frames(3)
	t.expect_eq(
		_brain_drawing(t),
		["i1"],
		"nor do their brains draw: under defenders only i1's does",
	)
	await InspectorProbe.right_click(t, t.actor(&"i2").global_position)
	t.expect_eq(_lit(t), ["d1", "d2", "i2"], "selecting another invader moves the extra one")
	t.expect_eq(_labelled(t), ["i2"], "and moves the brain labels to it")
	await _brain_drawn(t, &"i2")
	t.expect_eq(_brain_drawing(t), ["i2"], "and the brain drawing, i1's gone quiet")
	await InspectorProbe.right_click(t, GROUND)
	t.expect_eq(_lit(t), ["d1", "d2"], "and clearing the selection drops it")
	t.expect_eq(_labelled(t), [], "and the brain labels")
	await t.frames(3)
	t.expect_eq(_brain_drawing(t), [], "and every brain's drawing")


## The ids of the actors whose vision overlay is on, in the order of `SIDES`.
func _lit(t: TestContext) -> Array:
	return InspectorProbe.lit(t, "show_vision")


## The ids of the actors whose brain overlay has its labels on, in the order of `SIDES`.
func _labelled(t: TestContext) -> Array:
	return InspectorProbe.lit(t, "brain_labels")


## The ids of the actors whose brain overlay drew something in its last paint (`drawn()`), in the
## order of `SIDES`.
func _brain_drawing(t: TestContext) -> Array:
	var out: Array = []
	for id: StringName in SIDES:
		for child in t.actor(id).get_children():
			if (child.has_method("drawn")
					and "brain_labels" in child
					and not child.drawn().is_empty()):
				out.append(String(id))
	return out


## Wait until actor `id`'s brain overlay has drawn something.
func _brain_drawn(t: TestContext, id: StringName) -> void:
	await t.until(func(): return _brain_drawing(t).has(String(id)), 2.0, "%s's brain draws" % id)
