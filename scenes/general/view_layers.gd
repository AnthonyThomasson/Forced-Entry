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
## The debug overlays and the markers, which are drawn over the view and never remembered. The
## view's composite sits on this bit too, so the capture does not draw it.
const OVERLAY := 4


## Make `item` an overlay: drawn at `DrawLayers.OVERLAY` whatever its parent's z (absolute, so over
## the player's view at `DrawLayers.VISION`) and on `OVERLAY`, which the view's capture leaves out,
## so it is never remembered.
static func overlay(item: CanvasItem) -> void:
	item.z_index = DrawLayers.OVERLAY
	item.z_as_relative = false
	item.visibility_layer = OVERLAY


## Put `item` on `MOVING` (it moves: drawn only inside the cone) or back on `WORLD` (it is at rest:
## the view remembers it). The layer is written only when it changes, so a caller may ask every
## frame.
static func set_moving(item: CanvasItem, moving: bool) -> void:
	var layer := MOVING if moving else WORLD
	if item.visibility_layer != layer:
		item.visibility_layer = layer
