shader_type spatial;
render_mode specular_disabled, diffuse_lambert, ambient_light_disabled;
// The textured toon (Art, `MeshNodes.textured`; #193 phase 2b): `toon.gdshader` with the 2D
// painters' pixel art on the mesh. The art is painted UNSHADED (no baked light), so the toon bands
// shade it like any toon face; the light, fade, vision hook, figure, glow and outline behave as
// toon (`toon_common.gdshaderinc`, `toon_surface.gdshaderinc`: one source with `toon.gdshader`).
//
// One planar projection, straight down in MODEL space (so the art sticks to the mesh as the node
// turns and moves): a point at model `(x, z)` reads the texture at
// `((x, z) - uv_rect.xy) / uv_rect.zw`, `uv_rect` the footprint the art covers, in model units
// (`MeshNodes.textured` takes it in px). The camera looks about 80 degrees down, so a top face
// is the whole picture and the sides show a thin sliver; the choice for a side (a face whose
// normal is not up, `NORMAL.y <= 0.5`):
//   * it uses the SAME projection, with uv clamped to the texture's edge texels. A vertical wall
//     of the footprint's outline then reads the art's edge, stretched straight down: a table's
//     rim, a wall's cap edge, a car's roof edge, never one smooth colour;
//   * it is darkened by `side_dim` (a step, tuned in `MeshKitConfig.textured_side_dim`) so the
//     edge reads as a side and not as a second top.
// Where the art is clear (alpha < 0.5) the pixel is the vertex colour instead (times base_color),
// so a mesh is whole where its art does not reach. A top is `tiled` when the art repeats (a floor
// tile, a road strip): uv wraps by `fract`, the footprint `uv_rect` is one tile.
//
// Godot 4.4 instance uniforms cannot be samplers, so the texture is a uniform and there is one
// material per texture (`ToonMaterial.textured`).

#include "res://scenes/art/post/toon_common.gdshaderinc"
#include "res://scenes/art/post/toon_surface.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform bool tiled = false;
uniform float side_dim = 0.8;
// The footprint the art covers, in model units: x, z of its top-left corner, then its width, depth.
instance uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

varying vec2 model_xz;
varying float model_up;

void vertex() {
	model_xz = VERTEX.xz;
	model_up = NORMAL.y;
}

void fragment() {
	if (toon_dropped(FRAGCOORD.xy)) {
		discard;
	}
	seen = toon_seen(VERTEX, INV_VIEW_MATRIX);
	vec2 uv = (model_xz - uv_rect.xy) / max(uv_rect.zw, vec2(0.0001));
	bool top = model_up > 0.5;
	if (top) {
		if (tiled) {
			uv = fract(uv);
		}
	} else {
		vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
		uv = clamp(uv, half_texel, 1.0 - half_texel);
	}
	vec4 art = texture(albedo_texture, uv);
	vec3 tint = base_color.rgb * COLOR.rgb;
	vec3 colour = art.a >= 0.5 ? art.rgb * tint : tint;
	ALBEDO = top ? colour : colour * side_dim;
	EMISSION = emissive.rgb * emissive.a * seen;
	ROUGHNESS = 1.0 - figure;
}
