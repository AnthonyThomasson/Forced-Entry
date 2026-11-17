extends GameTest
## The Space key gets in and out of a vehicle (tickets #54, #193): Use merged into Interact, so the
## one key, default Space and rebindable on the settings page, is read by the player's controller: a
## `player` actor beside the car's front-left door presses it and gets in to drive; pressing it
## again, seated, gets it out.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The Space key gets in and out of a vehicle",
		"description": "Interact defaults to Space, is listed on the settings page with no "
			+ "clash beyond Pause; the player pressing it beside the car boards into the "
			+ "driver's seat, and again gets out.",
		"tags": ["vehicle", "input", "player", "keybinds"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(450, 300))
	s.actor(&"you", &"player", Vector2(150, 80))


## Press the action for a couple of frames, then let go.
func _tap(t: TestContext, action: String) -> void:
	Input.action_press(action)
	await t.frames(2)
	Input.action_release(action)
	await t.frames(1)


func run(t: TestContext) -> void:
	var action := Keybinds.INTERACT
	t.check(InputMap.has_action(action), "the action is registered")
	var event := Keybinds.bindings.default_event(action) as InputEventKey
	t.check(event != null and event.physical_keycode == KEY_SPACE, "it defaults to Space")
	t.check(
		Keybinds.LABELS.has(action) and Keybinds.GROUPS.has(action),
		"it has a settings-page label and group",
	)
	t.check(
		Settings.binding_rows().any(func(r): return r["action"] == action),
		"the settings page lists it",
	)
	t.expect_eq(
		Keybinds.bindings.conflicts_of(action),
		[],
		"it clashes with no other action (Pause shares it on purpose)",
	)
	t.check(not InputMap.has_action("use"), "there is no separate Use key")

	if not Probe.ready(t, &"car", [&"you"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var you := t.actor(&"you")
	you.global_position = VehicleFrame.stand_point(car, &"front_left")
	await t.seconds(0.3)
	await _tap(t, action)
	if not t.require(
			await t.until(func(): return you.use.is_in_vehicle(), 6.0),
			"pressing Space beside the car gets the player in",
	):
		return
	t.expect_eq(Probe.seat_of(car, you), &"driver", "into the driver's seat")
	await t.seconds(0.5)
	await _tap(t, action)
	t.check(
		await t.until(func(): return you.use.vehicle() == null, 8.0),
		"pressing Space again gets it out",
	)
	t.check(not you.use.is_in_vehicle(), "it is on foot")
