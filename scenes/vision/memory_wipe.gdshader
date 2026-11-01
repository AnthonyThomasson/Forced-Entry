// Vision domain: writes "nothing seen" (all zero, alpha too) over whatever the memory holds,
// replacing it without blending.
shader_type canvas_item;
render_mode blend_disabled;

void fragment() {
	COLOR = vec4(0.0);
}
