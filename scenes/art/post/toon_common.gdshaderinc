// The toon light, shared (Art, `toon_material.gd`; #193 rule 6): the ONE source of what the toon
// shaders (`toon.gdshader`, `toon_tex.gdshader` and the kit's `decal.gdshader`) share, so they
// cannot drift apart. It holds the vision hook's globals (phase 3, `toon_mask.gd`), the dusk's
// (`toon_light.gd`), the band uniforms, the fade's dither, the vision-mask read and `light()`: a
// pixel is lit by the dusk's ambient plus every light that reaches it, each light's amount (N.L
// times its fall-off and shadow) stepped into one of `count` bands whose strengths are `levels`
// and tinted by the light's colour, the sum capped at `dusk_cap` times the painted colour, so a
// surface under many lamps is the art lit warm, never blown out (by its brightest channel, so the hue stays). count = 0 steps nothing: a smooth
// light, the unposted reference. A shader that includes it calls `toon_dropped`, `toon_vision`,
// `toon_remember` and `toon_spot` from its `fragment()` (a built-in is not readable from here) and writes ALBEDO; the surface's own
// uniforms (`base_color`, ...) are its own.
//
// The player's view (phase 3, `ToonMask`): `toon_vision.gdshaderinc` holds its globals and the read
// of them by a world position, shared with the outline pass.
#include "res://scenes/art/post/toon_vision.gdshaderinc"

// The dusk (phase 3, `toon_light.gd`): what every surface is lit by, the most it may add up to,
// where the sun reaches (a texture of the street's floors; `sky_masked` 0, the default: everywhere)
// and which room each spot is in (a texture of room ids, red the low byte, green the high; a
// room's light reaches only its own room; `room_masked` 0, the default: no clipping).
global uniform vec3 dusk_ambient;
global uniform float dusk_cap;
global uniform sampler2D sky_mask : repeat_disable, filter_nearest;
global uniform vec4 sky_mask_xf;
global uniform float sky_masked;
global uniform sampler2D room_mask : repeat_disable, filter_nearest;
global uniform vec4 room_mask_xf;
global uniform float room_masked;
global uniform float room_ground;

uniform int count = 3;
uniform float levels[5];
// A positional light's pool is stepped into more bands than the sun (`ToonLightConfig.pool_levels`).
uniform int pool_count = 6;
uniform float pool_levels[8];
// How much of its N.L a positional light's amount is made of (`ToonLightConfig.pool_gain`).
uniform float pool_gain = 3.0;

varying float seen;
// Where the fragment is (`toon_spot`), stored by `fragment()` like `seen`: x whether the sun reaches
// it, y its room id times two, plus one when it is above the ground (a wall, a piece, a person).
varying vec2 spot;

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

// A thing that moves (Art, `MeshNodes.moving`; instance uniform, 1 = a living body, a bullet, a
// burst: what the player's view never remembers) is drawn only where the live cone shows it,
// pixel by pixel, as the 2D view cut it. 0 (the default) is a still thing: shown where it is seen
// now or was seen once.
instance uniform float moving : hint_range(0.0, 1.0) = 0.0;

// What the player's view makes of a pixel (1, 0, 0 everywhere by default). The masks are read only
// while one is set (vision_unseen below 1: a uniform branch), so the default costs the fragment
// nothing. `x` is how much of its light the pixel keeps and scales the light (`light()` below), not
// the albedo: the highlight term adds (1 - ALBEDO), which a dimmed albedo would brighten; `y` is
// how far the albedo takes the remembered look (`toon_remember`); `z` is 1 for a moving thing the
// cone does not show, which `fragment()` discards. `view_vertex` is the fragment's VERTEX;
// `fragment()` stores `x` in `seen`.
vec3 toon_vision(vec3 view_vertex, mat4 inv_view) {
	if (vision_unseen < 1.0) {
		vec3 world_pos = (inv_view * vec4(view_vertex, 1.0)).xyz;
		vec3 read = vision_read(world_pos);
		float hidden = moving > 0.5 && read.z < 0.5 ? 1.0 : 0.0;
		return vec3(read.x, read.y, hidden);
	}
	return vec3(1.0, 0.0, 0.0);
}

// `albedo` in the look of the remembered world, `weight` (`toon_vision().y`) of the way.
vec3 toon_remember(vec3 albedo, float weight) {
	if (weight <= 0.0) {
		return albedo;
	}
	float grey = dot(albedo, vec3(0.299, 0.587, 0.114));
	vec3 look = mix(albedo, vec3(grey), vision_look.x) * vision_tint.rgb;
	return mix(albedo, look, weight);
}

