// The toon light, shared (Art, `toon_material.gd`; #193 rule 6): the ONE source of what the toon
// shaders (`toon.gdshader`, `toon_tex.gdshader` and the kit's `decal.gdshader`) share, so they
// cannot drift apart. It holds the vision hook's globals (phase 3, `toon_mask.gd`), the band
// uniforms, the fade's dither, the vision-mask read and `light()`: the lit amount (N.L times the
// shadow) picks one of `count` bands, each a tone from the `ArtSurfaceConfig.tones` ramp; there is
// no ambient term, the shadow tone is the floor. count = 0 steps nothing: a smooth ramp, the
// unposted reference. A shader that includes it calls `toon_dropped` and `toon_seen` from its
// `fragment()` (a built-in is not readable from here) and writes ALBEDO; the surface's own
// uniforms (`base_color`, ...) are its own.
//
// The three globals are phase 3's vision hook: a spot of the ground the mask leaves unseen keeps
// only vision_unseen of its light, and the default (vision_unseen 1) shows everything.

global uniform sampler2D vision_mask : repeat_disable, filter_linear;
global uniform vec4 vision_mask_xf;
global uniform float vision_unseen;

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

// True when the fade drops this pixel: `fragment()` discards on it (`pixel` is FRAGCOORD.xy).
bool toon_dropped(vec2 pixel) {
	return fade < 1.0 && dither_keep(pixel) >= fade;
}

// How much of its light a pixel keeps (1 everywhere by default). The mask is read only while one
// is set (vision_unseen below 1: a uniform branch), so the default costs the fragment nothing. It
// scales the light (`light()` below), not the albedo: the highlight term adds (1 - ALBEDO), which
// a dimmed albedo would brighten. `view_vertex` is the fragment's VERTEX; `fragment()` stores the
// result in `seen`.
float toon_seen(vec3 view_vertex, mat4 inv_view) {
	if (vision_unseen < 1.0) {
		vec3 world_pos = (inv_view * vec4(view_vertex, 1.0)).xyz;
		vec2 mask_uv = world_pos.xz * vision_mask_xf.xy + vision_mask_xf.zw;
		return mix(vision_unseen, 1.0, textureLod(vision_mask, mask_uv, 0.0).r);
	}
	return 1.0;
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
