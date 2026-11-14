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
## The 3D picture is a `SubViewport` the rig sizes to `RenderConfig.internal_lines` rows at the
## reference window height (scaled with the window's, so a picture pixel stays about 3 screen
## pixels; the window's own rows when 0), times `oversample`, plus a one-pixel margin all round. The
## focus is snapped to the picture's pixel grid along the camera's right and up and the shown
## rectangle is shifted back by what was snapped away, so a following camera never shimmers. The rig
## runs after the `Camera2D` (it is a later node and `process_priority` 100) and, like it, while the
## tree is paused.

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


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)


func _process(_delta: float) -> void:
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
	_place()


## The picture's size in pixels, margin included (the 3D viewport's, divided by `oversample`).
func internal_size() -> Vector2i:
	return _internal


## The 3D units one picture pixel covers along the screen's height.
func texel() -> float:
	return _world_height() / float(maxi(_internal.y - 2, 1))


## Place the camera on the source's focus at its zoom, size the picture and shift it by the snap.
func _place() -> void:
	if not is_instance_valid(_source) or _viewport == null:
		return
	var screen := _source.get_viewport().get_visible_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var lines := _lines_of(screen.y)
	_internal = Vector2i(int(ceilf(float(lines) * screen.x / screen.y)) + 2, lines + 2)
	if _viewport.size != _internal * maxi(oversample, 1):
		_viewport.size = _internal * maxi(oversample, 1)
	var pixel := _world_height() / float(lines)
	camera.size = pixel * float(_internal.y)
	if camera.near != RenderConfig.near or camera.far != RenderConfig.far:
		camera.near = RenderConfig.near
		camera.far = RenderConfig.far
	var turned := Basis.from_euler(
		Vector3(deg_to_rad(-RenderConfig.pitch_degrees), deg_to_rad(yaw), 0.0)
	)
	var focus := _source.get_screen_center_position()
	var ground := Vector3(focus.x, 0.0, focus.y) * RenderConfig.unit
	ground += turned.x * _across(screen, lines) * pixel
	var offset := Vector2(ground.dot(turned.x), ground.dot(turned.y))
	var snapped_offset := (offset / pixel).round() * pixel
	var snap := snapped_offset - offset
	camera.global_transform = Transform3D(
		turned, ground + turned.x * snap.x + turned.y * snap.y + turned.z * RenderConfig.distance
	)
	if _rect != null:
		var scale_up := screen.y / float(lines)
		_rect.size = Vector2(_internal) * scale_up
		_rect.position = (Vector2(snap.x, -snap.y) / pixel - Vector2.ONE) * scale_up


## How many picture pixels the window's middle sits left of the picture's: the picture is whole
## pixels wide and the window is not, so the camera frames that much to the right of the focus.
func _across(screen: Vector2, lines: int) -> float:
	return float(_internal.x) * 0.5 - 1.0 - screen.x * 0.5 * float(lines) / screen.y


## The picture's rows for a window `height` high: `RenderConfig.internal_lines` at the reference
## height, scaled with the window's (the window's own rows when 0).
func _lines_of(height: float) -> int:
	if RenderConfig.internal_lines <= 0:
		return int(height)
	var reference := maxf(RenderConfig.reference_height, 1.0)
	var scaled := height * float(RenderConfig.internal_lines) / reference
	return maxi(int(roundf(scaled)), 4)


## The ground height the picture's rows show, in 3D units: the screen's height in 2D pixels at the
## source's zoom, times the scale.
func _world_height() -> float:
	var screen := _source.get_viewport().get_visible_rect().size
	return screen.y / maxf(_source.zoom.y, 0.001) * RenderConfig.unit
