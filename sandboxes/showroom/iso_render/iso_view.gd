extends Node
## Spike of #193: the 3D view of a 2D world, as a node a sandbox or the probe adds. It builds a
## SubViewport of its own 3D world (an orthographic Camera3D, one shadow-casting DirectionalLight3D,
## the `ProxyMirror` of the 2D bodies and a full-screen outline quad), shows it through a
## nearest-filtered TextureRect on a CanvasLayer over the 2D world, and follows a focus point at a
## yaw and pitch. The camera's focus snaps to the internal pixel grid and the shown image shifts
## back by the remainder, so a following camera does not shimmer. A pixel post (`IsoConfig.POSTS`)
## sets the internal resolution, the tone bands and the outline.

const IsoConfig := preload("res://sandboxes/showroom/iso_render/iso_config.gd")
const ProxyMirror := preload("res://sandboxes/showroom/iso_render/proxy_mirror.gd")
const OUTLINE := preload("res://sandboxes/showroom/iso_render/iso_outline.gdshader")

## The yaw (degrees) the camera looks from; the sandbox's Q / E turn it, the probe's route sets it.
var yaw := IsoConfig.YAW_START
## The elevation (degrees) of the camera.
var pitch := IsoConfig.PITCH_ISOMETRIC
## Visible world height, units along the screen's vertical (the ortho size).
var world_height := 780.0
## Turn with held Q / E (the sandbox); the probe turns by script.
var turn_keys := true
## Degrees a second the camera turns by script, on top of the keys (the probe's route, a mid-turn
## shot).
var auto_turn := 0.0
## The 2D node (or world point, when null) the camera follows.
var follow: Node2D
var focus := Vector2.ZERO
var mirror: Node3D
var _rect := TextureRect.new()
var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _post_quad := MeshInstance3D.new()
var _post: Dictionary = IsoConfig.POSTS["A"]
var _internal := Vector2i(384, 216)
var _outline_material := ShaderMaterial.new()


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	layer.name = "IsoLayer"
	add_child(layer)
	_rect.texture = _viewport.get_texture()
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_rect)
	_build_viewport()
	get_tree().root.size_changed.connect(_layout)
	_layout()
	_apply_post()


func _exit_tree() -> void:
	var soft := RenderingServer.SHADOW_QUALITY_SOFT_LOW
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)


func _process(delta: float) -> void:
	if turn_keys:
		var turn := 0.0
		if Input.is_physical_key_pressed(KEY_Q):
			turn -= 1.0
		if Input.is_physical_key_pressed(KEY_E):
			turn += 1.0
		yaw = fposmod(yaw + turn * IsoConfig.TURN_SPEED * delta, 360.0)
	yaw = fposmod(yaw + auto_turn * delta, 360.0)
	if follow != null and is_instance_valid(follow):
		focus = follow.global_position
	if mirror != null:
		mirror.update()
	_place_camera()


## Mirror `root`'s 2D bodies into the view (call once, after the world is built).
func mirror_world(root: Node, heights := {}) -> void:
	mirror = ProxyMirror.new()
	mirror.heights = heights
	_viewport.add_child(mirror)
	mirror.mirror(root)
	mirror.material().set_shader_parameter(&"ramp", IsoConfig.ramp())
	_apply_post()


## Show (true) or stop (false) the view: a stopped view renders nothing and costs nothing.
func set_enabled(on: bool) -> void:
	_rect.visible = on
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	)
	set_process(on)


func set_post(post_id: String) -> void:
	_post = IsoConfig.POSTS[post_id]
	_apply_post()


func set_pitch(degrees: float) -> void:
	pitch = degrees


## The viewport the 3D renders into (for the probe's GPU timing).
func viewport_rid() -> RID:
	return _viewport.get_viewport_rid()


## The 2D direction the top of the screen points to on the ground (the camera's forward on the
## ground plane), for a walker whose keys are screen-relative.
func screen_up_on_ground() -> Vector2:
	var forward := -_camera.global_transform.basis.z
	return Vector2(forward.x, forward.z).normalized()


func _build_viewport() -> void:
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.use_debanding = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = false
	add_child(_viewport)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = IsoConfig.CAMERA_NEAR
	_camera.far = IsoConfig.CAMERA_FAR
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_camera.environment = env
	_viewport.add_child(_camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -17.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 1600.0
	sun.shadow_bias = 0.6
	sun.shadow_normal_bias = 1.5
	sun.light_angular_distance = 0.0
	_viewport.add_child(sun)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_post_quad.mesh = quad
	_post_quad.extra_cull_margin = 16_384.0
	_post_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline_material.shader = OUTLINE
	_post_quad.material_override = _outline_material
	_camera.add_child(_post_quad)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)


func _apply_post() -> void:
	var bands: int = _post["bands"]
	_post_quad.visible = float(_post["outline"]) > 0.0
	_outline_material.set_shader_parameter(&"thickness", _post["outline"])
	_outline_material.set_shader_parameter(&"depth_step", _post["depth"])
	_outline_material.set_shader_parameter(&"normal_step", _post["normal"])
	if mirror != null:
		var material: ShaderMaterial = mirror.material()
		material.set_shader_parameter(&"count", bands)
		material.set_shader_parameter(&"pick", _pick_of(bands))
	_layout()


## Which of the five tones the bands take, darkest first: shadow, base, light for three.
func _pick_of(bands: int) -> PackedInt32Array:
	match bands:
		2:
			return PackedInt32Array([0, 2, 2, 2, 2])
		3:
			return PackedInt32Array([0, 2, 3, 3, 3])
		4:
			return PackedInt32Array([0, 1, 2, 3, 3])
		_:
			return PackedInt32Array([0, 1, 2, 3, 4])


## Size the internal viewport and its on-screen rectangle for the window: `lines` rows (the
## window's own when 0), a pixel the same height wide, plus a one-pixel margin all round for the
## sub-pixel shift.
func _layout() -> void:
	var screen := get_tree().root.get_visible_rect().size
	var lines: int = _post["lines"] if int(_post["lines"]) > 0 else int(screen.y)
	var width := int(ceilf(float(lines) * screen.x / screen.y))
	_internal = Vector2i(width, lines)
	_viewport.size = _internal + Vector2i(2, 2)
	_place_camera()


func _place_camera() -> void:
	var screen := get_tree().root.get_visible_rect().size
	var texel := world_height * IsoConfig.UNIT / float(_internal.y)
	_viewport.size = _internal + Vector2i(2, 2)
	_camera.size = texel * float(_internal.y + 2)
	var turned := Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0.0))
	var ground := Vector3(focus.x, 0.0, focus.y) * IsoConfig.UNIT
	# Snap the focus to the internal pixel grid along the camera's right and up; the image is
	# shifted back by what was snapped away.
	var offset := Vector2(ground.dot(turned.x), ground.dot(turned.y))
	var snapped_offset := (offset / texel).round() * texel
	var delta := snapped_offset - offset
	var snapped_focus := ground + turned.x * delta.x + turned.y * delta.y
	_camera.global_transform = Transform3D(
		turned, snapped_focus + turned.z * IsoConfig.CAMERA_DISTANCE
	)
	var pixel := screen.y / float(_internal.y)
	var shift := Vector2(delta.x, -delta.y) / texel
	_rect.size = Vector2(_viewport.size) * pixel
	_rect.position = -Vector2.ONE * pixel + shift * pixel
