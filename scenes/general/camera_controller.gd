extends Camera2D
## General domain: the camera. It centers on the player, but leads toward the mouse when it
## approaches screen edges. The mouse wheel zooms, in either mode, as a lasting scale on the
## automatic zoom. In framing mode (the spectator view) the viewer can also take the camera by hand
## — pan with the camera keys or by pushing the mouse to a screen edge — and after
## `CameraConfig.manual_hold` seconds without panning the automatic framing eases back in. An
## explosion on the EventBus shakes the view (through `Camera2D.offset`, so the follow and the
## framing are untouched). Following (or framing) someone aboard a vehicle, the zoom eases out with
## the vehicle's speed (its `view_zoom_out()`, read duck-typed through the target's `use.vehicle()`)
## and back in as it slows. Its tuning is `CameraConfig` (follow, framing, zoom, hand pan) and
## `CameraShakeConfig` (the shake); it follows the input pattern.

## The node to follow. Set in the scene; defaults to a sibling "Player".
@export var target_path: NodePath = ^"../Player"
## Whether the viewer may pan a framing camera by hand. Off where WASD already drives a character.
@export var pan_enabled: bool = true

## The resolved target node.
var _player: Node2D
## When on, frames `_frame_targets` instead of following `_player`.
var _frame_mode: bool = false
## The nodes to keep framed (the match combatants).
var _frame_targets: Array[Node2D] = []
## Framing mode only: the viewer has taken over the position.
var _manual: bool = false
## Seconds since the last pan while `_manual`.
var _idle: float = 0.0
## The automatic zoom the wheel scales: 1 when following, the fit when framing.
var _base_zoom: float = 1.0
## The wheel's lasting scale on `_base_zoom`.
var _zoom_bias: float = 1.0
## Last mouse position seen over the window.
var _mouse_pos := Vector2.ZERO
## Edge panning needs a live pointer: not yet seen, or left, = off.
var _mouse_in_window: bool = false
## 0..1, how much the camera is shaking now.
var _trauma: float = 0.0
## Phase (rad) of the shake's wobbles, advanced at `CameraShakeConfig.speed` while shaking.
var _shake_clock: float = 0.0


func _ready() -> void:
	# the viewer can still pan and zoom while the match is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node_or_null(target_path)
	if not _player:
		push_warning("Camera: could not find target node at %s" % target_path)
	EventBus.posted.connect(_on_posted)


## A pointer that left the window (or a window that lost focus) keeps its last edge position, so
## it stops counting as an edge pan.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_mouse_in_window = false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = event.position
		_mouse_in_window = true


## The mouse wheel (or whatever ZOOM_IN / ZOOM_OUT are bound to) and a trackpad's two-finger scroll
## scale the zoom in either mode and the scale stays; UI that scrolls gets the event first.
func _unhandled_input(event: InputEvent) -> void:
	var notches := 0.0  # signed: positive zooms in
	if event is InputEventPanGesture:
		# Scrolling up (negative delta) zooms in, like wheel-up.
		notches = -event.delta.y * CameraConfig.trackpad_zoom_sensitivity
	elif event.is_action_pressed(Keybinds.ZOOM_IN):
		notches = _wheel_notches(event)
	elif event.is_action_pressed(Keybinds.ZOOM_OUT):
		notches = -_wheel_notches(event)
	else:
		return
	_zoom_bias = clampf(_zoom_bias * pow(CameraConfig.zoom_step, notches),
			CameraConfig.wheel_min_zoom / _base_zoom, CameraConfig.wheel_max_zoom / _base_zoom)


func _process(delta: float) -> void:
	_shake(delta)
	if _frame_mode:
		_steer_by_hand(delta)
		_frame_combatants()
	elif _player:
		var target_pos := _calculate_target_position()
		global_position = global_position.lerp(target_pos, 1.0 / CameraConfig.follow_speed)
		_ease_zoom(1.0 - _drive_zoom_out(_player))


## How many notches a zoom press counts for: a wheel's own amount (fractional for some mice), else
## 1.
func _wheel_notches(event: InputEvent) -> float:
	if event is InputEventMouseButton and event.factor > 0.0:
		return event.factor
	return 1.0


## A grenade went off: shake by its kind and how near it is (linear to nothing at the kind's range,
## felt squared).
func _on_posted(topic: StringName, data: Dictionary) -> void:
	if topic != &"explosion":
		return
	var frag: bool = data.get("kind", &"") == &"frag"
	var reach := CameraShakeConfig.frag_range if frag else CameraShakeConfig.stun_range
	var near := (1.0
			- global_position.distance_to(data.get("position", global_position)) / maxf(reach, 1.0))
	if near > 0.0:
		_trauma = minf(
			_trauma + (CameraShakeConfig.frag if frag else CameraShakeConfig.stun) * near * near,
			1.0,
		)


## Throw the view about by the trauma left (two out-of-step wobbles per axis, so it does not read as
## a pattern) and drain it. Divided by the zoom, so the shake is the same size on screen whatever
## the framing.
func _shake(delta: float) -> void:
	if _trauma <= 0.0:
		offset = Vector2.ZERO
		return
	_shake_clock += delta * CameraShakeConfig.speed
	var wobble := Vector2(sin(_shake_clock) * 0.7 + sin(_shake_clock * 1.7 + 1.3) * 0.3,
			sin(_shake_clock * 1.3 + 2.1) * 0.7 + sin(_shake_clock * 2.3 + 0.4) * 0.3)
	offset = wobble * CameraShakeConfig.max_offset * _trauma * _trauma / zoom.x
	_trauma = maxf(_trauma - CameraShakeConfig.decay * delta, 0.0)


