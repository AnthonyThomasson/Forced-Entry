shader_type spatial;
// The 3D mirror's proxy material (Art, `mirror_proxy.gd`): one shared material, a colour per
// instance, lit by the view's one sun and flat ambient. The pixel post of #193 replaces it.
render_mode diffuse_lambert, specular_disabled;

instance uniform vec4 base_color : source_color = vec4(0.6, 0.6, 0.6, 1.0);

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = 1.0;
}
