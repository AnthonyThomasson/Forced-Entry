class_name ViewLayers
## General domain: the visibility bits (`CanvasItem.visibility_layer`) that say what the player's
## view may remember, shared read-only infrastructure like `DrawLayers`. The Vision domain's capture
## leaves `MOVING` and `OVERLAY` out of its cull mask (`Viewport.canvas_cull_mask`), so what it
## paints into the memory is the world as it stands, without anything that moves and without the
## overlays; the main viewport draws every bit.

## What stays where it is: the house, its floors, walls and furniture, and what has come to rest.
## Godot's default, so an item that sets nothing is remembered.
const WORLD := 1
## What moves and is not remembered: the living, bullets, grenades in flight, hit particles, flying
## debris, an explosion's look and a flash's light. Drawn only inside the cone.
const MOVING := 2
## The debug overlays and the markers, which are drawn over the view and never remembered.
const OVERLAY := 4
