extends RefCounted
## General domain: the rebinding store of the `Keybinds` autoload, a part it builds once with its
## tables and holds as `Keybinds.bindings`. It points each action at its one key or mouse button,
## puts them back on their defaults, describes them for the settings page and owns the saved
## format: `Settings` (also General) persists the differences from the defaults via `overrides()` /
## `apply_overrides()`. It is handed the action tables rather than reading them off the autoload,
## and holds no owner.

## The mouse buttons an action may be bound to, with their display names (the horizontal wheel is
## not bindable).
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Mouse Left",
	MOUSE_BUTTON_RIGHT: "Mouse Right",
	MOUSE_BUTTON_MIDDLE: "Mouse Middle",
	MOUSE_BUTTON_XBUTTON1: "Mouse 4",
	MOUSE_BUTTON_XBUTTON2: "Mouse 5",
	MOUSE_BUTTON_WHEEL_UP: "Wheel Up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down",
}

## Default key for each action (`Keybinds.DEFAULTS`).
var keys: Dictionary
## Default mouse button for each pointer-bound action (`Keybinds.MOUSE_DEFAULTS`).
var mouse: Dictionary
## Action pairs that deliberately share a binding (`Keybinds.SHARED`).
var shared: Array


func _init(default_keys: Dictionary, default_mouse: Dictionary, shared_pairs: Array) -> void:
	keys = default_keys
	mouse = default_mouse
	shared = shared_pairs


## Point `action` at the key or mouse button in `event`, replacing its current binding. A key is
## stored by its physical position (so it survives keyboard layouts); anything else (wheel, gamepad,
## an empty key) is refused. Returns whether the action was rebound.
func bind(action: String, event: InputEvent) -> bool:
	var fresh := _normalized(event)
	if fresh == null:
		return false
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, fresh)
	return true


## Put `action` back on its default binding.
func reset(action: String) -> void:
	bind(action, default_event(action))


## Put every action back on its default binding (and create any that are missing from the InputMap).
func reset_all() -> void:
	for action in actions():
		reset(action)


## Every action that has a default binding (keyboard first, then pointer).
func actions() -> Array:
	return keys.keys() + mouse.keys()


## The binding `action` ships with, or null for an action with none.
func default_event(action: String) -> InputEvent:
	if mouse.has(action):
		return _mouse_event(mouse[action])
	if keys.has(action):
		return _key_event(keys[action])
	return null


## `action`'s current binding as text for a button ("W", "Space", "Mouse Left"), "Unbound" when it
## has none.
func text_of(action: String) -> String:
	var event := _event_of(action)
	if event is InputEventKey:
		var physical: Key = (event as InputEventKey).physical_keycode
		var code: Key = physical
		# The key's label on the player's layout; a headless display server can't map it and logs an
		# error.
		if DisplayServer.get_name() != "headless":
			code = DisplayServer.keyboard_get_keycode_from_physical(physical)
		return OS.get_keycode_string(code if code != KEY_NONE else physical)
	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		return MOUSE_NAMES.get(button, "Mouse %d" % button)
	return "Unbound"


## The other actions that share `action`'s binding, apart from the pairs in `shared`.
func conflicts_of(action: String) -> Array:
	var mine := _serialize(_event_of(action))
	var out := []
	if mine.is_empty():
		return out
	for other in actions():
		if (other != action
				and not _is_shared(action, other)
				and _serialize(_event_of(other)) == mine):
			out.append(other)
	return out


## The bindings that differ from the defaults, as `{ action: { "key": int } | { "mouse": int } }` —
## what `Settings` writes to disk. Only differences are kept, so a changed default still reaches an
## action the player never touched.
func overrides() -> Dictionary:
	var out := {}
	for action in actions():
		var current := _serialize(_event_of(action))
		if current != _serialize(default_event(action)):
			out[action] = current
	return out


## Rebind from an `overrides()`-shaped dictionary (as read back from JSON). Unknown actions and
## malformed entries are skipped one by one; actions not named keep their current binding.
func apply_overrides(data: Dictionary) -> void:
	for action in data:
		if actions().has(action):
			bind(action, _deserialize(data[action]))


## The binding `action` currently has, or null when it has none.
func _event_of(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var events := InputMap.action_get_events(action)
	return null if events.is_empty() else events[0]


## Whether `a` and `b` are a pair that may share a binding.
func _is_shared(a: String, b: String) -> bool:
	for pair in shared:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


## A fresh key or mouse-button event for the same input as `event`, or null when it isn't bindable.
func _normalized(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return null if code == KEY_NONE else _key_event(code)
	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		return _mouse_event(button) if MOUSE_NAMES.has(button) else null
	return null


## A key event for the physical `keycode`.
func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


## A mouse-button event for `button`.
func _mouse_event(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


## `{ "key": physical keycode }` / `{ "mouse": button index }` for a binding, `{}` for none.
func _serialize(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return { "key": int((event as InputEventKey).physical_keycode) }
	if event is InputEventMouseButton:
		return { "mouse": int((event as InputEventMouseButton).button_index) }
	return {}


## The binding a `_serialize()` dictionary describes, or null when it isn't one (JSON numbers arrive
## as floats).
func _deserialize(value: Variant) -> InputEvent:
	if not value is Dictionary:
		return null
	var data := value as Dictionary
	if data.has("key") and typeof(data["key"]) in [TYPE_INT, TYPE_FLOAT]:
		return _key_event(int(data["key"]) as Key)
	if data.has("mouse") and typeof(data["mouse"]) in [TYPE_INT, TYPE_FLOAT]:
		return _mouse_event(int(data["mouse"]) as MouseButton)
	return null
