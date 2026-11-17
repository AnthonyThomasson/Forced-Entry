shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// The mesh kit's drop shadow (Art, `MeshNodes.shade`; #193 phase 3): a flat dark patch laid on the
// floor under a thing that moves, the 3D twin of the 2D body's floor shadow (a translucent shade the
// floor shows through, `ArtCanvasConfig.drop_shadow_alpha`), whatever the lights are: it is not
// lit and not cast, so it is as short as it is drawn. The player's view hides it where it hides
// the thing (`moving`) and dims it where the ground is unseen, as the toon shaders do
// (`toon_vision.gdshaderinc`, the one source of the view's globals).

#include "res://scenes/art/post/toon_vision.gdshaderinc"

instance uniform float moving : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D shape_texture : filter_nearest, repeat_disable;
instance uniform float strength : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	float seen = 1.0;
	if (vision_unseen < 1.0) {
		vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 read = vision_read(world_pos);
		if (moving > 0.5 && read.z < 0.5) {
			discard;
		}
		seen = read.x;
	}
	ALBEDO = vec3(0.0);
	ALPHA = texture(shape_texture, UV).a * strength * seen;
}
