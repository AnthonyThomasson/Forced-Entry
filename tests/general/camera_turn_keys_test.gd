extends GameTest
## The camera turns on two held, rebindable actions (ticket #193, rule 4): Q turns it one way and E
## the other. Both are on the settings page with a label and a group and clash with nothing, and
## `Keybinds.get_camera_turn()` reads them as -1 (Q), +1 (E) or 0 (neither, or both). The Use action
## they free E from is gone.


func describe() -> Dictionary:
	return {
		"name": "Camera turn keys: Q and E, held and rebindable",
		"description": "camera_turn_left / camera_turn_right default to Q and E, are listed on the "
			+ "settings page, clash with nothing, and get_camera_turn() reads -1 / 0 / +1; the "
			+ "old Use action no longer exists.",
		"tags": ["keybinds", "camera", "input"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	Keybinds.bindings.reset_all()
	var actions := ["camera_turn_left", "camera_turn_right"]
	for action: String in actions:
		t.check(InputMap.has_action(action), "%s is registered" % action)
		t.check(
			Keybinds.LABELS.has(action) and Keybinds.GROUPS.has(action),
			"%s has a settings-page label and group" % action,
		)
		t.check(
			Settings.binding_rows().any(func(r): return r["action"] == action),
			"the settings page lists %s" % action,
		)
		t.check(
			Keybinds.bindings.conflicts_of(action).is_empty(),
			"%s clashes with nothing (%s)" % [action, Keybinds.bindings.conflicts_of(action)],
		)
	t.check(_key(KEY_Q).is_action("camera_turn_left"), "Q turns the camera left")
	t.check(_key(KEY_E).is_action("camera_turn_right"), "E turns the camera right")
	t.check(not InputMap.has_action("use"), "the Use action is gone")
	t.check(not Keybinds.has_method("is_use_just_pressed"), "and so are its readers")

	t.expect_eq(Keybinds.get_camera_turn(), 0.0, "no key held: no turn")
	Input.action_press("camera_turn_left")
	t.expect_eq(Keybinds.get_camera_turn(), -1.0, "Q held: -1")
	Input.action_press("camera_turn_right")
	t.expect_eq(Keybinds.get_camera_turn(), 0.0, "both held: they cancel")
	Input.action_release("camera_turn_left")
	t.expect_eq(Keybinds.get_camera_turn(), 1.0, "E held: +1")
	Input.action_release("camera_turn_right")
	t.expect_eq(Keybinds.get_camera_turn(), 0.0, "released: no turn")

	Keybinds.bindings.bind("camera_turn_left", _key(KEY_Z))
	Input.action_press("camera_turn_left")
	t.expect_eq(Keybinds.get_camera_turn(), -1.0, "a rebound turn key still reads -1")
	Input.action_release("camera_turn_left")
	t.check(_key(KEY_Z).is_action("camera_turn_left"), "it is on Z now")
	Keybinds.bindings.reset_all()


## A key event at the physical position `code`.
func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event
