class_name ToonLight
extends RefCounted
## Art domain, the pixel post (#193 phase 3, interface 27): the global shader uniforms the toon
## shaders read for the dusk, so the Lighting domain sets the world's ambient and where the sky
## reaches without touching a mesh or a material. Four globals: `dusk_ambient` (what every surface
## is lit by, a colour times its painted one), `dusk_cap` (the most a surface may add up to),
## `sky_mask` / `sky_mask_xf` (a texture whose red channel is where the sun reaches, 1 the street's
## floors, 0 a house; world `(x, z)` in 3D units to its uv) and `sky_masked` (0: the sun reaches
## everywhere, the default; 1: only where the mask says). The defaults light nothing but the lights
## themselves (`ToonLightConfig.cap`).
##
## They must be declared before a shader that names them compiles: `ToonMaterial` calls `install()`
## with the vision hook's `ToonMask.install()`.

const AMBIENT := &"dusk_ambient"
const CAP := &"dusk_cap"
const SKY_MASK := &"sky_mask"
const SKY_TRANSFORM := &"sky_mask_xf"
const SKY_MASKED := &"sky_masked"

## Whether the globals are declared.
static var _installed := false
## What the globals were last set to, for a caller that reads them back (the headless renderer
## keeps none).
static var _ambient := Color(0.0, 0.0, 0.0)
static var _sky_rect := Rect2()
## The sky mask's texels, for `sky_reaches` (null: no mask set).
static var _sky_image: Image


## Declare the globals with their defaults. Idempotent.
static func install() -> void:
	if _installed:
		return
	_installed = true
	if Engine.is_editor_hint() and RenderingServer.global_shader_parameter_get_list().has(AMBIENT):
		return
	var white := Image.create(1, 1, false, Image.FORMAT_L8)
	white.fill(Color.WHITE)
	RenderingServer.global_shader_parameter_add(
		AMBIENT, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO
	)
	RenderingServer.global_shader_parameter_add(
		CAP, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, ToonLightConfig.cap
	)
	RenderingServer.global_shader_parameter_add(
		SKY_MASK, RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, ImageTexture.create_from_image(white)
	)
	RenderingServer.global_shader_parameter_add(
		SKY_TRANSFORM, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO
	)
	RenderingServer.global_shader_parameter_add(
		SKY_MASKED, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0
	)


## Light every surface by `colour` (its colour times the painted one) and let it add up to
## `ToonLightConfig.cap`.
static func set_ambient(colour: Color) -> void:
	install()
	RenderingServer.global_shader_parameter_set(AMBIENT, Vector3(colour.r, colour.g, colour.b))
	RenderingServer.global_shader_parameter_set(CAP, ToonLightConfig.cap)
	_ambient = colour


## The sun reaches only where `texture`'s red channel is 1: `world_rect` (2D px) is the part of the
## world the texture covers edge to edge.
static func set_sky(texture: Texture2D, world_rect: Rect2) -> void:
	install()
	var size := world_rect.size * RenderConfig.unit
	var scale := Vector2(1.0 / maxf(size.x, 0.0001), 1.0 / maxf(size.y, 0.0001))
	var offset := -world_rect.position * RenderConfig.unit * scale
	RenderingServer.global_shader_parameter_set(SKY_MASK, texture)
	RenderingServer.global_shader_parameter_set(
		SKY_TRANSFORM, Vector4(scale.x, scale.y, offset.x, offset.y)
	)
	RenderingServer.global_shader_parameter_set(SKY_MASKED, 1.0)
	_sky_rect = world_rect
	_sky_image = texture.get_image()


## Back to the defaults: no ambient, the sun everywhere.
static func clear() -> void:
	install()
	RenderingServer.global_shader_parameter_set(AMBIENT, Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(SKY_MASKED, 0.0)
	_ambient = Color(0.0, 0.0, 0.0)
	_sky_rect = Rect2()
	_sky_image = null


## The ambient last set (black after `clear`).
static func ambient() -> Color:
	return _ambient


## The world rect (2D px) of the sky mask last set, empty when none is.
static func sky_rect() -> Rect2:
	return _sky_rect


## Whether the sun reaches world point `at` (2D px): true while no sky mask is set.
static func sky_reaches(at: Vector2) -> bool:
	if _sky_image == null:
		return true
	var cell := _sky_rect.size / Vector2(_sky_image.get_size())
	var uv := ((at - _sky_rect.position) / cell).floor()
	var size := _sky_image.get_size()
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= size.x or uv.y >= size.y:
		return false
	return _sky_image.get_pixel(int(uv.x), int(uv.y)).r > 0.5
