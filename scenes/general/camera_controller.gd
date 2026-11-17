extends Camera2D
## General domain: the camera. It centers on the player, but leads toward the mouse as it nears a
## screen edge, up to leaving the player at the opposite edge. The mouse wheel zooms, in either
## mode, as a lasting scale on the automatic zoom. In framing mode (the spectator view) the viewer
## can also take the camera by hand — pan with the camera keys or by pushing the mouse to a screen
## edge — and after `CameraConfig.manual_hold` seconds without panning the automatic framing eases
## back in. An explosion on the EventBus shakes the view (through `Camera2D.offset`, so the follow
## and the framing are untouched). Following (or framing) someone aboard a vehicle, the zoom eases
## out with the vehicle's speed (its `view_zoom_out()`, read duck-typed through the target's
## `use.vehicle()`) and back in as it slows. Its tuning is `CameraConfig` (follow, framing, zoom,
## hand pan) and `CameraShakeConfig` (the shake); it follows the input pattern.

## The node to follow. Set in the scene; defaults to a sibling "Player".
@export var target_path: NodePath = ^"../Player"
## Whether the viewer may pan a framing camera by hand. Off where WASD already drives a character.
@export var pan_enabled: bool = true

## The resolved target node.
var _player: Node2D
## The one-element list `focus_targets` gives while following the player.
var _followed: Array[Node2D] = []
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
## The 3D render's zoom in whole steps and the wheel's place in them.
var _steps := ZoomSteps.new()
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
	else:
		_followed.append(_player)
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
	var notches := Keybinds.scroll_notches(event)  # signed: positive zooms in
	if notches == 0.0:
		return
	if Pointer.is_3d(self):
		_steps.wheel(notches, Time.get_ticks_msec())
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


## Who the view is about: the player while following, every framed node (the match's combatants)
## while spectating. The camera's own list, not a copy: read it, never change it; a node may have
## been freed or be dead. The 3D render's wall fade fades around each (interface 27).
func focus_targets() -> Array[Node2D]:
	return _frame_targets if _frame_mode else _followed


## Switch to framing mode: ease to keep every live node in `targets` on screen (used by the
## spectator match view and the test runner's shared camera, whose zoom then starts afresh). A
## General observer: reads only Node2D positions and the `is_dead` property.
func frame(targets: Array) -> void:
	_frame_targets.clear()
	for t in targets:
		if t is Node2D:
			_frame_targets.append(t)
	_frame_mode = not _frame_targets.is_empty()
	_manual = false
	# a new framing starts from its own fit: the held zoom step and the wheel's scale are forgotten
	_steps = ZoomSteps.new()
	_zoom_bias = 1.0


## Framing mode: pan by the camera keys / screen edge, handing control to the viewer while they do
## and back to the automatic framing once `CameraConfig.manual_hold` seconds pass without any camera
## input.
func _steer_by_hand(delta: float) -> void:
	var pan := ((Keybinds.get_camera_vector() + _edge_pan()).limit_length(1.0)
			if pan_enabled
			else Vector2.ZERO)
	if pan != Vector2.ZERO:
		_take_over()
		# The keys and the edge are screen directions: the ground step that shows as that
		# screen step at the camera's yaw, so the pan is as fast on the screen up it as along it
		# (the pitch squeezes the ground's depth); with no camera rig bound the screen is the world.
		if Pointer.is_3d(self):
			global_position += Pointer.world_vector(self, pan) * CameraConfig.pan_speed * delta
		else:
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
## out). In the 3D render it does not ease: it takes its whole step (`ZoomSteps`).
func _ease_zoom(out_scale := 1.0) -> void:
	if Pointer.is_3d(self):
		var step := _steps.snap(_base_zoom * out_scale, _frame_mode)
		zoom = Vector2(step, step)
		return
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
	var space := _framing_space()
	var box := Rect2(space * live[0].global_position, Vector2.ZERO)
	for t in live:
		box = box.expand(space * t.global_position)
	box = box.grow(CameraConfig.frame_margin)
	if not _manual:
		global_position = global_position.lerp(
			space.affine_inverse() * box.get_center(), 1.0 / CameraConfig.follow_speed
		)
	var vp := get_viewport_rect().size
	var fit := minf(vp.x / maxf(box.size.x, 1.0), vp.y / maxf(box.size.y, 1.0))
	_base_zoom = clampf(fit, CameraConfig.min_zoom, CameraConfig.max_zoom)
	var out := 0.0
	for t in live:
		out = maxf(out, _drive_zoom_out(t))
	_ease_zoom(1.0 - out)


## The space the framing measures the combatants in: the screen at zoom 1 (the ground's
## linear map to the screen at the camera's yaw, without its zoom or origin; with no camera rig
## bound, the world), so the fit is by the extent the screen shows, not by the ground box a turned
## camera sees as a diamond.
func _framing_space() -> Transform2D:
	if not Pointer.is_3d(self):
		return Transform2D.IDENTITY
	var view := Pointer.screen_transform(self)
	return Transform2D(view.x / zoom.x, view.y / zoom.x, Vector2.ZERO)


## How far `who`'s vehicle zooms the view out (0 on foot, or for a vehicle that does not say).
func _drive_zoom_out(who: Node) -> float:
	if not "use" in who:
		return 0.0
	var ride: Variant = who.use.vehicle()
	if not is_instance_valid(ride) or not (ride as Object).has_method("view_zoom_out"):
		return 0.0
	return clampf(float(ride.call("view_zoom_out")), 0.0, 0.9)


## The point the camera eases toward: the target, led toward the mouse. On each screen axis the lead
## eases from nothing inside `CameraConfig.look_ahead_dead_zone` to its full reach at
## `look_ahead_full_at`, and the full reach leaves the target `look_ahead_edge_margin` screen pixels
## in from the opposite edge, so the view looks as far as it can without losing the character. Read
## in screen space, so the camera's own move never feeds back into it.
func _calculate_target_position() -> Vector2:
	var player_pos := _player.global_position
	var half := get_viewport_rect().size * 0.5
	if half.x <= 0.0 or half.y <= 0.0:
		return player_pos
	var from_centre := (Pointer.screen_mouse(self) - half) / half
	var reach := (half - Vector2.ONE * CameraConfig.look_ahead_edge_margin).max(Vector2.ZERO)
	var lead := Vector2(_lead(from_centre.x), _lead(from_centre.y))
	if Pointer.is_3d(self):  # the ground the camera's yaw shows that far along the screen
		return player_pos + Pointer.world_vector(self, lead * reach)
	return player_pos + lead * (reach / zoom)


## The lead (-1..1) along one screen axis for the mouse `u` of the half-screen from the centre.
func _lead(u: float) -> float:
	return signf(u) * smoothstep(
		CameraConfig.look_ahead_dead_zone, CameraConfig.look_ahead_full_at, absf(u)
	)
