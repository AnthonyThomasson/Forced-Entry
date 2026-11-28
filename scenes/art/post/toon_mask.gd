class_name ToonMask
extends RefCounted
## Art domain, the pixel post (interface 27): the global shader uniforms the
## toon shaders (those that include `toon_common.gdshaderinc`), the drop shadow's and the
## outline pass read for the player's view (`toon_vision.gdshaderinc`), so the vision job puts its
## masks in place without touching a mesh or a material. Seven globals: the live cone `vision_mask`
## (a texture whose red channel is how visible a spot of the ground is, 1 seen to 0 unseen),
## `vision_mask_xf` (`xy` scale and `zw` offset taking a surface's world `(x, z)` in 3D units to its
## uv) and `vision_unseen` (how bright a spot never seen stays, 0 black to 1 untouched); the ground
## ever seen `vision_memory` with `vision_memory_xf`; and the remembered look `vision_look` (grey,
## brightness, contrast, pivot) and `vision_tint`. The default is "everything visible":
## `vision_unseen` 1, whatever the masks hold. Art builds no mask: `set_mask` and `set_memory` are
## what the vision job calls.
##
## The globals must be declared before a shader that names them compiles, so `ToonMaterial.make()`
## and the decal material call `install()`.

const MASK := &"vision_mask"
const TRANSFORM := &"vision_mask_xf"
const UNSEEN := &"vision_unseen"
const MEMORY := &"vision_memory"
const MEMORY_TRANSFORM := &"vision_memory_xf"
const LOOK := &"vision_look"
const TINT := &"vision_tint"

## Whether `install` has declared the globals (they are declared once for the renderer's life).
static var _installed := false
## What the globals were last set to, for a caller that reads them back (`mask_active`,
## `mask_world_rect`): the headless renderer keeps no globals.
static var _active := false
static var _world_rect := Rect2()
static var _memory_rect := Rect2()
## The "nothing remembered" texture the memory global returns to (`clear`).
static var _black: ImageTexture


## Declare the globals with their "everything visible" defaults. Idempotent.
static func install() -> void:
	if _installed:
		return
	_installed = true
	# The editor's renderer outlives a script reload (the statics here start over), so there the
	# globals may be declared already; the list is read only there (the engine allows it nowhere
	# else).
	if Engine.is_editor_hint() and RenderingServer.global_shader_parameter_get_list().has(MASK):
		return
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	RenderingServer.global_shader_parameter_add(
		MASK, RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, ImageTexture.create_from_image(white)
	)
	RenderingServer.global_shader_parameter_add(
		TRANSFORM, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0.0, 0.0, 0.0, 0.0)
	)
	RenderingServer.global_shader_parameter_add(
		UNSEEN, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0
	)
	# The memory: nothing remembered (a black 1 x 1) until `set_memory`, so a mask alone dims
	# everything it leaves unseen, as it always did.
	var black := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	black.fill(Color.BLACK)
	_black = ImageTexture.create_from_image(black)
	RenderingServer.global_shader_parameter_add(
		MEMORY, RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, _black
	)
	RenderingServer.global_shader_parameter_add(
		MEMORY_TRANSFORM, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0.0, 0.0, 0.0, 0.0)
	)
	RenderingServer.global_shader_parameter_add(
		LOOK, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(1.0, 1.0, 1.0, 0.0)
	)
	RenderingServer.global_shader_parameter_add(
		TINT, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(1.0, 1.0, 1.0, 1.0)
	)


## Dim what `texture`'s red channel leaves unseen: `world_rect` (2D px, the art's units) is the part
## of the world the texture covers edge to edge, and ground outside the mask or where it reads 0
## keeps only `unseen_brightness` (0 to 1) of its light.
static func set_mask(texture: Texture2D, world_rect: Rect2, unseen_brightness: float) -> void:
	install()
	RenderingServer.global_shader_parameter_set(MASK, texture)
	RenderingServer.global_shader_parameter_set(TRANSFORM, _to_uv(world_rect))
	RenderingServer.global_shader_parameter_set(UNSEEN, clampf(unseen_brightness, 0.0, 1.0))
	_active = true
	_world_rect = world_rect


## Move the live mask to cover `world_rect` (2D px) without touching its texture or the dim: the
## view's window follows the camera, so this is called when it re-anchors.
static func move_mask(world_rect: Rect2) -> void:
	RenderingServer.global_shader_parameter_set(TRANSFORM, _to_uv(world_rect))
	_world_rect = world_rect


## The remembered world: `texture`'s red channel is how surely a spot of `world_rect` (2D px, the
## texture covers it edge to edge) was ever seen (1 seen, 0 never); where the live mask does not
## show a spot, a remembered one is drawn in the `look` (`Vector4(grey, brightness, contrast,
## pivot)`, as the 2D memory's: greyed by `grey` 0 to 1, keeping `brightness` of its light, the
## `contrast` about `pivot`; 1 and 0 for none) and tinted `tint` (the world as it stands, not a
## frozen picture); a spot never seen keeps the unseen brightness `set_mask` was given.
static func set_memory(
	texture: Texture2D, world_rect: Rect2, look: Vector4, tint: Color
) -> void:
	install()
	RenderingServer.global_shader_parameter_set(MEMORY, texture)
	RenderingServer.global_shader_parameter_set(MEMORY_TRANSFORM, _to_uv(world_rect))
	RenderingServer.global_shader_parameter_set(
		LOOK, Vector4(clampf(look.x, 0.0, 1.0), maxf(look.y, 0.0), look.z, look.w)
	)
	RenderingServer.global_shader_parameter_set(TINT, Vector4(tint.r, tint.g, tint.b, 1.0))
	_memory_rect = world_rect


## Show everything again (the default).
static func clear() -> void:
	install()
	RenderingServer.global_shader_parameter_set(UNSEEN, 1.0)
	if _black != null:
		RenderingServer.global_shader_parameter_set(MEMORY, _black)
	_active = false
	_world_rect = Rect2()
	_memory_rect = Rect2()


## Whether a mask is set (`set_mask` and not yet `clear`).
static func mask_active() -> bool:
	return _active


## The world rect (2D px) of the mask last set, empty when none is.
static func mask_world_rect() -> Rect2:
	return _world_rect


## The world rect (2D px) of the memory last set, empty when none is.
static func memory_world_rect() -> Rect2:
	return _memory_rect


## The `(scale.xy, offset.zw)` taking a surface's world `(x, z)` in 3D units to the uv of a texture
## that covers `world_rect` (2D px) edge to edge.
static func _to_uv(world_rect: Rect2) -> Vector4:
	var size := world_rect.size * RenderConfig.unit
	var scale := Vector2(1.0 / maxf(size.x, 0.0001), 1.0 / maxf(size.y, 0.0001))
	var offset := -world_rect.position * RenderConfig.unit * scale
	return Vector4(scale.x, scale.y, offset.x, offset.y)
