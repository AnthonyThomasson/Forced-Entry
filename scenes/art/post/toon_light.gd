class_name ToonLight
extends RefCounted
## Art domain, the pixel post (#193 phase 3, interface 27): the global shader uniforms the toon
## shaders read for the dusk, so the Lighting domain sets the world's ambient, where the sky
## reaches and which room each spot is in without touching a mesh or a material. Globals:
## `dusk_ambient` (what every surface is lit by, a colour times its painted one), `dusk_cap` (the
## most a surface may add up to), `sky_mask` / `sky_mask_xf` / `sky_masked` (a texture whose red
## channel is where the sun reaches, 1 the street's floors, 0 a house; world `(x, z)` in 3D units to
## its uv; `sky_masked` 0, the default: everywhere), and `room_mask` / `room_mask_xf` /
## `room_masked` / `room_ground` (a texture of the room each spot is in, its id in the red and green
## channels, 0 none; a room's light reaches only its own room's spots, `room_masked` 0, the default:
## no clipping).
##
## They must be declared before a shader that names them compiles: `ToonMaterial` calls `install()`
## with the vision hook's `ToonMask.install()`.

const AMBIENT := &"dusk_ambient"
const CAP := &"dusk_cap"
const SKY_MASK := &"sky_mask"
const SKY_TRANSFORM := &"sky_mask_xf"
const SKY_MASKED := &"sky_masked"
const ROOM_MASK := &"room_mask"
const ROOM_TRANSFORM := &"room_mask_xf"
const ROOM_MASKED := &"room_masked"
const ROOM_GROUND := &"room_ground"

## Whether the globals are declared.
static var _installed := false
## What the globals were last set to, for a caller that reads them back (the headless renderer
## keeps none).
static var _ambient := Color(0.0, 0.0, 0.0)
static var _cap := 1.7
static var _sky_rect := Rect2()
static var _room_rect := Rect2()
## The masks' texels, for `sky_reaches` and `room_at` (null: none set).
static var _sky_image: Image
static var _room_image: Image


