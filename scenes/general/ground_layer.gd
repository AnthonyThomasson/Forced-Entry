class_name GroundLayer
extends CanvasLayer
## General domain: the flat overlays of the 3D render mode (#193, interface 27). The 2D world is
## hidden in 3D mode, and a hidden `CanvasItem` draws nothing, so the player's view (its cone mask
## and memory composite) and every debug overlay would vanish with it. Each of them says what it is
## (`ViewLayers.overlay`, the view's composite), and while the 3D view is on (`enabled`) it is moved
## under a `GroundLayer`: a `CanvasLayer` is not a `CanvasItem`, so the hidden world does not hide
## what is under it, and it draws over the 3D view and under the HUD.
##
## The layer's `transform` is `Pointer.screen_transform` each frame, the exact ground-to-screen
## affine of the 3D camera, so a world point the overlay draws lands on the same screen point as the
## 3D floor under it, at any camera yaw.
##
## There is ONE layer for all the match's debug overlays (`overlays`, made by the 3D view with
## `shared`), not one per NPC: each overlay is moved under it and the layer puts it back on its
## owner, the node it was a child of, every frame (an overlay draws from its owner's origin and
## turns with it, as in 2D), frees it when the owner leaves the tree, and answers which overlays an
## owner has (`overlays_of`). The view's composite, one to a match, sits under a layer of its own
## beside it (`VISION`), which dies with the view.

## The name of the layer the view's composite sits on, under its view.
const VISION := &"GroundVision"

## Whether the 3D view is on: Main sets it with the view, and while it is off `adopt` does nothing,
## so the 2D render is as it was.
static var enabled := false
## The match's one layer for the debug overlays, made by the 3D view (`shared`); null before and
## after it. Untyped so a freed one is checked, not read.
static var overlays: Variant = null

## The overlays this layer holds, per owner: the owner's instance id -> a plain `Node` holding that
## owner's overlays under their own names (two owners both have a `VisionDebug`).
var _held := {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After the camera rig (50) and the player's view (100), so it follows this frame's camera.
	process_priority = 110


func _process(_delta: float) -> void:
	# A layer left behind by a view that has ended has no 3D camera to follow.
	if not Pointer.is_3d(self):
		return
	transform = Pointer.screen_transform(self)
	for id: int in _held.keys():
		var home: Variant = instance_from_id(id)
		if not home is Node2D:
			continue
		var pose: Transform2D = (home as Node2D).global_transform
		for item: Node in (_held[id] as Node).get_children():
			if item is Node2D and (item as Node2D).transform != pose:
				(item as Node2D).transform = pose


## The match's overlay layer, on `RenderConfig.overlay_layer`: the 3D view adds it as its child and
## sets `enabled`; the view's `_exit_tree` calls `forget`.
static func shared() -> GroundLayer:
	var made := GroundLayer.new()
	made.layer = RenderConfig.overlay_layer
	made.name = &"GroundOverlays"
	overlays = made
	return made


## Forget the shared layer (the view is leaving; the layer goes with it).
static func forget() -> void:
	overlays = null


## Move `item`, an overlay or the view's composite, under a ground layer in the 3D render mode
## (`enabled`); in 2D this does nothing. It waits for the item to be in the tree and for the
## frame's tree changes to end, so it may be asked from an `_init`, a `_ready` or a parent still
## adding its children. An overlay (any layer but `RenderConfig.vision_layer`) goes under the
## shared layer, with its parent as its owner; the composite under a `VISION` layer beside it.
static func adopt(item: CanvasItem, canvas_layer: int) -> void:
	if not enabled:
		return
	if not item.is_inside_tree():
		item.tree_entered.connect(adopt.bind(item, canvas_layer), CONNECT_ONE_SHOT)
		return
	_move.bind(item, canvas_layer).call_deferred()


## The overlays of `home` that were moved under the shared layer (none in 2D).
static func overlays_of(home: Node) -> Array:
	if not is_instance_valid(overlays):
		return []
	var held: Node = (overlays as GroundLayer)._held.get(home.get_instance_id())
	return [] if held == null else held.get_children()


## The deferred half of `adopt`: put `item` under its ground layer, its parent being its owner.
static func _move(item: CanvasItem, canvas_layer: int) -> void:
	if not is_instance_valid(item) or not item.is_inside_tree() or item.is_queued_for_deletion():
		return
	var parent := item.get_parent()
	if parent is GroundLayer:
		return
	if canvas_layer == RenderConfig.vision_layer:
		var holder := parent.get_node_or_null(NodePath(VISION)) as GroundLayer
		if holder == null:
			holder = GroundLayer.new()
			holder.name = VISION
			holder.layer = canvas_layer
			parent.add_child(holder)
		item.reparent(holder, false)
	elif is_instance_valid(overlays):
		(overlays as GroundLayer)._take(item, parent)


## Hold `item`, moved under this layer, for `home`: it follows its pose and goes when it leaves.
func _take(item: CanvasItem, home: Node) -> void:
	var id := home.get_instance_id()
	if not _held.has(id):
		var held := Node.new()
		held.name = "For%d" % id
		add_child(held)
		_held[id] = held
		home.tree_exiting.connect(_release.bind(id), CONNECT_ONE_SHOT)
	item.reparent(_held[id], false)


## `home` left the tree: its overlays go with it, as when they were its children.
func _release(id: int) -> void:
	var held: Node = _held.get(id)
	if held != null:
		held.queue_free()
	_held.erase(id)
