extends Node
## General domain: central place for all input actions, their default bindings and runtime
## rebinding.
##
## Autoloaded as `Keybinds` (see project.godot [autoload]). Everything that reads
## input should go through the constants and helpers here instead of hard-coding
## action-name strings. Each action holds exactly one binding, a key or a mouse button.
## The rebinding store is its part `bindings` (`input_bindings.gd`): the settings page edits them
## through `bindings.bind()` / `bindings.reset()`; `Settings` (also General) persists the
## differences from the defaults via `bindings.overrides()` / `bindings.apply_overrides()`.

const InputBindings := preload("res://scenes/general/input_bindings.gd")
## Action names. Use these constants instead of raw strings elsewhere.
const MOVE_LEFT := "move_left"
const MOVE_RIGHT := "move_right"
const MOVE_UP := "move_up"
const MOVE_DOWN := "move_down"
const RUN := "run"
## Crouch (toggle): a smaller target but slower, and only a standing character can run.
const CROUCH := "crouch"
const PUNCH := "punch"
## Kick with a leg, whatever is held.
const KICK := "kick"
const FIRE := "fire"
const INTERACT := "interact"
## Reload the held gun from a carried magazine.
const RELOAD := "reload"
## Get into the vehicle whose door is nearest, or out of the one the player sits in.
const USE_VEHICLE := "use_vehicle"
## Command teammates (the UI's command menu, built only when the human leads its side): pause and
## open the menu on what is under the cursor.
const COMMAND := "command"
## Return to the pre-game setup window to start a fresh match (handled by main.gd, works in both
## player and spectator mode).
const MENU := "menu"
## Pause/resume the game (spectator inspector only — shares Space with INTERACT, which is unused in
## the player-less spectator match).
const PAUSE := "pause"
## Pan the spectator camera by hand (camera_controller.gd). Shares WASD with the MOVE_* actions —
## harmless because the spectator match has no player to move.
const CAMERA_LEFT := "camera_left"
const CAMERA_RIGHT := "camera_right"
const CAMERA_UP := "camera_up"
const CAMERA_DOWN := "camera_down"
## Zoom the camera (default: mouse wheel).
const ZOOM_IN := "zoom_in"
const ZOOM_OUT := "zoom_out"
const ITEM_1 := "item_1"
const ITEM_2 := "item_2"
const ITEM_3 := "item_3"
const ITEM_4 := "item_4"
const ITEM_5 := "item_5"
const ITEM_6 := "item_6"
const ITEM_7 := "item_7"
const ITEM_8 := "item_8"
const ITEM_9 := "item_9"
## Default key for each action, keyed by action name. Change a value here to change the shipped
## layout — e.g. swap WASD for arrow keys; a player's own changes go through `bindings.bind()` and
## `Settings`.
const DEFAULTS := {
	MOVE_LEFT: KEY_A,
	MOVE_RIGHT: KEY_D,
	MOVE_UP: KEY_W,
	MOVE_DOWN: KEY_S,
	RUN: KEY_SHIFT,
	CROUCH: KEY_C,
	PUNCH: KEY_F,
	KICK: KEY_V,
	INTERACT: KEY_SPACE,
	RELOAD: KEY_R,
	USE_VEHICLE: KEY_E,
	MENU: KEY_ESCAPE,
	PAUSE: KEY_SPACE,
	CAMERA_LEFT: KEY_A,
	CAMERA_RIGHT: KEY_D,
	CAMERA_UP: KEY_W,
	CAMERA_DOWN: KEY_S,
	ITEM_1: KEY_1,
	ITEM_2: KEY_2,
	ITEM_3: KEY_3,
	ITEM_4: KEY_4,
	ITEM_5: KEY_5,
	ITEM_6: KEY_6,
	ITEM_7: KEY_7,
	ITEM_8: KEY_8,
	ITEM_9: KEY_9,
}
## Default mouse button for each pointer-bound action (`MouseButton` values aren't `Key`s, so they
## live apart from DEFAULTS).
const MOUSE_DEFAULTS := {
	FIRE: MOUSE_BUTTON_LEFT,
	COMMAND: MOUSE_BUTTON_RIGHT,
	ZOOM_IN: MOUSE_BUTTON_WHEEL_UP,
	ZOOM_OUT: MOUSE_BUTTON_WHEEL_DOWN,
}
## The settings-page label of each action, in page order. Every action in DEFAULTS / MOUSE_DEFAULTS
## needs a row here and in GROUPS (a test enforces it).
const LABELS := {
	MOVE_UP: "Move up",
	MOVE_DOWN: "Move down",
	MOVE_LEFT: "Move left",
	MOVE_RIGHT: "Move right",
	RUN: "Run (hold)",
	CROUCH: "Crouch",
	PUNCH: "Punch",
	KICK: "Kick",
	FIRE: "Fire",
	RELOAD: "Reload",
	INTERACT: "Interact",
	USE_VEHICLE: "Get in / out of vehicle",
	COMMAND: "Command teammates",
	ITEM_1: "Item 1",
	ITEM_2: "Item 2",
	ITEM_3: "Item 3",
	ITEM_4: "Item 4",
	ITEM_5: "Item 5",
	ITEM_6: "Item 6",
	ITEM_7: "Item 7",
	ITEM_8: "Item 8",
	ITEM_9: "Item 9",
	CAMERA_UP: "Pan up",
	CAMERA_DOWN: "Pan down",
	CAMERA_LEFT: "Pan left",
	CAMERA_RIGHT: "Pan right",
	ZOOM_IN: "Zoom in",
	ZOOM_OUT: "Zoom out",
	PAUSE: "Pause (spectator)",
	MENU: "Back to setup",
}
## The settings-page section each action is listed under.
const GROUPS := {
	MOVE_UP: "Movement",
	MOVE_DOWN: "Movement",
	MOVE_LEFT: "Movement",
	MOVE_RIGHT: "Movement",
	RUN: "Movement",
	CROUCH: "Movement",
	PUNCH: "Combat",
	KICK: "Combat",
	FIRE: "Combat",
	RELOAD: "Combat",
	INTERACT: "Interaction",
	USE_VEHICLE: "Interaction",
	COMMAND: "Interaction",
	ITEM_1: "Items",
	ITEM_2: "Items",
	ITEM_3: "Items",
	ITEM_4: "Items",
	ITEM_5: "Items",
	ITEM_6: "Items",
	ITEM_7: "Items",
	ITEM_8: "Items",
	ITEM_9: "Items",
	CAMERA_UP: "Camera",
	CAMERA_DOWN: "Camera",
	CAMERA_LEFT: "Camera",
	CAMERA_RIGHT: "Camera",
	ZOOM_IN: "Camera",
	ZOOM_OUT: "Camera",
	PAUSE: "System",
	MENU: "System",
}
## Action pairs that deliberately share a binding, so `bindings.conflicts_of()` doesn't flag them:
## Interact and Pause (the player-less spectator match has nothing to interact with) and each camera
## pan key with its move key (the spectator match has no player to move).
const SHARED := [
	[INTERACT, PAUSE],
	[MOVE_UP, CAMERA_UP],
	[MOVE_DOWN, CAMERA_DOWN],
	[MOVE_LEFT, CAMERA_LEFT],
	[MOVE_RIGHT, CAMERA_RIGHT],
]