## Declare the globals with their defaults. Idempotent.
static func install() -> void:
	if _installed:
		return
	_installed = true
	if Engine.is_editor_hint() and RenderingServer.global_shader_parameter_get_list().has(AMBIENT):
		return
	var white := Image.create(1, 1, false, Image.FORMAT_L8)
	white.fill(Color.WHITE)
	var none := Image.create(1, 1, false, Image.FORMAT_RG8)
	var grey := ToonLightConfig.default_ambient
	_ambient = grey
	_add(AMBIENT, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(grey.r, grey.g, grey.b))
	_add(CAP, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, ToonLightConfig.cap)
	_add(SKY_MASK, RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, ImageTexture.create_from_image(white))
	_add(SKY_TRANSFORM, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	_add(SKY_MASKED, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	_add(ROOM_MASK, RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, ImageTexture.create_from_image(none))
	_add(ROOM_TRANSFORM, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	_add(ROOM_MASKED, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	_add(ROOM_GROUND, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, ToonLightConfig.ground_y)


## Light every surface by `colour` (its colour times the painted one) and let it add up to
## `ToonLightConfig.cap`.
static func set_ambient(colour: Color) -> void:
	install()
	RenderingServer.global_shader_parameter_set(AMBIENT, Vector3(colour.r, colour.g, colour.b))
	RenderingServer.global_shader_parameter_set(CAP, ToonLightConfig.cap)
	_ambient = colour
	_cap = ToonLightConfig.cap


## Let a surface add up to `value` times its painted colour (a burst's flash lifts it so a stun can
## wash the world white); `ToonLightConfig.cap` again with no argument.
static func set_cap(value := -1.0) -> void:
	install()
	var held := ToonLightConfig.cap if value < 0.0 else value
	RenderingServer.global_shader_parameter_set(CAP, held)
	_cap = held


## The cap last set (`ToonLightConfig.cap` until one is).
static func cap() -> float:
	return _cap


## The sun reaches only where `image`'s red channel is 1: `world_rect` (2D px) is the part of the
## world the image covers edge to edge (beyond it, no sun).
static func set_sky(image: Image, world_rect: Rect2) -> void:
	install()
	var xf := _transform(world_rect)
	RenderingServer.global_shader_parameter_set(SKY_MASK, ImageTexture.create_from_image(image))
	RenderingServer.global_shader_parameter_set(SKY_TRANSFORM, xf)
	RenderingServer.global_shader_parameter_set(SKY_MASKED, 1.0)
	_sky_rect = world_rect
	_sky_image = image


## A room's light reaches only the spots of its own room (and walls, `ToonLightConfig.ground_y`):
## `image` holds the room id of each texel (red the low byte, green the high, 0 none), covering
## `world_rect` (2D px) edge to edge.
static func set_rooms(image: Image, world_rect: Rect2) -> void:
	install()
	var xf := _transform(world_rect)
	RenderingServer.global_shader_parameter_set(ROOM_MASK, ImageTexture.create_from_image(image))
	RenderingServer.global_shader_parameter_set(ROOM_TRANSFORM, xf)
	RenderingServer.global_shader_parameter_set(
		ROOM_GROUND, ToonLightConfig.ground_y * RenderConfig.unit
	)
	RenderingServer.global_shader_parameter_set(ROOM_MASKED, 1.0)
	_room_rect = world_rect
	_room_image = image


## Back to the defaults: the default ambient, the sun everywhere, no room clipping.
static func clear() -> void:
	install()
	var grey := ToonLightConfig.default_ambient
	RenderingServer.global_shader_parameter_set(AMBIENT, Vector3(grey.r, grey.g, grey.b))
	RenderingServer.global_shader_parameter_set(SKY_MASKED, 0.0)
	RenderingServer.global_shader_parameter_set(ROOM_MASKED, 0.0)
	RenderingServer.global_shader_parameter_set(CAP, ToonLightConfig.cap)
	_cap = ToonLightConfig.cap
	_ambient = grey
	_sky_rect = Rect2()
	_sky_image = null
	_room_rect = Rect2()
	_room_image = null


## The ambient last set (the default after `clear`).
static func ambient() -> Color:
	return _ambient


## The world rect (2D px) of the sky mask last set, empty when none is.
static func sky_rect() -> Rect2:
	return _sky_rect


## Whether the sun reaches world point `at` (2D px): true while no sky mask is set.
static func sky_reaches(at: Vector2) -> bool:
	if _sky_image == null:
		return true
	var spot := _texel(_sky_image, _sky_rect, at)
	return spot.x >= 0 and _sky_image.get_pixel(spot.x, spot.y).r > 0.5


## The id of the room world point `at` (2D px) is in (0: none, or no room map set).
static func room_at(at: Vector2) -> int:
	if _room_image == null:
		return 0
	var spot := _texel(_room_image, _room_rect, at)
	if spot.x < 0:
		return 0
	var c := _room_image.get_pixel(spot.x, spot.y)
	return roundi(c.r * 255.0) + roundi(c.g * 255.0) * 256


## The global `name` of `type` set to `value`.
static func _add(name: StringName, type: int, value: Variant) -> void:
	RenderingServer.global_shader_parameter_add(name, type, value)


## `world_rect` (2D px) as the shader's `(scale, offset)` from world `(x, z)` to uv.
static func _transform(world_rect: Rect2) -> Vector4:
	var size := world_rect.size * RenderConfig.unit
	var scale := Vector2(1.0 / maxf(size.x, 0.0001), 1.0 / maxf(size.y, 0.0001))
	var offset := -world_rect.position * RenderConfig.unit * scale
	return Vector4(scale.x, scale.y, offset.x, offset.y)


## The texel of `image` (covering `rect` edge to edge) at `at`; `(-1, -1)` beyond it.
static func _texel(image: Image, rect: Rect2, at: Vector2) -> Vector2i:
	var size := image.get_size()
	var cell := rect.size / Vector2(size)
	var uv := ((at - rect.position) / cell).floor()
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= size.x or uv.y >= size.y:
		return Vector2i(-1, -1)
	return Vector2i(uv)
