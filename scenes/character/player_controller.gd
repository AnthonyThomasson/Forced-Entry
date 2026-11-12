extends Node
## Human input driver for a Character. Attach as a child of the character; each physics
## frame the character calls `control(character, delta)`, and this is the ONLY place in the
## character domain that reads Keybinds / the mouse. Swap in a different `control()`-having
## node (e.g. an AI brain) to drive a non-player character with no other changes.

## The fire button went down over a HUD control, so this press belongs to the UI until it is
## released.
var _fire_press_on_ui := false
## The door Use (E) went down on, until it is let go: its toggle waits for the release, and the
## wheel turns that door meanwhile, whichever door the aim comes to be nearest by.
var _held_door: Node2D = null
## The wheel turned that door during this hold, so the release does not toggle it.
var _use_scrolled := false


## While Use is held on a door, the wheel and a trackpad's scroll turn that door by steps instead of
## zooming the camera (the event is taken before the camera reads it). With no door in reach the
## scroll goes on to the camera.
func _input(event: InputEvent) -> void:
	if _held_door == null or not Keybinds.is_use_pressed():
		return
	var notches := Keybinds.scroll_notches(event)
	if notches != 0.0 and get_parent().use.doors.turn(notches, _held_door):
		_use_scrolled = true
		get_viewport().set_input_as_handled()


## Called by the character at the top of its _physics_process, so the intent we write is
## used the same frame.
func control(character: CharacterBody2D, _delta: float) -> void:
	character.movement.move_input = Keybinds.get_move_vector()
	character.movement.run_input = Keybinds.is_run_pressed()
	character.movement.aim_point = Pointer.world_mouse(character)

	var selected := Keybinds.get_selected_item()
	if selected > 0:
		character.inventory.select_slot(selected)

	if Keybinds.is_crouch_just_pressed():
		character.movement.toggle_crouch()

	if Keybinds.is_punch_just_pressed():
		character.weapon.melee()
	if Keybinds.is_kick_just_pressed():
		character.anatomy.leg_kick()
	_fire(character)
	if Keybinds.is_reload_just_pressed():
		character.ammo.reload()
	if Keybinds.is_interact_just_pressed():
		character.use.try_interact()
	_use(character)


## Use (E): a vehicle is acted on at the press, as is getting out of one. A door is not: its tap
## toggles it at the release, so that a hold can scroll it instead (DR7), and a hold that scrolled
## leaves it where the scroll put it.
func _use(character: CharacterBody2D) -> void:
	if Keybinds.is_use_just_pressed():
		_held_door = null
		_use_scrolled = false
		if character.use.use_target() == &"door":
			_held_door = character.use.doors.door_in_reach()
		else:
			character.use.try_use()
	if Keybinds.is_use_just_released():
		if _held_door != null and not _use_scrolled:
			character.use.doors.use(_held_door)
		_held_door = null


## Pull the trigger: once per click, and for as long as the button is held with an automatic gun
## (the gun paces itself). A click on a HUD control (the overlay bar, a panel) belongs to the UI,
## not the gun. Input polling ignores GUI mouse filters, so ask the viewport what the pointer is
## over. A press that began on the UI stays the UI's however far it is dragged.
func _fire(character: CharacterBody2D) -> void:
	var over_ui: bool = character.get_viewport().gui_get_hovered_control() != null
	if Keybinds.is_fire_just_pressed():
		_fire_press_on_ui = over_ui
	if over_ui or _fire_press_on_ui:
		return
	if (Keybinds.is_fire_just_pressed()
			or (Keybinds.is_fire_pressed() and character.weapon.is_automatic())):
		character.weapon.shoot()
