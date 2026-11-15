class_name ToonMaterial
extends RefCounted
## Art domain, the pixel post (`pixel_post_config.gd`; #193 rule 6): the one toon `ShaderMaterial`
## the 3D render's meshes share, a colour per instance (`base_color`, an instance uniform). The
## mirror's proxies use it now and each domain's mesh will; the tones are `ArtSurfaceConfig`'s ramp
## stepped into `PixelPostConfig.bands` bands by the light.

const SHADER := preload("res://scenes/art/post/toon.gdshader")
const DECAL_SHADER := preload("res://scenes/art/post/decal.gdshader")

## The one material every mesh of the 3D view shares: the mirror's proxies and each domain's own
## mesh (`MeshNodes.instance`). Made on first use; a new mirror pushes the holders into it again
## (`refresh`), so a tuning change applies from the next match.
static var _shared: ShaderMaterial
## The mesh kit's decal materials, one per texture (a decal's texture is a uniform of its own, so
## the
## shared material cannot carry it); a material holds its texture, so the key (its instance id)
## is never reused while the material lives.
static var _decals: Dictionary = {}


## A new toon material set from the holders. It declares the vision hook's globals first
## (`ToonMask`: the shader names them).
static func make() -> ShaderMaterial:
	ToonMask.install()
	var material := ShaderMaterial.new()
	material.shader = SHADER
	refresh(material)
	return material


## The decal material showing `texture` (a plain white patch for null), the toon bands and ramp of
## the shared material, made once per texture and refreshed with it (`refresh_all`).
static func decal(texture: Texture2D) -> ShaderMaterial:
	var id: int = texture.get_instance_id() if texture != null else 0
	if not _decals.has(id):
		ToonMask.install()
		var material := ShaderMaterial.new()
		material.shader = DECAL_SHADER
		refresh(material)
		if texture != null:
			material.set_shader_parameter(&"albedo_texture", texture)
		_decals[id] = material
	return _decals[id]


## Push the holders into the shared material and every decal material (a new mirror does it, so a
## tuning change applies from the next match).
static func refresh_all() -> void:
	refresh(shared())
	for material: ShaderMaterial in _decals.values():
		refresh(material)


## The shared material (see `_shared`).
static func shared() -> ShaderMaterial:
	if _shared == null:
		_shared = make()
	return _shared


## Push the holders' bands and tone ramp into `material` (after a tuning change). The shader's tone
## table holds five tones and a band needs a step above it, so the bands are held to 2 to 5 (0 is a
## smooth ramp, no bands).
static func refresh(material: ShaderMaterial) -> void:
	var bands := 0 if PixelPostConfig.bands <= 0 else clampi(PixelPostConfig.bands, 2, 5)
	material.set_shader_parameter(&"count", bands)
	material.set_shader_parameter(&"ramp", PixelPostConfig.ramp())
	material.set_shader_parameter(&"pick", PixelPostConfig.picks(bands))