## Switch to framing mode: ease to keep every live node in `targets` on screen (used by the
## spectator match view). A General observer — reads only Node2D positions + the `is_dead` property.
func frame(targets: Array) -> void:
	_frame_targets.clear()
	for t in targets:
		if t is Node2D:
			_frame_targets.append(t)
	_frame_mode = not _frame_targets.is_empty()
	_manual = false


## Framing mode: pan by the camera keys / screen edge, handing control to the viewer while they do
## and back to the automatic framing once `CameraConfig.manual_hold` seconds pass without any camera
## input.
func _steer_by_hand(delta: float) -> void:
	var pan := ((Keybinds.get_camera_vector() + _edge_pan()).limit_length(1.0)
			if pan_enabled
			else Vector2.ZERO)
	if pan != Vector2.ZERO:
		_take_over()
		global_position += pan * CameraConfig.pan_speed * delta / zoom.x
	elif _manual:
		_idle += delta
		if _idle >= CameraConfig.manual_hold:
			_manual = false


## Framing mode: the viewer just panned. Freeze the automatic position where it is and restart the
## idle clock.
func _take_over() -> void:
	_idle = 0.0
	_manual = true


## Ease the zoom toward the automatic zoom scaled by the wheel (and by `out_scale`: under 1 zooms
## out).
func _ease_zoom(out_scale := 1.0) -> void:
	var z := clampf(
		_base_zoom * _zoom_bias * out_scale,
		CameraConfig.wheel_min_zoom,
		CameraConfig.wheel_max_zoom,
	)
	zoom = zoom.lerp(Vector2(z, z), 1.0 / CameraConfig.follow_speed)


## Pan direction from the mouse pushing against a screen edge: each axis -1, 0 or 1.
func _edge_pan() -> Vector2:
	if CameraConfig.edge_pan_margin <= 0.0 or not _mouse_in_window:
		return Vector2.ZERO
	var size := get_viewport_rect().size
	return Vector2(
		float(_mouse_pos.x >= size.x - CameraConfig.edge_pan_margin)
				- float(_mouse_pos.x <= CameraConfig.edge_pan_margin),
		float(_mouse_pos.y >= size.y - CameraConfig.edge_pan_margin)
				- float(_mouse_pos.y <= CameraConfig.edge_pan_margin))


## Centre on the midpoint of the live framed targets (unless the viewer holds the position) and zoom
## to fit them plus `CameraConfig.frame_margin`. A downed combatant drops out of the framing; once
## all are down it holds on the last positions.
func _frame_combatants() -> void:
	var live: Array[Node2D] = []
	for t in _frame_targets:
		if is_instance_valid(t) and t.get("is_dead") != true:
			live.append(t)
	if live.is_empty():
		for t in _frame_targets:
			if is_instance_valid(t):
				live.append(t)
	if live.is_empty():
		return
	var box := Rect2(live[0].global_position, Vector2.ZERO)
	for t in live:
		box = box.expand(t.global_position)
	box = box.grow(CameraConfig.frame_margin)
	if not _manual:
		global_position = global_position.lerp(box.get_center(), 1.0 / CameraConfig.follow_speed)
	var vp := get_viewport_rect().size
	var fit := minf(vp.x / maxf(box.size.x, 1.0), vp.y / maxf(box.size.y, 1.0))
	_base_zoom = clampf(fit, CameraConfig.min_zoom, CameraConfig.max_zoom)
	var out := 0.0
	for t in live:
		out = maxf(out, _drive_zoom_out(t))
	_ease_zoom(1.0 - out)


## How far `who`'s vehicle zooms the view out (0 on foot, or for a vehicle that does not say).
func _drive_zoom_out(who: Node) -> float:
	if not "use" in who:
		return 0.0
	var ride: Variant = who.use.vehicle()
	if not is_instance_valid(ride) or not (ride as Object).has_method("view_zoom_out"):
		return 0.0
	return clampf(float(ride.call("view_zoom_out")), 0.0, 0.9)


## The point the camera eases toward: the target, offset toward the mouse as it nears a
## screen edge.
func _calculate_target_position() -> Vector2:
	var player_pos := _player.global_position
	var mouse_world_pos := get_global_mouse_position()
	var to_mouse := mouse_world_pos - player_pos

	if to_mouse.length() < 0.1:
		# Mouse too close to player, don't look ahead.
		return player_pos

	var dir_to_mouse := to_mouse.normalized()

	# Offset camera toward the mouse.
	var look_offset := dir_to_mouse * CameraConfig.look_ahead_distance * _edge_factor()

	return player_pos + look_offset


## How far the look-ahead is ramped up (0-1): how far from screen centre the mouse is (screen
## space), against the longer axis (x or y) scaled by `CameraConfig.look_ahead_threshold`.
func _edge_factor() -> float:
	var screen_size := get_viewport_rect().size
	var mouse_screen := get_viewport().get_mouse_position()
	var screen_center := screen_size / 2.0
	var edge_offset := (mouse_screen - screen_center).abs()
	var threshold_pixels := maxf(
		screen_size.x,
		screen_size.y,
	) * 0.5 * CameraConfig.look_ahead_threshold
	return (minf(1.0, edge_offset.length() / threshold_pixels)
			if threshold_pixels > 0
			else 0.0)
