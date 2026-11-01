// Vision domain: the layer drawn over the world. Inside the cone it is transparent (the live world
// shows, characters included); outside it is the memory, the world as last seen, in the picked
// look, and black where nothing was ever seen. Unshaded, so the world's dusk and lights do not
// colour it a second time.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D memory : filter_nearest, repeat_disable;
uniform sampler2D cone_mask : filter_linear, repeat_disable;
// The main viewport's size in pixels, and the screen to world transform (inverse canvas transform).
uniform vec2 view_size;
uniform vec2 inv_x;
uniform vec2 inv_y;
uniform vec2 inv_o;
// The memory texture: the world point of its corner, its texels per world pixel and its size.
uniform vec2 memory_origin;
uniform float memory_scale;
uniform vec2 memory_size;
// 0: the mask is a hard 0 / 1. 1: the mask is a disc blur of the polygon, 0.5 at the edge; the
// feather is laid inside the edge (0 at the edge, 1 a feather width in).
uniform float soft;
// The look of the remembered world: how far to grey, the contrast about a pivot, the brightness
// and a tint.
uniform float grey;
uniform float contrast;
uniform float pivot;
uniform float brightness;
uniform vec3 tint;

vec3 remembered_look(vec3 c) {
	vec3 g = vec3(dot(c, vec3(0.299, 0.587, 0.114)));
	vec3 l = mix(c, g, grey);
	l = (l - vec3(pivot)) * contrast + vec3(pivot);
	return clamp(l * brightness * tint, 0.0, 1.0);
}

void fragment() {
	float m = texture(cone_mask, SCREEN_UV).r;
	float inside = step(0.5, m);
	if (soft > 0.5) {
		inside = smoothstep(0.0, 1.0, clamp(2.0 * m - 1.0, 0.0, 1.0));
	}
	vec2 px = SCREEN_UV * view_size;
	vec2 world = inv_x * px.x + inv_y * px.y + inv_o;
	vec2 at = (world - memory_origin) * memory_scale / memory_size;
	vec4 seen = texture(memory, at);
	float in_memory = step(0.0, at.x) * step(at.x, 1.0) * step(0.0, at.y) * step(at.y, 1.0);
	float known = step(0.02, seen.a) * in_memory;
	COLOR = vec4(remembered_look(seen.rgb) * known, 1.0 - inside);
}
