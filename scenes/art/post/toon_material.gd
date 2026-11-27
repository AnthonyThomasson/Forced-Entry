class_name ToonMaterial
extends RefCounted
## Art domain, the pixel post (`pixel_post_config.gd`): the one toon `ShaderMaterial`
## the 3D render's meshes share, a colour per instance (`base_color`, an instance uniform). The
## mirror's proxies use it now and each domain's mesh will; each light's amount is stepped into
## `PixelPostConfig.bands` bands (`ToonLightConfig`), the dusk's ambient and the lights added up.

const SHADER := preload("res://scenes/art/post/toon.gdshader")
const DECAL_SHADER := preload("res://scenes/art/post/decal.gdshader")
const TEX_SHADER := preload("res://scenes/art/post/toon_tex.gdshader")
const SHADE_SHADER := preload("res://scenes/art/post/shade.gdshader")
## The drop shadow draws after the outline pass (a transparent surface sorts by priority first: the
## outline quad would draw over it from the copy of the screen before it).
const SHADE_PRIORITY := 100
## The texels across the drop shadow's disc.
const SHADE_TEXELS := 32

## The one material every mesh of the 3D view shares: the mirror's proxies and each domain's own
## mesh (`MeshNodes.instance`). Made on first use; a new mirror pushes the holders into it again
## (`refresh`), so a tuning change applies from the next match.
static var _shared: ShaderMaterial
## The mesh kit's live decal materials, one per texture, by the texture's instance id, held weakly:
## a decal's texture is a uniform of its own (the shared material cannot carry it) and a material
## holds its texture, so the nodes showing it are what keep it (and the texture) alive, and the last
## to go frees both. The id is never reused while the material lives.
static var _decals: Dictionary = {}
## The textured toon materials (`toon_tex.gdshader`): one per tiling and cut-out for every texture
## in the atlas (`ToonAtlas`), by `"atlas|<tiled>|<cutout>"`, held for good; and one per texture
## and tiling for a texture too large for the atlas, by `"<texture id>|<tiled>|<cutout>"`, held
## weakly as `_decals` are.
static var _atlased: Dictionary = {}
static var _textured: Dictionary = {}
## The tables' size at which `decal`, `textured` or `follow` next drops the freed ones (twice what
## they held after the last).
static var _prune_at := 64
## The materials of other shaders that take the textured toon's knobs (a `PartSkin`'s), held weakly,
## by instance id (`follow`).
static var _followers: Dictionary = {}
## The drop shadow's material (`shade`), one for every shadow.
static var _shade: ShaderMaterial


## A new toon material set from the holders. It declares the vision hook's globals first
## (`ToonMask`: the shader names them).
static func make() -> ShaderMaterial:
	ToonMask.install()
	ToonLight.install()
	var material := ShaderMaterial.new()
	material.shader = SHADER
	refresh(material)
	return material


## The decal material showing `texture` (a plain white patch for null), the toon bands and ramp of
## the shared material, made when no decal shows that texture and shared by those that do (a node
## holds it; `refresh_all` keeps it in step).
static func decal(texture: Texture2D) -> ShaderMaterial:
	var id: int = texture.get_instance_id() if texture != null else 0
	var held: Variant = _decals[id].get_ref() if _decals.has(id) else null
	if held is ShaderMaterial:
		return held
	ToonMask.install()
	ToonLight.install()
	_prune()
	var material := ShaderMaterial.new()
	material.shader = DECAL_SHADER
	refresh(material)
	if texture != null:
		material.set_shader_parameter(&"albedo_texture", texture)
	_decals[id] = weakref(material)
	return material


## The textured toon material showing `texture` (the 2D painters' art on a mesh,
## `MeshNodes.textured` is the entry domains call: it also tells the node where the texture lies):
## the toon bands and ramp of the shared material, each `tiled` (the art repeats: a floor tile, a
## road strip) and each `cutout` (a clear texel draws nothing). Every texture that fits the atlas
## (`ToonAtlas.fits`) shares one material per tiling and cut-out, so meshes of different art are
## drawn together; a larger one has a material of its own, held by the node showing it, as a decal
## is. `refresh_all` keeps all in step. A null texture is the shared toon material (nothing to
## show).
static func textured(texture: Texture2D, tiled := false, cutout := false) -> ShaderMaterial:
	if texture == null:
		return shared()
	var atlased := ToonAtlas.fits(texture)
	var table := _atlased if atlased else _textured
	var key := "%s|%s|%s" % ["atlas" if atlased else str(texture.get_instance_id()), tiled, cutout]
	var held: Variant = table.get(key)
	if held is WeakRef:
		held = (held as WeakRef).get_ref()
	if held is ShaderMaterial:
		return held
	ToonMask.install()
	ToonLight.install()
	_prune()
	var material := ShaderMaterial.new()
	material.shader = TEX_SHADER
	refresh_textured(material)
	material.set_shader_parameter(&"atlased", atlased)
	if atlased:
		material.set_shader_parameter(&"atlas", ToonAtlas.array())
		_atlased[key] = material
	else:
		material.set_shader_parameter(&"albedo_texture", texture)
		_textured[key] = weakref(material)
	material.set_shader_parameter(&"tiled", tiled)
	material.set_shader_parameter(&"cutout", cutout)
	return material