## The rebinding store: binding, resetting, describing and the saved overrides
## (`input_bindings.gd`), built once with the tables above.
var bindings: InputBindings = InputBindings.new(DEFAULTS, MOUSE_DEFAULTS, SHARED)


func _ready() -> void:
	# Make sure every action exists in the InputMap and matches its default, even if
	# project.godot drifts. This is the single source of truth at runtime. Saved overrides
	# are layered on top by Main (`Settings.load_file()`), not here, so the headless test
	# runner never reads a developer's settings file.
	bindings.reset_all()


## Movement direction from the four move actions, ready to multiply by speed.
func get_move_vector() -> Vector2:
	return Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN)


## True while the run key is held.
func is_run_pressed() -> bool:
	return Input.is_action_pressed(RUN)


## True on the frame the crouch key is pressed (a toggle). Rebindable like the others.
func is_crouch_just_pressed() -> bool:
	return Input.is_action_just_pressed(CROUCH)


## Manual camera pan direction from the four camera actions (length <= 1).
func get_camera_vector() -> Vector2:
	return Input.get_vector(CAMERA_LEFT, CAMERA_RIGHT, CAMERA_UP, CAMERA_DOWN)


## True on the frame the punch key is pressed. Goes through the same rebindable
## action as movement, so rebinding `PUNCH` with `bindings.bind()` just works.
func is_punch_just_pressed() -> bool:
	return Input.is_action_just_pressed(PUNCH)


## True on the frame the kick key is pressed (rebindable through `KICK`).
func is_kick_just_pressed() -> bool:
	return Input.is_action_just_pressed(KICK)


## True on the frame the fire button (left-click) is pressed. Rebindable with `bindings.bind()`
## exactly like the keyboard actions.
func is_fire_just_pressed() -> bool:
	return Input.is_action_just_pressed(FIRE)


## True every frame the fire button is held down: how an automatic gun keeps firing.
func is_fire_pressed() -> bool:
	return Input.is_action_pressed(FIRE)


## True on the frame the interact key (space) is pressed. Goes through the same rebindable
## action path as the others.
func is_interact_just_pressed() -> bool:
	return Input.is_action_just_pressed(INTERACT)


## True on the frame the use-vehicle key (E) is pressed: get in, or out. Rebindable like the others.
func is_use_vehicle_just_pressed() -> bool:
	return Input.is_action_just_pressed(USE_VEHICLE)


## True on the frame the reload key (R) is pressed. Rebindable like the others.
func is_reload_just_pressed() -> bool:
	return Input.is_action_just_pressed(RELOAD)


## Item selection (1-9). Returns the item number (1-9) if an item key was pressed
## on this frame, or -1 if none. Only the first pressed item is returned.
func get_selected_item() -> int:
	var items := [ITEM_1, ITEM_2, ITEM_3, ITEM_4, ITEM_5, ITEM_6, ITEM_7, ITEM_8, ITEM_9]
	for i in range(items.size()):
		if Input.is_action_just_pressed(items[i]):
			return i + 1  # 1-indexed: item 1-9, not 0-8.
	return -1  # No item key pressed.
