// Vision domain: paints the seen part of the world into the memory. The polygon is textured with
// the capture; the pixel written replaces what was there (no blending, the alpha too, so a place
// the capture left empty stays "never seen").
shader_type canvas_item;
render_mode blend_disabled;

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
