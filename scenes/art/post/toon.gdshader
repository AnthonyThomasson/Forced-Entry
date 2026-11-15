shader_type spatial;
render_mode specular_disabled, diffuse_lambert, ambient_light_disabled;
// The 3D render's one toon material (Art, `toon_material.gd`; #193 rule 6): every mesh the mirror
// and the domains' meshes draw shares it, a colour per instance. The lit amount (N.L times the
// shadow) picks one of `count` bands, each a tone of the instance's base colour from the Art
// domain's `ArtSurfaceConfig.tones` ramp; there is no ambient term, the shadow tone is the floor.
// count = 0 steps nothing: a smooth ramp, the unposted reference.

// The mesh kit's faces carry their own colour (the vertex colour, white on a mesh without one);
// base_color tints the whole instance. The three globals are phase 3's vision hook (Art,
// `toon_mask.gd`): a spot of the ground the mask leaves unseen keeps only vision_unseen of its
// light, and the default (vision_unseen 1) shows everything.

global uniform sampler2D vision_mask : repeat_disable, filter_linear;
global uniform vec4 vision_mask_xf;
global uniform float vision_unseen;

instance uniform vec4 base_color : source_color = vec4(0.7, 0.7, 0.7, 1.0);
// A figure (Art, `MeshNodes.figure`; 1 = a character's part): written as the roughness into the
// normal buffer, which the outline pass reads to draw a figure's silhouette only, no creases.
instance uniform float figure : hint_range(0.0, 1.0) = 0.0;
// A glow whatever the light (Art, `MeshNodes.glow`): rgb the colour, a the strength; 0 is none.
instance uniform vec4 emissive : source_color = vec4(0.0);
uniform int count = 3;
uniform vec2 ramp[5];
uniform int pick[5];

varying float seen;

// The fade (Art, `MeshNodes.fade`; instance uniform, 1 = whole): below 1 a pixel is dropped where
// an ordered 4 x 4 dither of the screen pixel says, so a thinning wall stays opaque pixels (no
// blend, no sorting) and reads as the pixel art it is. At 1 the branch is never taken.
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0
);

float dither_keep(vec2 pixel) {
	ivec2 p = ivec2(pixel) & ivec2(3);
	return (BAYER[p.x + p.y * 4] + 0.5) / 16.0;
}

void fragment() {
	if (fade < 1.0 && dither_keep(FRAGCOORD.xy) >= fade) {
		discard;
	}
	// The mask is read only while one is set (vision_unseen below 1: a uniform branch), so the
	// default costs the fragment nothing. It scales the light (light() below), not the albedo:
	// the highlight term adds (1 - ALBEDO), which a dimmed albedo would brighten.
	seen = 1.0;
	if (vision_unseen < 1.0) {
		vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 mask_uv = world_pos.xz * vision_mask_xf.xy + vision_mask_xf.zw;
		seen = mix(vision_unseen, 1.0, textureLod(vision_mask, mask_uv, 0.0).r);
	}
	ALBEDO = base_color.rgb * COLOR.rgb;
	EMISSION = emissive.rgb * emissive.a * seen;
	ROUGHNESS = 1.0 - figure;
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