## Give `material`, of a shader with the textured toon's knobs (`toon_parts.gdshader`), the
## holders, now and at every `refresh_all` while it lives.
static func follow(material: ShaderMaterial) -> void:
	_prune()
	refresh_textured(material)
	_followers[material.get_instance_id()] = weakref(material)


## The drop shadow's material (`shade.gdshader`): a round patch (a disc of `SHADE_TEXELS` texels,
## hard edged as pixel art is) of black at `strength` (an alpha: the floor shows through), shared by
## every shadow. Not lit and not cast; the player's view dims and hides it as it does the toon
## shaders.
static func shade() -> ShaderMaterial:
	if _shade == null:
		ToonMask.install()
		var image := Image.create(SHADE_TEXELS, SHADE_TEXELS, false, Image.FORMAT_RGBA8)
		var middle := (SHADE_TEXELS - 1) * 0.5
		for y in SHADE_TEXELS:
			for x in SHADE_TEXELS:
				var inside := Vector2(x - middle, y - middle).length() <= SHADE_TEXELS * 0.5
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0 if inside else 0.0))
		_shade = ShaderMaterial.new()
		_shade.shader = SHADE_SHADER
		_shade.render_priority = SHADE_PRIORITY
		_shade.set_shader_parameter(&"shape_texture", ImageTexture.create_from_image(image))
	return _shade


## How many textures the textured toon shows now (a test reads it, the perf report too): those in
## the atlas and those with a material of their own that something still holds.
static func textured_count() -> int:
	_forget_freed()
	return ToonAtlas.count() + _textured.size()


## How many decal materials are alive (a test reads it): the ones a node still shows.
static func decal_count() -> int:
	_forget_freed()
	return _decals.size()


## Push the holders into the shared material and every live decal and textured material (a new
## mirror does it, so a tuning change applies from the next match).
static func refresh_all() -> void:
	refresh(shared())
	_forget_freed()
	for held: WeakRef in _decals.values():
		var material: Variant = held.get_ref()
		if material is ShaderMaterial:
			refresh(material)
	for material: ShaderMaterial in _atlased.values():
		refresh_textured(material)
	for held: WeakRef in _textured.values() + _followers.values():
		var material: Variant = held.get_ref()
		if material is ShaderMaterial:
			refresh_textured(material)


## Drop the decal, textured and following materials nothing shows any more, so the tables hold only
## what is alive.
static func _forget_freed() -> void:
	for table: Dictionary in [_decals, _textured, _followers]:
		for id: Variant in table.keys():
			if (table[id] as WeakRef).get_ref() == null:
				table.erase(id)


## Before a new material is held: past `_prune_at` entries, drop the freed ones.
static func _prune() -> void:
	if _held_count() >= _prune_at:
		_forget_freed()
		_prune_at = maxi(64, _held_count() * 2)


## How many entries the tables of held materials have.
static func _held_count() -> int:
	return _decals.size() + _textured.size() + _followers.size()


## The shared material (see `_shared`).
static func shared() -> ShaderMaterial:
	if _shared == null:
		_shared = make()
	return _shared


## Push the holders' bands and their strengths into `material` (after a tuning change). The shader's
## table holds five bands, so the bands are held to 2 to 5 (0 is a smooth light, no bands).
static func refresh(material: ShaderMaterial) -> void:
	var bands := 0 if PixelPostConfig.bands <= 0 else clampi(PixelPostConfig.bands, 2, 5)
	material.set_shader_parameter(&"count", bands)
	material.set_shader_parameter(&"levels", ToonLightConfig.levels(bands))
	material.set_shader_parameter(&"pool_gain", ToonLightConfig.pool_gain)
	material.set_shader_parameter(
		&"pool_high",
		Vector3(
			ToonLightConfig.high_from * RenderConfig.unit,
			ToonLightConfig.high_to * RenderConfig.unit,
			ToonLightConfig.high_scale,
		),
	)
	var pool := 0 if bands == 0 else mini(ToonLightConfig.pool_levels.size(), 8)
	material.set_shader_parameter(&"pool_count", pool)
	material.set_shader_parameter(&"pool_levels", ToonLightConfig.pool())


## `refresh` plus the textured toon's own knob: the step its sides are darkened by
## (`MeshKitConfig.textured_side_dim`).
static func refresh_textured(material: ShaderMaterial) -> void:
	refresh(material)
	material.set_shader_parameter(&"side_dim", MeshKitConfig.textured_side_dim)
