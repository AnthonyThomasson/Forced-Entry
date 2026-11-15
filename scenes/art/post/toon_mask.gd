class_name ToonMask
extends RefCounted
## Art domain, the pixel post (#193 phase 3's hook, interface 27): the global shader uniforms the
## toon material (`toon.gdshader`) and the decal's (`decal.gdshader`) read to dim what the player's
## view does not show, so the vision job puts its mask in place without touching a mesh or a
## material. Three globals: `vision_mask` (a texture whose red channel is how visible a spot of the
## ground is, 1 seen to 0 unseen), `vision_mask_xf` (`xy` scale and `zw` offset taking a surface's
## world `(x, z)` in 3D units to the mask's uv) and `vision_unseen` (how bright an unseen spot
## stays,
## 0 black to 1 untouched). The default is "everything visible": `vision_unseen` 1, whatever the
## mask holds. Art builds no mask: `set_mask` is the one call the vision job makes.
##
## The globals must be declared before a shader that names them compiles, so `ToonMaterial.make()`
## and the decal material call `install()`.

const MASK := &"vision_mask"
const TRANSFORM := &"vision_mask_xf"
const UNSEEN := &"vision_unseen"

## Whether `install` has declared the globals (they are declared once for the renderer's life).
static var _installed := false
## What the globals were last set to, for a caller that reads them back (`mask_active`,
## `mask_world_rect`): the headless renderer keeps no globals.
static var _active := false
static var _world_rect := Rect2()


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


## Dim what `texture`'s red channel leaves unseen: `world_rect` (2D px, the art's units) is the part
## of the world the texture covers edge to edge, and ground outside the mask or where it reads 0
## keeps only `unseen_brightness` (0 to 1) of its light.
static func set_mask(texture: Texture2D, world_rect: Rect2, unseen_brightness: float) -> void:
	install()
	var unit := RenderConfig.unit
	var size := world_rect.size * unit
	var scale := Vector2(1.0 / maxf(size.x, 0.0001), 1.0 / maxf(size.y, 0.0001))
	var offset := -world_rect.position * unit * scale
	RenderingServer.global_shader_parameter_set(MASK, texture)
	RenderingServer.global_shader_parameter_set(
		TRANSFORM, Vector4(scale.x, scale.y, offset.x, offset.y)
	)
	RenderingServer.global_shader_parameter_set(UNSEEN, clampf(unseen_brightness, 0.0, 1.0))
	_active = true
	_world_rect = world_rect


## Show everything again (the default).
static func clear() -> void:
	install()
	RenderingServer.global_shader_parameter_set(UNSEEN, 1.0)
	_active = false
	_world_rect = Rect2()


## Whether a mask is set (`set_mask` and not yet `clear`).
static func mask_active() -> bool:
	return _active


## The world rect (2D px) of the mask last set, empty when none is.
static func mask_world_rect() -> Rect2:
	return _world_rect
