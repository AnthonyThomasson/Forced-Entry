extends Node
## Human input driver for a Character. Attach as a child of the character; each physics
## frame the character calls `control(character, delta)`, and this is the ONLY place in the
## character domain that reads Keybinds / the mouse. Swap in a different `control()`-having
## node (e.g. an AI brain) to drive a non-player character with no other changes.

## The fire button went down over a HUD control, so this press belongs to the UI until it is
## released.
var _fire_press_on_ui := false
## The door Space went down on, until it is let go: its toggle waits for the release, and the
## wheel turns that door meanwhile, whichever door the aim comes to be nearest by.
var _held_door: Node2D = null
## The wheel turned that door during this hold, so the release does not toggle it.
var _use_scrolled := false


## While Space is held on a door, the wheel and a trackpad's scroll turn that door by steps instead
## of zooming the camera (the event is taken before the camera reads it). With no door in reach the
## scroll goes on to the camera.
func _input(event: InputEvent) -> void:
	if _held_door == null or not Keybinds.is_interact_pressed():
		return
	var notches := Keybinds.scroll_notches(event)
	if notches != 0.0 and get_parent().use.doors.turn(notches, _held_door):
		_use_scrolled = true
		get_viewport().set_input_as_handled()


## Called by the character at the top of its _physics_process, so the intent we write is
## used the same frame.
func control(character: CharacterBody2D, _delta: float) -> void:
	character.movement.move_input = _move_keys(character)
	character.movement.run_input = Keybinds.is_run_pressed()
	_aim(character)

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
	_interact(character)


## The cursor's aim (#194 D8): where its line meets a character's body, at that height; else, over
## cover that hides a body, that point on the cover; else the floor point under it, the shot flying
## level at the muzzle's height.
func _aim(character: CharacterBody2D) -> void:
	var meets := Pointer.aim_hit(character, character)
	if meets.is_empty():
		character.movement.aim_point = Pointer.world_mouse(character)
		character.movement.aim_height = CharacterMovement.AIM_LEVEL
	else:
		character.movement.aim_point = meets["plan"]
		character.movement.aim_height = meets["height"]


## The movement keys as a direction in the world. The keys are relative to the screen (W is up the
## screen at any camera yaw, `Pointer.world_direction`); with no camera rig bound the screen is the
## world, so they are as pressed. Seated in a vehicle they stay raw: they are the vehicle's throttle
## and steer, never turned by the camera (`docs/vehicles.md`).
func _move_keys(character: CharacterBody2D) -> Vector2:
	var keys := Keybinds.get_move_vector()
	if character.use.is_in_vehicle():
		return keys
	return Pointer.world_direction(character, keys)


## Space acts on what is nearest the mouse (`use.interact_target`): a chair, a vehicle's door and
## getting out of a vehicle at the press. A door does not: its tap toggles it at the release, so
## that a hold can scroll it instead (DR7), and a hold that scrolled leaves it where the scroll put
## it.
func _interact(character: CharacterBody2D) -> void:
	if Keybinds.is_interact_just_pressed():
		_held_door = null
		_use_scrolled = false
		var target: Dictionary = character.use.interact_target()
		if target.get("kind", &"") == &"door":
			_held_door = target["object"]
		else:
			character.use.try_interact()
	if Keybinds.is_interact_just_released():
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
