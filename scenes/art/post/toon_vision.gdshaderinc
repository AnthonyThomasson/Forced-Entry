// The player's view as the shaders read it (Art, `toon_mask.gd`; #193 phase 3): the globals
// `ToonMask` sets and the read of them by a world position, shared by the toon shaders
// (`toon_common.gdshaderinc`) and the outline pass (`outline.gdshader`), so neither draws what the
// other hides.
//
// The globals are phase 3's vision hook (`ToonMask`): `vision_mask` is the cone the player sees
// live (1 seen, 0 not), `vision_memory` the ground ever seen; a spot in neither keeps only
// vision_unseen of its light, one remembered only keeps `vision_look.y` of it and is greyed and
// tinted, one in the cone is as lit. The default (vision_unseen 1) shows everything.

global uniform sampler2D vision_mask : repeat_disable, filter_linear;
global uniform vec4 vision_mask_xf;
global uniform float vision_unseen;
global uniform sampler2D vision_memory : repeat_disable, filter_linear;
global uniform vec4 vision_memory_xf;
global uniform vec4 vision_look;
global uniform vec4 vision_tint;

// What the view makes of the ground at `world_pos` (3D units): x how much of its light a pixel keeps
// (1 in the cone, `vision_look.y` where it is only remembered, `vision_unseen` where it never was),
// y how far the remembered look takes it (0 in the cone), z how much the cone shows it (1 to 0).
// Read only while a mask is set (vision_unseen below 1).
vec3 vision_read(vec3 world_pos) {
	vec2 mask_uv = world_pos.xz * vision_mask_xf.xy + vision_mask_xf.zw;
	vec2 memory_uv = world_pos.xz * vision_memory_xf.xy + vision_memory_xf.zw;
	float live = textureLod(vision_mask, mask_uv, 0.0).r;
	float known = textureLod(vision_memory, memory_uv, 0.0).r;
	float kept = mix(vision_unseen, vision_look.y, known);
	return vec3(mix(kept, 1.0, live), known * (1.0 - live), live);
}
