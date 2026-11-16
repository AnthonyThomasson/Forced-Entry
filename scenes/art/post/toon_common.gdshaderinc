// The toon light, shared (Art, `toon_material.gd`; #193 rule 6): the ONE source of what the toon
// shaders (`toon.gdshader`, `toon_tex.gdshader` and the kit's `decal.gdshader`) share, so they
// cannot drift apart. It holds the vision hook's globals (phase 3, `toon_mask.gd`), the dusk's
// (`toon_light.gd`), the band uniforms, the fade's dither, the vision-mask read and `light()`: a
// pixel is lit by the dusk's ambient plus every light that reaches it, each light's amount (N.L
// times its fall-off and shadow) stepped into one of `count` bands whose strengths are `levels`
// and tinted by the light's colour, the sum capped at `dusk_cap` times the painted colour, so a
// surface under many lamps is the art lit warm, never blown out (by its brightest channel, so the hue stays). count = 0 steps nothing: a smooth
// light, the unposted reference. A shader that includes it calls `toon_dropped` and `toon_seen`
// from its `fragment()` (a built-in is not readable from here) and writes ALBEDO; the surface's own
// uniforms (`base_color`, ...) are its own.
//
// The three globals are phase 3's vision hook: a spot of the ground the mask leaves unseen keeps
// only vision_unseen of its light, and the default (vision_unseen 1) shows everything.

global uniform sampler2D vision_mask : repeat_disable, filter_linear;
global uniform vec4 vision_mask_xf;
global uniform float vision_unseen;

// The dusk (phase 3, `toon_light.gd`): what every surface is lit by, the most it may add up to, and
// where the sun reaches (a texture of the street's floors; `sky_masked` 0, the default: everywhere).
global uniform vec3 dusk_ambient;
global uniform float dusk_cap;
global uniform sampler2D sky_mask : repeat_disable, filter_nearest;
global uniform vec4 sky_mask_xf;
global uniform float sky_masked;

uniform int count = 3;
uniform float levels[5];
// How much of its N.L a positional light's amount is made of (`ToonLightConfig.pool_gain`).
uniform float pool_gain = 3.0;

varying float seen;
// Whether the sun reaches the fragment (`toon_sky`), stored by `fragment()` like `seen`.
varying float sky;

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

// A light's amount stepped into its band's strength (`count` 0: the amount itself).
float toon_step(float lit) {
	if (count <= 0) {
		return lit;
	}
	return levels[min(int(lit * float(count)), count - 1)];
}

// Whether the sun reaches the fragment at `view_vertex` (its VERTEX; `inv_view` the INV_VIEW_MATRIX):
// the street's floors, everywhere while no sky mask is set. `fragment()` stores it in `sky`.
float toon_sky(vec3 view_vertex, mat4 inv_view) {
	if (sky_masked > 0.5) {
		vec3 world_pos = (inv_view * vec4(view_vertex, 1.0)).xyz;
		vec2 uv = world_pos.xz * sky_mask_xf.xy + sky_mask_xf.zw;
		// Beyond the mask's rectangle is no street: no sun.
		if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
			return 0.0;
		}
		return textureLod(sky_mask, uv, 0.0).r;
	}
	return 1.0;
}

void light() {
	float n_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 add;
	if (LIGHT_IS_DIRECTIONAL) {
		// The sun (Godot's LIGHT_COLOR is the colour times energy times PI) where it reaches, and
		// the dusk's ambient once, with the one directional light every view has.
		add = LIGHT_COLOR / 3.14159265 * toon_step(n_l * ATTENUATION) * sky;
		add += dusk_ambient;
	} else {
		// A positional light's pool: Godot's fall-off (1 - r^4)^2, r the distance over the range
		// (and 0 in a shadow), made linear again (f = 1 - r, 1 under the light, 0 at its rim), and
		// as flat as the light's `light_specular` says (SPECULAR_AMOUNT: the slope of f; a ceiling
		// lamp's pool is flat to the middle of its radius, a screen's glow is not).
		float f = 1.0 - pow(1.0 - sqrt(clamp(ATTENUATION, 0.0, 1.0)), 0.25);
		float lit = clamp(f * SPECULAR_AMOUNT, 0.0, 1.0) * clamp(n_l * pool_gain, 0.0, 1.0);
		add = LIGHT_COLOR / 3.14159265 * toon_step(lit);
	}
	// The sum is held to `dusk_cap` by its brightest channel, so a warm pool under a warm lamp stays
	// warm (a cap per channel would wash it to white).
	vec3 sum = DIFFUSE_LIGHT + add * seen;
	float top = max(sum.r, max(sum.g, sum.b));
	DIFFUSE_LIGHT = top > dusk_cap ? sum * (dusk_cap / top) : sum;
}
