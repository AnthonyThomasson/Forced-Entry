class_name GroundLayer
extends CanvasLayer
## General domain: the flat overlays of the 3D render (interface 27). The 2D world is hidden
## under the 3D view, and a hidden `CanvasItem` draws nothing, so every debug overlay would vanish
## with it. Each says what it is (`ViewLayers.overlay`), and while the 3D view is up it is moved
## under a `GroundLayer`: a `CanvasLayer` is not a `CanvasItem`, so the hidden world does not hide
## what is under it, and it draws over the 3D view and under the HUD. A world with no 3D view (a
## headless test world) has no layer: its overlays stay where they were made (and wait in `WAITING`,
## for a layer made later).
##
## The layer's `transform` is `Pointer.screen_transform` each frame, the exact ground-to-screen
## affine of the 3D camera, so a world point the overlay draws lands on the same screen point as the
## 3D floor under it, at any camera yaw.
##
## There is ONE layer for all the match's debug overlays (`overlays`, made by the 3D view with
## `shared`), not one per NPC: each overlay is moved under it, beside its owner's others in one
## holder, and the layer puts the holder on its owner, the node they were children of, every frame
## (an overlay draws from its owner's origin and turns with it, as in 2D; one write moves all of an
## owner's, since a match holds hundreds), frees them when the owner leaves the tree, and answers
## which overlays an owner has (`overlays_of`). The player's view is not one of them in 3D: it is
## two masks the toon shaders read (`ViewGround`), so nothing of it is drawn flat.

## The group an overlay made while no layer stood waits in (a test world's build makes its overlays
## before the session builds the 3D view); `shared` adopts the group when the layer is made.
const WAITING := &"ground_overlay_waiting"

## The match's one layer for the debug overlays, made by the 3D view (`shared`); null before and
## after it. Untyped so a freed one is checked, not read.
static var overlays: Variant = null

## The overlays this layer holds, per owner: the owner's instance id -> a `Node2D` holding that
## owner's overlays under their own names (two owners both have a `VisionDebug`), standing where
## the owner does.
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
		var held: Node2D = _held[id]
		if held.transform != pose:
			held.transform = pose


## The match's overlay layer, on `RenderConfig.overlay_layer`: the 3D view adds it as its child; the
## view's `_exit_tree` calls `forget`.
static func shared() -> GroundLayer:
	var made := GroundLayer.new()
	made.layer = RenderConfig.overlay_layer
	made.name = &"GroundOverlays"
	overlays = made
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for waiting: Node in tree.get_nodes_in_group(WAITING):
			if waiting is CanvasItem:
				adopt(waiting)
	return made


## Forget the shared layer (the view is leaving; the layer goes with it).
static func forget() -> void:
	overlays = null


## Move `item`, a debug overlay, under the ground layer of the 3D view (a world with none leaves it
## where it is). It waits for the item to be in the tree and for the
## frame's tree changes to end, so it may be asked from an `_init`, a `_ready` or a parent still
## adding its children. It goes under the shared layer, with its parent as its owner.
static func adopt(item: CanvasItem) -> void:
	if not is_instance_valid(overlays):
		# no layer yet: wait for it (`shared` adopts what waits)
		item.add_to_group(WAITING)
		return
	if not item.is_inside_tree():
		item.tree_entered.connect(adopt.bind(item), CONNECT_ONE_SHOT)
		return
	_move.bind(item).call_deferred()


## The overlays of `home` that were moved under the shared layer (none without a 3D view).
static func overlays_of(home: Node) -> Array:
	if not is_instance_valid(overlays):
		return []
	var held: Node = (overlays as GroundLayer)._held.get(home.get_instance_id())
	return [] if held == null else held.get_children()


## The deferred half of `adopt`: put `item` under its ground layer, its parent being its owner.
static func _move(item: CanvasItem) -> void:
	if not is_instance_valid(item) or not item.is_inside_tree() or item.is_queued_for_deletion():
		return
	item.remove_from_group(WAITING)
	var parent := item.get_parent()
	if parent is GroundLayer:
		return
	if is_instance_valid(overlays):
		(overlays as GroundLayer)._take(item, parent)


## Hold `item`, moved under this layer, for `home`: it follows its pose and goes when it leaves.
func _take(item: CanvasItem, home: Node) -> void:
	var id := home.get_instance_id()
	if not _held.has(id):
		var held := Node2D.new()
		held.name = "For%d" % id
		if home is Node2D:
			held.transform = (home as Node2D).global_transform
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
