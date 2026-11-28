shader_type spatial;
render_mode diffuse_lambert, ambient_light_disabled;
// The textured toon of many posed parts in one mesh (Art, `PartSkin`): `toon_tex.gdshader`'s rules
// (and `toon.gdshader`'s for a part with no art), part for part. A vertex is given in its part's
// own frame and names its part (CUSTOM0.a); `part_pose` puts it where the part is (three basis
// columns and an origin a part, the columns square to one another, so the normal is turned by the
// columns over their lengths squared). The art is projected straight down in the PART's frame, as
// the textured toon projects it in a node's model space, and read from the look's atlas by texel
// (what nearest filtering with no repeat reads). CUSTOM0.rgb is the part's colour (linear): where
// there is no art, or it is clear, the pixel is that colour.

#include "res://scenes/art/post/toon_common.gdshaderinc"
#include "res://scenes/art/post/toon_surface.gdshaderinc"

const int MOST = 32;

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform float side_dim = 0.8;
uniform vec3 part_pose[128];
// Where each part's art is in the atlas: x, y, width, height in texels. Width 0: no art; a
// negative height: a cut-out (a clear texel draws nothing).
uniform vec4 part_atlas[32];
// The footprint each part's art covers, in the part's frame: x, z, width, depth.
uniform vec4 part_uv[32];

varying vec2 model_xz;
varying flat float model_up;
varying flat int part;
varying vec3 colour_of_part;

void vertex() {
	part = int(CUSTOM0.a + 0.5);
	colour_of_part = CUSTOM0.rgb;
	model_xz = VERTEX.xz;
	model_up = NORMAL.y;
	int at = part * 4;
	vec3 x = part_pose[at];
	vec3 y = part_pose[at + 1];
	vec3 z = part_pose[at + 2];
	VERTEX = x * VERTEX.x + y * VERTEX.y + z * VERTEX.z + part_pose[at + 3];
	NORMAL = normalize(
		x * (NORMAL.x / dot(x, x)) + y * (NORMAL.y / dot(y, y)) + z * (NORMAL.z / dot(z, z))
	);
}

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
	vec3 colour = base_color.rgb * colour_of_part;
	vec4 region = part_atlas[part];
	if (region.z > 0.0) {
		vec4 footprint = part_uv[part];
		vec2 size = vec2(region.z, abs(region.w));
		vec2 uv = (model_xz - footprint.xy) / max(footprint.zw, vec2(0.0001));
		bool top = model_up > 0.5;
		ivec2 texel = clamp(ivec2(floor(uv * size)), ivec2(0), ivec2(size) - 1);
		vec4 art = texelFetch(atlas, ivec2(region.xy) + texel, 0);
		if (region.w < 0.0 && art.a < 0.5) {
			discard;
		}
		if (art.a >= 0.5) {
			colour = art.rgb * base_color.rgb;
		}
		if (!top) {
			colour *= side_dim;
		}
	}
	ALBEDO = toon_remember(colour, vision.y);
	EMISSION = emissive.rgb * emissive.a * seen;
	ROUGHNESS = 1.0 - figure;
	SPECULAR = 0.0;
}
