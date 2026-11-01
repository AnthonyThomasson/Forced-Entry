// Vision domain: paints the seen part of the world into the memory. The polygon is textured with
// the capture; the pixel written replaces what was there (no blending, the alpha too, so a place
// the capture left empty stays "never seen"). A point the capture does not reach (the cone runs
// past the screen) was not seen on it, so it is left as it was.
shader_type canvas_item;
render_mode blend_disabled;

void fragment() {
	if (UV.x < 0.0 || UV.x > 1.0 || UV.y < 0.0 || UV.y > 1.0) {
		discard;
	}
	COLOR = texture(TEXTURE, UV);
}
