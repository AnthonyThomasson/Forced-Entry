shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled;
// The pixel post's outline (Art, `pixel_post.gd`; #193 rule 6): a full-screen quad in the
// low-resolution viewport that draws a dark outline where the depth or the surface normal steps
// between neighbouring pixels. `silhouette_px` and `crease_px` are in texels of this viewport.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
uniform vec4 outline_color : source_color = vec4(0.06, 0.05, 0.08, 1.0);
uniform float silhouette_px = 1.0;
uniform float crease_px = 1.0;
uniform float depth_step = 0.004;
uniform float normal_step = 0.45;
uniform float crease_gap = 0.012;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(screen_tex, 0));
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;
	float d = texture(depth_tex, SCREEN_UV).r;
	vec3 n = texture(normal_tex, SCREEN_UV).xyz * 2.0 - 1.0;
	vec2 axes[2] = vec2[](vec2(texel.x, 0.0), vec2(0.0, texel.y));
	float edge = 0.0;
	for (int i = 0; i < 2; i++) {
		vec2 sil = axes[i] * silhouette_px;
		float d_before = texture(depth_tex, SCREEN_UV - sil).r;
		float d_after = texture(depth_tex, SCREEN_UV + sil).r;
		// The depth's second difference: a flat slope (a floor seen at an angle) is zero, a step
		// to a nearer surface (reversed depth: larger is nearer) is positive on the far side only,
		// so a silhouette is `silhouette_px` thick.
		edge = max(edge, step(depth_step, d_before + d_after - 2.0 * d));
		// A crease: this pixel's normal differs from the one before it on either axis, where the two
		// are at about one depth (the camera is orthographic, so depth is linear). Across a
		// silhouette the depth test above draws the line, so the normals are not asked: they would
		// mark the near side of it as well and make it two pixels thick on its left and top.
		vec2 before = SCREEN_UV - axes[i] * crease_px;
		vec3 n_before = texture(normal_tex, before).xyz * 2.0 - 1.0;
		float joined = step(abs(texture(depth_tex, before).r - d), crease_gap);
		edge = max(edge, step(normal_step, length(n_before - n)) * joined);
	}
	ALBEDO = mix(base, outline_color.rgb, edge);
}