// A light's amount stepped into its band's strength (`count` 0: the amount itself).
float toon_step(float lit) {
	if (count <= 0) {
		return lit;
	}
	return levels[min(int(lit * float(count)), count - 1)];
}

// Where the fragment at `view_vertex` (its VERTEX; `inv_view` the INV_VIEW_MATRIX) is: x 1 where the
// sun reaches (the street's floors, everywhere while no sky mask is set), y its room id times two,
// plus one above the ground (0 where no room map is set). `fragment()` stores it in `spot`.
vec2 toon_spot(vec3 view_vertex, mat4 inv_view) {
	vec2 out_spot = vec2(1.0, 0.0);
	if (sky_masked < 0.5 && room_masked < 0.5) {
		return out_spot;
	}
	vec3 world_pos = (inv_view * vec4(view_vertex, 1.0)).xyz;
	if (sky_masked > 0.5) {
		vec2 uv = world_pos.xz * sky_mask_xf.xy + sky_mask_xf.zw;
		// Beyond the mask's rectangle is no street: no sun.
		bool inside = all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
		out_spot.x = inside ? textureLod(sky_mask, uv, 0.0).r : 0.0;
	}
	if (room_masked > 0.5) {
		vec2 uv = world_pos.xz * room_mask_xf.xy + room_mask_xf.zw;
		bool inside = all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
		vec2 id = inside ? textureLod(room_mask, uv, 0.0).rg : vec2(0.0);
		float room = floor(id.r * 255.0 + 0.5) + floor(id.g * 255.0 + 0.5) * 256.0;
		out_spot.y = room * 2.0 + (world_pos.y > room_ground ? 1.0 : 0.0);
	}
	return out_spot;
}

// A positional light's amount stepped into its pool's band strength (`pool_count` 0: itself; none: none).
float toon_pool(float lit) {
	if (pool_count <= 0 || lit <= 0.0) {
		return lit;
	}
	return pool_levels[min(int(lit * float(pool_count)), pool_count - 1)];
}

// Whether a positional light reaches this fragment (1) or not (0), by the light's room: `code` is
// the light's room id times two plus one if it is a street light (Lighting packs it into the
// light's specular, `SPECULAR_AMOUNT`). A room's light reaches its own room's spots and, above the
// ground, the walls that are in no room; a street light the spots in no room; none reaches into
// another room, so a pool never crosses a wall.
float toon_reach(float code) {
	if (room_masked < 0.5) {
		return 1.0;
	}
	float street = mod(code, 2.0);
	float light_room = floor(code * 0.5);
	float spot_room = floor(spot.y * 0.5);
	float above = mod(spot.y, 2.0);
	if (light_room == spot_room) {
		return 1.0;
	}
	if (spot_room == 0.0 && (street > 0.5 || (light_room > 0.0 && above > 0.5))) {
		return 1.0;
	}
	return 0.0;
}

void light() {
	float n_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 add;
	if (LIGHT_IS_DIRECTIONAL) {
		// The sun (Godot's LIGHT_COLOR is the colour times energy times PI) where it reaches, and
		// the dusk's ambient once, with the one directional light every view has.
		add = LIGHT_COLOR / 3.14159265 * toon_step(n_l * ATTENUATION) * spot.x;
		add += dusk_ambient;
	} else {
		// A positional light's pool: Godot's fall-off (1 - r^4)^2, r the distance over the range
		// (and 0 in a shadow), made linear again (f = 1 - r, 1 under the light, 0 at its rim), and
		// as flat as the light's slope says. Lighting packs both into `light_specular`:
		// SPECULAR_AMOUNT is `slope + 4 * code` (slope 1 or 2: a ceiling lamp's pool is flat to the
		// middle of its radius, a screen's glow is not; `code` the room and street, `toon_reach`).
		float code = floor(SPECULAR_AMOUNT / 4.0 + 0.001);
		float slope = SPECULAR_AMOUNT - 4.0 * code;
		float f = 1.0 - pow(1.0 - sqrt(clamp(ATTENUATION, 0.0, 1.0)), 0.25);
		float lit = clamp(f * slope, 0.0, 1.0) * clamp(n_l * pool_gain, 0.0, 1.0);
		add = LIGHT_COLOR / 3.14159265 * toon_pool(lit) * toon_reach(code);
	}
	// The sum is held to `dusk_cap` by its brightest channel, so a warm pool under a warm lamp stays
	// warm (a cap per channel would wash it to white).
	vec3 sum = DIFFUSE_LIGHT + add * seen;
	float top = max(sum.r, max(sum.g, sum.b));
	DIFFUSE_LIGHT = top > dusk_cap ? sum * (dusk_cap / top) : sum;
}
