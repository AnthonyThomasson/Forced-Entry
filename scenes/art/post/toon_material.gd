class_name ToonMaterial
extends RefCounted
## Art domain, the pixel post (`pixel_post_config.gd`; #193 rule 6): the one toon `ShaderMaterial`
## the 3D render's meshes share, a colour per instance (`base_color`, an instance uniform). The
## mirror's proxies use it now and each domain's mesh will; the tones are `ArtSurfaceConfig`'s ramp
## stepped into `PixelPostConfig.bands` bands by the light.

const SHADER := preload("res://scenes/art/post/toon.gdshader")


## A new toon material set from the holders.
static func make() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	refresh(material)
	return material


## Push the holders' bands and tone ramp into `material` (after a tuning change). The shader's tone
## table holds five tones and a band needs a step above it, so the bands are held to 2 to 5 (0 is a
## smooth ramp, no bands).
static func refresh(material: ShaderMaterial) -> void:
	var bands := 0 if PixelPostConfig.bands <= 0 else clampi(PixelPostConfig.bands, 2, 5)
	material.set_shader_parameter(&"count", bands)
	material.set_shader_parameter(&"ramp", PixelPostConfig.ramp())
	material.set_shader_parameter(&"pick", PixelPostConfig.picks(bands))
