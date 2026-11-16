shader_type spatial;
render_mode diffuse_lambert, ambient_light_disabled;
// The mesh kit's decal (Art, `MeshNodes.decal`; #193 phase 2): a flat quad laid on a surface,
// showing a texture whose alpha cuts it out, lit by the same toon bands as `toon.gdshader` and
// dimmed by the same vision hook (both are `toon_common.gdshaderinc`, the one source).

#include "res://scenes/art/post/toon_common.gdshaderinc"

instance uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;

void fragment() {
	if (toon_dropped(FRAGCOORD.xy)) {
		discard;
	}
	vec4 texel = texture(albedo_texture, UV) * base_color;
	vec3 vision = toon_vision(VERTEX, INV_VIEW_MATRIX);
	if (vision.z > 0.5) {
		discard;
	}
	seen = vision.x;
	spot = toon_spot(VERTEX, INV_VIEW_MATRIX);
	ALBEDO = toon_remember(texel.rgb, vision.y);
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
