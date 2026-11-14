class_name GroundLayer
extends CanvasLayer
## General domain: the flat overlays of the 3D render mode (#193, interface 27). The 2D world is
## hidden in 3D mode, and a hidden `CanvasItem` draws nothing, so the player's view (its cone mask
## and memory composite) and every debug overlay would vanish with it. Each of them says what it is
## (`ViewLayers.overlay`, the view's composite), and while the 3D view is on (`enabled`) it is
## moved under a `GroundLayer` made beside it: a `CanvasLayer` is not a `CanvasItem`, so the hidden
## world does not hide what is under it, and it draws over the 3D view and under the HUD.
##
## The layer's `transform` is `Pointer.screen_transform` each frame, the exact ground-to-screen
## affine of the 3D camera, so a world point the overlay draws lands on the same screen point as the
## 3D floor under it, at any camera yaw. The overlay keeps its place in the tree one step down (its
## parent holds the layer, named `NAME` or `VISION`), so it still lives and dies with its owner and
## its owner's code still finds it through `OverlayRegistry` (the child, or the layer's child).
## A `CanvasLayer` stops the parent's transform, so the layer puts its overlays back on their owner
## each frame (`_follow`): an overlay draws from its owner's origin and turns with it, as in 2D.

## The layer node's name under an overlay's parent, and the one the view's composite sits on.
const NAME := &"GroundOverlays"
const VISION := &"GroundVision"

## Whether the 3D view is on: Main sets it with the view, and while it is off `adopt` does nothing,
## so the 2D render is as it was.
static var enabled := false

## The 2D node the layer sits under: its overlays take that node's global transform every frame.
var _follow: Node2D


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After the camera rig (50) and the player's view (100), so it follows this frame's camera.
	process_priority = 110


func _process(_delta: float) -> void:
	# A layer left behind by a view that has ended has no 3D camera to follow.
	if not Pointer.is_3d(self):
		return
	transform = Pointer.screen_transform(self)
	if _follow == null or not is_instance_valid(_follow):
		return
	for child in get_children():
		if child is Node2D:
			(child as Node2D).global_transform = _follow.global_transform


## Move `item`, an overlay or the view's composite, under a `GroundLayer` on canvas layer `layer`
## beside it, in the 3D render mode (`enabled`); in 2D this does nothing. It waits for the item to
## be in the tree and for the frame's tree changes to end, so it may be asked from an `_init`, a
## `_ready` or a parent still adding its children.
static func adopt(item: CanvasItem, canvas_layer: int) -> void:
	if not enabled:
		return
	if not item.is_inside_tree():
		item.tree_entered.connect(adopt.bind(item, canvas_layer), CONNECT_ONE_SHOT)
		return
	_move.bind(item, canvas_layer).call_deferred()


## The `GroundLayer` under `item`'s parent for `canvas_layer` (made when there is none) and `item`
## in it.
static func _move(item: CanvasItem, canvas_layer: int) -> void:
	if not is_instance_valid(item) or not item.is_inside_tree() or item.is_queued_for_deletion():
		return
	var parent := item.get_parent()
	if parent is GroundLayer:
		return
	var holder_name := VISION if canvas_layer == RenderConfig.vision_layer else NAME
	var holder := parent.get_node_or_null(NodePath(holder_name)) as GroundLayer
	if holder == null:
		holder = GroundLayer.new()
		holder.name = holder_name
		holder.layer = canvas_layer
		holder._follow = parent as Node2D
		parent.add_child(holder)
	item.reparent(holder, false)
