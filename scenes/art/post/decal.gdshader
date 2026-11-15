shader_type spatial;
render_mode specular_disabled, diffuse_lambert, ambient_light_disabled, shadows_disabled;
// The mesh kit's decal (Art, `MeshNodes.decal`; #193 phase 2): a flat quad laid on a surface,
// showing a texture whose alpha cuts it out, lit by the same toon bands as `toon.gdshader` (the
// light() function is the same; keep the two in step) and dimmed by the same vision hook.

global uniform sampler2D vision_mask : repeat_disable, filter_linear;
global uniform vec4 vision_mask_xf;
global uniform float vision_unseen;

instance uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform int count = 3;
uniform vec2 ramp[5];
uniform int pick[5];

varying float seen;

void fragment() {
	vec4 texel = texture(albedo_texture, UV) * base_color;
	seen = 1.0;
	if (vision_unseen < 1.0) {
		vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 mask_uv = world_pos.xz * vision_mask_xf.xy + vision_mask_xf.zw;
		seen = mix(vision_unseen, 1.0, textureLod(vision_mask, mask_uv, 0.0).r);
	}
	ALBEDO = texel.rgb;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}

void light() {
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	vec2 tone;
	if (count > 0) {
		int band = min(int(lit * float(count)), count - 1);
		tone = ramp[pick[band]];
	} else {
		tone = mix(ramp[0], ramp[4], lit);
	}
	DIFFUSE_LIGHT += vec3(tone.x) * seen;
	SPECULAR_LIGHT += (vec3(1.0) - ALBEDO) * tone.y * seen;
}
