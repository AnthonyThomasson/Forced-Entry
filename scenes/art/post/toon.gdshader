shader_type spatial;
render_mode specular_disabled, diffuse_lambert, ambient_light_disabled;
// The 3D render's one toon material (Art, `toon_material.gd`; #193 rule 6): every mesh the mirror
// and the domains' meshes draw shares it, a colour per instance. The light, the bands, the fade
// and the vision hook are `toon_common.gdshaderinc` (shared with `toon_tex.gdshader` and the
// decal); the surface's instance uniforms are `toon_surface.gdshaderinc`.

#include "res://scenes/art/post/toon_common.gdshaderinc"
#include "res://scenes/art/post/toon_surface.gdshaderinc"

void fragment() {
	if (toon_dropped(FRAGCOORD.xy)) {
		discard;
	}
	seen = toon_seen(VERTEX, INV_VIEW_MATRIX);
	spot = toon_spot(VERTEX, INV_VIEW_MATRIX);
	ALBEDO = base_color.rgb * COLOR.rgb;
	EMISSION = emissive.rgb * emissive.a * seen;
	ROUGHNESS = 1.0 - figure;
}
