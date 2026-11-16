shader_type spatial;
render_mode specular_disabled, diffuse_lambert, ambient_light_disabled;
// The textured toon (Art, `MeshNodes.textured`; #193 phase 2b): `toon.gdshader` with the 2D
// painters' pixel art on the mesh. The art is painted UNSHADED (no baked light), so the toon bands
// shade it like any toon face; the light, fade, vision hook, figure, glow and outline behave as
// toon (`toon_common.gdshaderinc`, `toon_surface.gdshaderinc`: one source with `toon.gdshader`).
//
// One planar projection, straight down in MODEL space (so the art sticks to the mesh as the node
// turns, stretches and moves): a point at model `(x, z)` reads the texture at
// `((x, z) - uv_rect.xy) / uv_rect.zw`, `uv_rect` the footprint the art covers, in model units
// (`MeshNodes.textured` takes it in px). The camera looks about 80 degrees down, so a top face
// is the whole picture and the sides show a thin sliver. A face is a TOP when its model normal
// has `y > 0.5` (a slope within 60 degrees of flat) and a SIDE otherwise (an underside too: it
// is never seen from above and takes the side rule). The kit's faces are flat, so the choice is
// per face (`flat` varyings). A side:
//   * uses the SAME projection, with its fixed axis (the one its normal points along: a south
//     wall's z) clamped to the texture's edge texels. A vertical wall of the footprint's outline
//     then reads the art's edge, stretched straight down: a table's rim, a wall's cap edge, a
//     car's roof edge, never one smooth colour;
//   * on a `tiled` mesh wraps the axis it runs along by `fract` as a top does, so a long road or
//     wall side repeats the art's edge instead of smearing one texel column;
//   * is darkened by `side_dim` (a step, tuned in `MeshKitConfig.textured_side_dim`) so the edge
//     reads as a side and not as a second top.
// Where the art is clear (alpha < 0.5) the pixel is the vertex colour instead (times base_color; an
// opaque texel is the art times base_color alone: white vertex colour or tones, the art is the albedo),
// so a mesh is whole where its art does not reach. A top is `tiled` when the art repeats (a floor
// tile, a road strip): uv wraps by `fract`, the footprint `uv_rect` is one tile. A skinned mesh
// (`Skeleton3D`) would slide the art over its bones (model space is the rest pose): none is used.
//
// Godot 4.4 instance uniforms cannot be samplers, so the texture is a uniform and there is one
// material per texture (`ToonMaterial.textured`).

#include "res://scenes/art/post/toon_common.gdshaderinc"
#include "res://scenes/art/post/toon_surface.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform bool tiled = false;
// A cut-out mesh draws no clear texel at all (a flat sprite laid over solids, as a head's art over
// its dome: the brim past the dome, the clear ground round it shows what is behind).
uniform bool cutout = false;
uniform float side_dim = 0.8;
// The footprint the art covers, in model units: x, z of its top-left corner, then its width, depth.
instance uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

varying vec2 model_xz;
varying flat float model_up;
varying flat vec2 model_across;

void vertex() {
	model_xz = VERTEX.xz;
	model_up = NORMAL.y;
	model_across = abs(NORMAL.xz);
}

void fragment() {
	if (toon_dropped(FRAGCOORD.xy)) {
		discard;
	}
	seen = toon_seen(VERTEX, INV_VIEW_MATRIX);
	sky = toon_sky(VERTEX, INV_VIEW_MATRIX);
	vec2 uv = (model_xz - uv_rect.xy) / max(uv_rect.zw, vec2(0.0001));
	bool top = model_up > 0.5;
	if (tiled) {
		if (top) {
			uv = fract(uv);
		} else if (model_across.x > model_across.y) {
			// A wall across x: it runs along z.
			uv.y = fract(uv.y);
		} else {
			uv.x = fract(uv.x);
		}
	}
	if (!top) {
		// The fixed axis sits on the footprint's edge (uv 0 or 1): clamp it to the edge texel
		// (the wrapped one is inside already).
		vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
		uv = clamp(uv, half_texel, 1.0 - half_texel);
	}
	vec4 art = texture(albedo_texture, uv);
	if (cutout && art.a < 0.5) {
		discard;
	}
	// The art is the albedo: it is NOT multiplied by the vertex colour (a furniture mesh carries
	// its parts' tones there, which the art already paints). A clear texel shows the vertex colour.
	vec3 colour = art.a >= 0.5 ? art.rgb * base_color.rgb : base_color.rgb * COLOR.rgb;
	ALBEDO = top ? colour : colour * side_dim;
	EMISSION = emissive.rgb * emissive.a * seen;
	ROUGHNESS = 1.0 - figure;
}
