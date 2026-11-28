class_name ViewLayers
## General domain: the visibility bits (`CanvasItem.visibility_layer`) that say what the player's
## view hides while it moves outside the cone, and the hook that makes a node a debug overlay.
## Shared read-only infrastructure like `PhysicsLayers`. Art's `MeshCarrier` and `MeshFollower` read
## `MOVING` off a 2D node to hide its mesh outside the cone (`docs/player-vision.md`).

## What stays where it is: the house, its floors, walls and furniture, and what has come to rest.
## Godot's default, so an item that sets nothing is remembered.
const WORLD := 1
## What moves and is not remembered: the living, bullets, grenades in flight, hit particles, flying
## debris, an explosion's look and a flash's light. Shown only inside the cone.
const MOVING := 2
## A user signal `set_moving` emits when it changed an item's layer, on an item that has it (a
## watcher adds it: `Node.add_user_signal`): Godot says nothing of a layer written.
const CHANGED := &"view_layer_changed"


## Make `item` an overlay: a debug overlay or marker that draws flat on the ground over the 3D
## view, in its own colours (`GroundLayer` moves it under the view's overlay layer and has it
## follow its owner), never touched by the player's view. A world with no 3D view leaves it where
## it is.
static func overlay(item: CanvasItem) -> void:
	GroundLayer.adopt(item)


## Put `item` on `MOVING` (it moves: drawn only inside the cone) or back on `WORLD` (it is at rest:
## the view remembers it). The layer is written only when it changes, so a caller may ask every
## frame. The layer is written only here (a watcher hears of it by `CHANGED`).
static func set_moving(item: CanvasItem, moving: bool) -> void:
	var layer := MOVING if moving else WORLD
	if item.visibility_layer != layer:
		item.visibility_layer = layer
		if item.has_user_signal(CHANGED):
			item.emit_signal(CHANGED)
