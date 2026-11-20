# The vision hook (side file of `domain-art`)

The player's view in 3D (`docs/player-vision.md` V12; `ToonMask`, `toon_vision.gdshaderinc`, `toon.gdshader`, `decal.gdshader`).

Global shader uniforms, declared by `ToonMaterial.make()` / `ToonMaterial.decal()` through `ToonMask.install()`: `vision_mask` (the live cone: a texture's red channel, 1 seen, 0 not) with `vision_mask_xf` (world `(x, z)` in 3D units to its uv),
`vision_unseen` (the brightness a spot never seen keeps; **1 by default: everything visible**, whatever the masks hold), `vision_memory` with `vision_memory_xf` (where the player has ever seen: nothing until `set_memory`) and `vision_look` (grey, brightness, contrast, pivot) / `vision_tint`
(the remembered look, as the 2D memory's). `ToonMask.set_mask(texture, world_rect_px, unseen_brightness)`, `move_mask(world_rect_px)`, `set_memory(texture, world_rect_px, look: Vector4, tint)`, `clear()`, `mask_active()`,
`mask_world_rect()`, `memory_world_rect()` are the whole interface; Vision's `ViewGround` is the one caller. The masks are read only while `vision_unseen` is below 1 (a uniform branch: the default costs nothing). A spot in the cone is lit as it is; one only remembered keeps `vision_look.y` of its
light and its albedo is greyed and tinted (`toon_remember`: the current world in a dimmer, greyer look, not a picture of it); one never seen keeps `vision_unseen` (0: black). It scales the light, not the albedo (the highlight term adds `1 - albedo`, which a dimmed albedo would brighten). The
**outline pass reads the same masks** (`outline.gdshader`: the line's floor is as lit as the ground under it, so no line shows in the unseen house). **A thing that moves** is marked `MeshNodes.moving(node, true)` (every part under it; a batch once): the shader discards its pixels where the cone does not show them, so it is
drawn only inside the cone, cut at its edge. The mirror marks and hides bodies on `ViewLayers.MOVING` itself (`mirror_sight.gd`, `MirrorVisionConfig`); a batch of short-lived moving things (bullets, bits) is marked where it is made. A part added later under a marked node takes its parent's mark. A new mesh needs nothing for the vision unless it is a batch of moving things.

**Seen first** (`MirrorVisionConfig.seen_first`, groups): a body of a listed group (a character, a vehicle, a dropped item) is hidden by the carrier until the cone has first reached it (`SeenArea.active()` and `reaches`), then marked seen until it moves outside the cone (a thing that rests out of view must be reached again); the static world is not held back. Projectile's `ShotLayer` does the same for a casing. A test of either sets `SeenArea.set_area` by hand.

