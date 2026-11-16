# The vision hook (side file of `domain-art`)

The player's view in 3D (`docs/player-vision.md` V12; `ToonMask`, `toon_vision.gdshaderinc`, `toon.gdshader`, `decal.gdshader`).

Global shader uniforms, declared by `ToonMaterial.make()` / `ToonMaterial.decal()` through `ToonMask.install()`: `vision_mask` (the live cone: a texture's red channel, 1 seen, 0 not) with `vision_mask_xf` (world `(x, z)` in 3D units to its uv),
`vision_unseen` (the brightness a spot never seen keeps; **1 by default: everything visible**, whatever the masks hold), `vision_memory` with `vision_memory_xf` (where the player has ever seen: nothing until `set_memory`) and `vision_look` / `vision_tint`
(grey amount and brightness, and the tint, of the remembered look). `ToonMask.set_mask(texture, world_rect_px, unseen_brightness)`, `move_mask(world_rect_px)`, `set_memory(texture, world_rect_px, grey, brightness, tint)`, `clear()`, `mask_active()`,
`mask_world_rect()`, `memory_world_rect()` are the whole interface; Vision's `ViewGround` is the one caller. The masks are read only while `vision_unseen` is below 1 (a uniform branch: the default costs nothing). A spot in the cone is lit as it is; one only remembered keeps `vision_look.y` of its
light and its albedo is greyed and tinted (`toon_remember`: the current world in a dimmer, greyer look, not a picture of it); one never seen keeps `vision_unseen` (0: black). It scales the light, not the albedo (the highlight term adds `1 - albedo`, which a dimmed albedo would brighten). The
**outline pass reads the same masks** (`outline.gdshader`: the line's floor is as lit as the ground under it, so no line shows in the unseen house). **A thing that moves** is marked `MeshNodes.moving(node, true)` (every part under it; a batch once): the shader discards its pixels where the cone does not show them, so it is
drawn only inside the cone, cut at its edge. The mirror marks and hides bodies on `ViewLayers.MOVING` itself (`world_mirror.gd`, `MirrorVisionConfig`); a batch of short-lived moving things (bullets, bits) is marked where it is made. A new mesh needs nothing for the vision unless it is a batch of moving things.

