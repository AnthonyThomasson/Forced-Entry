shader_type spatial;
render_mode diffuse_lambert, ambient_light_disabled;
// The toon of a merged chunk of the still world (Art, `mirror/still_merge.gd`): one mesh holding
// many still meshes, so one draw shows what `toon.gdshader`, `toon_tex.gdshader` (its art in the
// atlas) and `decal.gdshader` drew in many. What those take from a mesh's frame and its instance
// uniforms comes from the vertices, the same value on every vertex of a mesh:
//   UV       a textured part: its own model (x, z); a decal: its quad's uv
//   UV2      x: the kind (0 plain, 1 textured, 2 textured tiled, 3 textured cut-out, 4 both,
//            5 decal, 6 decal with no picture), y: `figure`
//   CUSTOM0  `uv_rect`   CUSTOM1 `atlas_rect`   CUSTOM2 `base_color` (linear)
//   CUSTOM3  the vertex's normal in its own mesh (what says a top from a side)
// The rules of each kind are documented in the shader it stands in for. `fade`, `moving` and
// `emissive` are never other than their defaults in a chunk: a mesh that has one set draws itself.

#include "res://scenes/art/post/toon_common.gdshaderinc"

uniform sampler2DArray atlas : source_color, filter_nearest, repeat_disable;
uniform float side_dim = 0.8;

varying vec2 model_uv;
varying flat vec4 part_uv_rect;
varying flat vec4 part_atlas_rect;
varying flat vec4 part_color;
varying flat float part_kind;
varying flat float part_figure;
varying flat float model_up;
varying flat vec2 model_across;

void vertex() {
	model_uv = UV;
	part_kind = UV2.x;
	part_figure = UV2.y;
	part_uv_rect = CUSTOM0;
	part_atlas_rect = CUSTOM1;
	part_color = CUSTOM2;
	model_up = CUSTOM3.y;
	model_across = abs(CUSTOM3.xz);
}

// The texel of the atlas the part's art holds at `uv` (0 to 1 over the art).
vec4 atlas_texel(vec2 uv, vec4 place) {
	float layer = floor(place.x / 4096.0);
	vec2 corner = vec2(place.x - layer * 4096.0, place.y);
	vec2 texel = clamp(floor(uv * place.zw), vec2(0.0), place.zw - 1.0);
	return texelFetch(atlas, ivec3(ivec2(corner + texel), int(layer)), 0);
}

void fragment() {
	vec3 vision = toon_vision(VERTEX, INV_VIEW_MATRIX);
	seen = vision.x;
	spot = toon_spot(VERTEX, INV_VIEW_MATRIX);
	int kind = int(part_kind + 0.5);
	if (kind >= 5) {
		vec4 texel = kind == 5 ? atlas_texel(model_uv, part_atlas_rect) : vec4(1.0);
		texel *= part_color;
		if (texel.a < 0.5) {
			discard;
		}
		ALBEDO = toon_remember(texel.rgb, vision.y);
		ROUGHNESS = 1.0;
	} else {
		if (kind == 0) {
			ALBEDO = toon_remember(part_color.rgb * COLOR.rgb, vision.y);
		} else {
			vec2 uv = (model_uv - part_uv_rect.xy) / max(part_uv_rect.zw, vec2(0.0001));
			bool top = model_up > 0.5;
			if (kind == 2 || kind == 4) {
				if (top) {
					uv = fract(uv);
				} else if (model_across.x > model_across.y) {
					uv.y = fract(uv.y);
				} else {
					uv.x = fract(uv.x);
				}
			}
			if (!top) {
				vec2 half_texel = 0.5 / part_atlas_rect.zw;
				uv = clamp(uv, half_texel, 1.0 - half_texel);
			}
			vec4 art = atlas_texel(uv, part_atlas_rect);
			if (kind >= 3 && art.a < 0.5) {
				discard;
			}
			vec3 colour = art.a >= 0.5 ? art.rgb * part_color.rgb : part_color.rgb * COLOR.rgb;
			ALBEDO = toon_remember(top ? colour : colour * side_dim, vision.y);
		}
		ROUGHNESS = 1.0 - part_figure;
	}
	SPECULAR = 0.0;
}
