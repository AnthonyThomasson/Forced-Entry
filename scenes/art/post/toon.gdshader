shader_type spatial;
render_mode diffuse_lambert, ambient_light_disabled;
// The toon of an untextured mesh (Art, `toon_material.gd`): every such mesh shares one material of
// it (`ToonMaterial.shared`), a colour per instance. The light, the bands, the fade and the vision
// hook are `toon_common.gdshaderinc` (shared by every toon shader); the surface's instance
// uniforms are `toon_surface.gdshaderinc`.

#include "res://scenes/art/post/toon_common.gdshaderinc"
#include "res://scenes/art/post/toon_surface.gdshaderinc"

void fragment() {
	if (toon_dropped(FRAGCOORD.xy)) {
		discard;
	}
	vec3 vision = toon_vision(VERTEX, INV_VIEW_MATRIX);
	if (vision.z > 0.5) {
		discard;
	}
	seen = vision.x;
	spot = toon_spot(VERTEX, INV_VIEW_MATRIX);
	ALBEDO = toon_remember(base_color.rgb * COLOR.rgb, vision.y);
	EMISSION = emissive.rgb * emissive.a * seen;
	ROUGHNESS = 1.0 - figure;
	SPECULAR = 0.0;
}
