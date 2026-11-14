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
## The 3D picture is a `SubViewport` the rig sizes to `RenderConfig.internal_lines` rows (the
## window's own when 0) plus a one-pixel margin all round. The focus is snapped to the picture's
## pixel grid along the camera's right and up and the shown rectangle is shifted back by what was
## snapped away, so a following camera never shimmers. The rig runs after the `Camera2D` (it is a
## later node and `process_priority` 100) and, like it, while the tree is paused.

## The camera's yaw round the focus, in degrees (45: the world's corner faces the camera).
var yaw: float = RenderConfig.yaw_degrees
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
	var lines := RenderConfig.internal_lines if RenderConfig.internal_lines > 0 else int(screen.y)
	_internal = Vector2i(int(ceilf(float(lines) * screen.x / screen.y)) + 2, lines + 2)
	if _viewport.size != _internal:
		_viewport.size = _internal
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


## The ground height the picture's rows show, in 3D units: the screen's height in 2D pixels at the
## source's zoom, times the scale.
func _world_height() -> float:
	var screen := _source.get_viewport().get_visible_rect().size
	return screen.y / maxf(_source.zoom.y, 0.001) * RenderConfig.unit
