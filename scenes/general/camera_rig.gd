class_name CameraRig
extends Node3D
## General domain, camera: the 3D view's camera (interface 27). An orthographic `Camera3D` at the
## isometric pitch that frames what the sim's `Camera2D` frames. The `Camera2D` stays the focus,
## zoom and shake source (the Sound, the cull and the tests read it), so each frame the rig reads
## its screen centre (the focus plus its shake `offset`) and its `zoom` and places the 3D camera on
## the same ground point at 1 screen pixel to a world pixel at zoom 1 (`RenderConfig.unit` is the
## 2D-to-3D scale). Its `yaw` is a property, in degrees, that the camera-turn controls set; the
## pitch is `RenderConfig.pitch_degrees`.
##
## The 3D picture is a `SubViewport` the rig sizes so a picture pixel is a whole number of screen
## pixels (`RenderConfig.reference_height` over `internal_lines`, 3: 216 rows at a 648-high window)
## at any window size, with as many rows and columns as cover the window, times `oversample`, plus
## a one-pixel margin all round. The focus is snapped to the picture's pixel grid along the camera's
## right and up and the shown rectangle is shifted back by what was snapped away, so a following
## camera never shimmers. The rig runs after the `Camera2D` (it is a later node and
## `process_priority` 50, before the player's view and the ground layer that read it) and, like it,
## while the tree is paused.

## The camera's yaw round the focus, in degrees (45: the world's corner faces the camera).
var yaw: float = RenderConfig.yaw_degrees
## How many times the picture's size the 3D viewport is rendered at (the pixel post's supersample,
## set by the view that averages it back down): 1 renders it at the picture's own size.
var oversample: int = 1
## The orthographic camera, a child of the rig.
var camera: Camera3D
## Where the picture shows on screen (a Control over the window), shifted and sized by the rig; null
## when nothing shows it.
var _rect: Control
var _source: Camera2D
var _viewport: SubViewport
var _internal := Vector2i(2, 2)
## Screen pixels to a picture pixel (whole), and the 3D units a picture pixel covers.
var _scale := 3
var _pixel := 3.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 50
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)


func _exit_tree() -> void:
	Pointer.unbind_3d(camera)


func _process(delta: float) -> void:
	_turn(delta)
	_place()


## Follow `source` (the sim's `Camera2D`), drawing into `viewport`, which the rig sizes; `rect` is
## the Control that shows the picture, moved and sized to keep the focus on the pixel grid.
func bind(source: Camera2D, viewport: SubViewport, rect: Control = null) -> void:
	_source = source
	_viewport = viewport
	_rect = rect
	camera.near = RenderConfig.near
	camera.far = RenderConfig.far
	camera.current = true
	Pointer.bind_3d(camera, rect, source.get_viewport())
	_place()


## The picture's size in pixels, margin included (the 3D viewport's, divided by `oversample`).
func internal_size() -> Vector2i:
	return _internal


## Turn the camera round its focus while a camera-turn key is held (`Keybinds.get_camera_turn`),
## freely and at `RenderConfig.turn_speed_degrees`; released, it stops where it is.
func _turn(delta: float) -> void:
	var held := Keybinds.get_camera_turn()
	if held != 0.0:
		yaw = fposmod(yaw + held * RenderConfig.turn_speed_degrees * delta, 360.0)


## The 3D units one picture pixel covers along the screen's height.
func texel() -> float:
	return _pixel


## Place the camera on the source's focus at its zoom, size the picture and shift it by the snap.
func _place() -> void:
	if not is_instance_valid(_source) or _viewport == null:
		return
	var screen := _source.get_viewport().get_visible_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	_size_picture(screen)
	var turned := Basis.from_euler(
		Vector3(deg_to_rad(-RenderConfig.pitch_degrees), deg_to_rad(yaw), 0.0)
	)
	var focus := _source.get_screen_center_position()
	var ground := Vector3(focus.x, 0.0, focus.y) * RenderConfig.unit
	var middle := _middle(screen)
	ground += (turned.x * middle.x - turned.y * middle.y) * _pixel
	var offset := Vector2(ground.dot(turned.x), ground.dot(turned.y))
	var snapped_offset := (offset / _pixel).round() * _pixel
	var snap := snapped_offset - offset
	camera.global_transform = Transform3D(
		turned, ground + turned.x * snap.x + turned.y * snap.y + turned.z * RenderConfig.distance
	)
	if _rect != null:
		_rect.size = Vector2(_internal * _scale)
		_rect.position = (Vector2(snap.x, -snap.y) / _pixel - Vector2.ONE) * float(_scale)
	Pointer.refresh_3d(camera)  # the once-a-frame affine the mouse and the controls read


## Size the picture for a window of `screen`: a whole number of screen pixels to a picture pixel
## (`RenderConfig.reference_height` over `internal_lines`, rounded: 3 at the reference; 1 when
## `internal_lines` is 0) and as many picture rows and columns as cover the window plus the
## one-pixel margin, so the upscale is exact at any window size; the camera and the 3D viewport
## follow.
func _size_picture(screen: Vector2) -> void:
	_scale = 1
	if RenderConfig.internal_lines > 0:
		var wanted := float(RenderConfig.reference_height) / float(RenderConfig.internal_lines)
		_scale = maxi(roundi(wanted), 1)
	_internal = Vector2i(ceili(screen.x / float(_scale)) + 2, ceili(screen.y / float(_scale)) + 2)
	_pixel = float(_scale) / maxf(_source.zoom.y, 0.001) * RenderConfig.unit
	var rendered := _internal * maxi(oversample, 1)
	if _viewport.size != rendered:
		_viewport.size = rendered
	camera.size = _pixel * float(_internal.y)
	if camera.near != RenderConfig.near or camera.far != RenderConfig.far:
		camera.near = RenderConfig.near
		camera.far = RenderConfig.far


## How many picture pixels the window's middle sits left of (x) and above (y) the picture's: the
## picture covers whole pixels and the window need not, so the camera frames that much to the
## right of the focus and below it.
func _middle(screen: Vector2) -> Vector2:
	return (Vector2(_internal) * 0.5 - Vector2.ONE) - screen * 0.5 / float(_scale)
