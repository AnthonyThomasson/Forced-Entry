# The player's view: the two masks (side file of `domain-vision`)

Spec: `docs/player-vision.md` V12.

`ViewGround` (built by `PlayerView._ready`) holds two
  transparent `SubViewport`s drawn on request (`UPDATE_ONCE`), never every frame: the **live** window (a square of the world about the camera,
  `live_side` texels, the cone feathered by a disc of 32 shifted copies, laid again when the camera drifts out of it or the zoom
  steps: `follow` each `_process`) and the **seen** one (the floors' bounds, never cleared, the cone added on each publish). `publish` (called
  where `SeenArea.set_area` is) draws both unless the cone is the one already drawn (the backstop republishes unchanged cones); `ToonMask.set_mask` /
  `set_memory` switch the shaders' globals on `settle_frames` later and `suspend()` (a lift, a disabled view) clears them. The shaders do the rest
  (`domain-art`: `toon_vision.gdshaderinc`; the carrier hides what moves out of the cone, `MirrorVisionConfig`). `live_side` is fixed, so a texel covers more world px zoomed out (a coarser feather there); `PlayerView.ground` is the node (`counts` says how often each draw was asked). Nothing photographs
  the world.

A new moving thing: its sim node is on `ViewLayers.MOVING` and the carrier hides it outside the cone and marks its mesh (`MeshNodes.moving`);
a batch (bullets, bits) is marked once where it is made. See V12 for the one limit (debris chips).

