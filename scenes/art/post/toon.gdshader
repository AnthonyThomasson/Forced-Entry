shader_type spatial;
render_mode specular_disabled, diffuse_lambert, ambient_light_disabled;
// The 3D render's one toon material (Art, `toon_material.gd`; #193 rule 6): every mesh the mirror
// and the domains' meshes draw shares it, a colour per instance. The lit amount (N.L times the
// shadow) picks one of `count` bands, each a tone of the instance's base colour from the Art
// domain's `ArtSurfaceConfig.tones` ramp; there is no ambient term, the shadow tone is the floor.
// count = 0 steps nothing: a smooth ramp, the unposted reference.

instance uniform vec4 base_color : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform int count = 3;
uniform vec2 ramp[5];
uniform int pick[5];

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = 1.0;
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
	DIFFUSE_LIGHT += vec3(tone.x);
	SPECULAR_LIGHT += (vec3(1.0) - ALBEDO) * tone.y;
}
