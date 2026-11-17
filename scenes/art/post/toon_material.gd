class_name ToonMaterial
extends RefCounted
## Art domain, the pixel post (`pixel_post_config.gd`; #193 rule 6): the one toon `ShaderMaterial`
## the 3D render's meshes share, a colour per instance (`base_color`, an instance uniform). The
## mirror's proxies use it now and each domain's mesh will; each light's amount is stepped into
## `PixelPostConfig.bands` bands (`ToonLightConfig`), the dusk's ambient and the lights added up.

const SHADER := preload("res://scenes/art/post/toon.gdshader")
const DECAL_SHADER := preload("res://scenes/art/post/decal.gdshader")
const TEX_SHADER := preload("res://scenes/art/post/toon_tex.gdshader")
const SHADE_SHADER := preload("res://scenes/art/post/shade.gdshader")
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
## The textured toon materials (`toon_tex.gdshader`), one per texture and tiling, by
## `"<texture id>|<tiled>"`, held weakly as `_decals` are.
static var _textured: Dictionary = {}
## The table's size at which `decal` or `textured` next drops the freed ones (twice what it held
## after the last).
static var _prune_at := 64
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
## `MeshNodes.textured`
## is the entry domains call): the toon bands and ramp of the shared material plus the texture, as
## a decal is held, one for each texture, each `tiled` (the art repeats: a floor tile, a road
## strip) and each `cutout` (a clear texel draws nothing); a node holds it, `refresh_all` keeps it
## in step. A null texture is the shared toon material (nothing to show).
static func textured(texture: Texture2D, tiled := false, cutout := false) -> ShaderMaterial:
	if texture == null:
		return shared()
	var key := "%d|%s|%s" % [texture.get_instance_id(), tiled, cutout]
	var held: Variant = _textured[key].get_ref() if _textured.has(key) else null
	if held is ShaderMaterial:
		return held
	ToonMask.install()
	ToonLight.install()
	_prune()
	var material := ShaderMaterial.new()
	material.shader = TEX_SHADER
	refresh_textured(material)
	material.set_shader_parameter(&"albedo_texture", texture)
	material.set_shader_parameter(&"tiled", tiled)
	material.set_shader_parameter(&"cutout", cutout)
	_textured[key] = weakref(material)
	return material


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
		_shade.set_shader_parameter(&"shape_texture", ImageTexture.create_from_image(image))
	return _shade


## How many textured materials are alive (a test reads it, the perf report too): the ones a node
## still shows.
static func textured_count() -> int:
	_forget_freed()
	return _textured.size()


## How many decal materials are alive (a test reads it): the ones a node still shows.
static func decal_count() -> int:
	_forget_freed()
	return _decals.size()


## Push the holders into the shared material and every live decal material (a new mirror does it, so
## a tuning change applies from the next match).
static func refresh_all() -> void:
	refresh(shared())
	_forget_freed()
	for held: WeakRef in _decals.values():
		var material: Variant = held.get_ref()
		if material is ShaderMaterial:
			refresh(material)
	for held: WeakRef in _textured.values():
		var material: Variant = held.get_ref()
		if material is ShaderMaterial:
			refresh_textured(material)


## Drop the decal and textured materials nothing shows any more, so the tables hold only what is
## alive.
static func _forget_freed() -> void:
	for table: Dictionary in [_decals, _textured]:
		for id: Variant in table.keys():
			if (table[id] as WeakRef).get_ref() == null:
				table.erase(id)


## Before a new decal or textured material: past `_prune_at` entries, drop the freed ones.
static func _prune() -> void:
	if _decals.size() + _textured.size() >= _prune_at:
		_forget_freed()
		_prune_at = maxi(64, (_decals.size() + _textured.size()) * 2)


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
	var pool := 0 if bands == 0 else mini(ToonLightConfig.pool_levels.size(), 8)
	material.set_shader_parameter(&"pool_count", pool)
	material.set_shader_parameter(&"pool_levels", ToonLightConfig.pool())


## `refresh` plus the textured toon's own knob: the step its sides are darkened by
## (`MeshKitConfig.textured_side_dim`).
static func refresh_textured(material: ShaderMaterial) -> void:
	refresh(material)
	material.set_shader_parameter(&"side_dim", MeshKitConfig.textured_side_dim)
