class_name PlayerView
extends Node2D
## The Vision domain's one node: what one character sees, drawn for the player
## (`docs/player-vision.md`), a leaf like Lighting. The match builder builds it through
## `watch(root, viewer)` for Main's human and the Testing world's viewer (interface 25); it reads
## the viewer only duck-typed (`facing`, `global_position`, `get_rid()`, `sight()`, `is_dead`, and
## its `died` and `tree_exiting` signals, on which the view lifts) and imports nothing but General.
##
## Each physics frame, after its viewer has moved and turned, it builds the exact polygon of the
## viewer's sight (`ViewCone`): the cone round its facing and the bubble round its eye, bounded by
## the walls and tall pieces `SightRay` says break the line.

const GROUP := &"player_view"
const Cone := preload("res://scenes/vision/view_cone.gd")
const Memory := preload("res://scenes/vision/view_memory.gd")
const Mask := preload("res://scenes/vision/view_mask.gd")
const Composite := preload("res://scenes/vision/view_composite.gd")
const Watch := preload("res://scenes/vision/view_watch.gd")
const Pipeline := preload("res://scenes/vision/view_pipeline.gd")
## It runs after the characters it watches (their default priority is 0).
const PRIORITY := 100

## The character whose sight this is.
var _viewer: Node2D
var _cone := Cone.new()
var _memory := Memory.new()
var _mask := Mask.new()
var _composite := Composite.new()
var _watch := Watch.new()
## The cone's jobs: starts, slices, restarts and publishes.
var _pipeline := Pipeline.new(_cone, _watch)


func _enter_tree() -> void:
	add_to_group(GROUP)
	process_physics_priority = PRIORITY


func _exit_tree() -> void:
	_watch.detach()
	SeenArea.clear()


## A view whose node is disabled works no more, so it shows the whole world again.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED:
		_pipeline.drop()
		SeenArea.clear()


func _ready() -> void:
	var main := get_viewport()
	_memory.name = "Memory"
	_mask.name = "Mask"
	add_child(_memory)
	add_child(_mask)
	_watch.attach(get_tree(), [_viewer.get_rid()])
	_memory.build(_floor_bounds(), VisionConfig.memory_scale, main)
	_mask.build(main, VisionConfig.feather)
	_composite.build(
		_memory.memory.get_texture(),
		_mask.mask.get_texture(),
		_memory.bounds,
		_memory.scale,
		_memory.memory.size,
	)
	add_child(_composite)
	process_priority = PRIORITY


func _process(_delta: float) -> void:
	if not is_instance_valid(_viewer):
		return
	var main := get_viewport()
	var cam := Pointer.screen_transform(self)
	var size := Vector2i(main.get_visible_rect().size).max(Vector2i.ONE)
	_memory.follow(cam, size)
	_mask.follow(cam, size)
	_composite.follow(cam, size)
	_memory.paint(_cone.cone, _cone.bubble, _cone.eye, cam)
	_mask.paint(_cone.cone, _cone.bubble, _cone.eye)


func _physics_process(_delta: float) -> void:
	# A lifted view is queued for deletion but still ticks this frame: it builds and writes nothing.
	if not is_instance_valid(_viewer) or is_queued_for_deletion():
		return
	var eye := _viewer.global_position
	var facing: Vector2 = _viewer.get("facing")
	var sight: Dictionary = _viewer.sight()
	# One slice of the cone's job (`ViewPipeline`): held while nothing the polygon is made of has
	# changed, published when a job completes.
	var space := get_world_2d().direct_space_state
	if _pipeline.tick(space, eye, facing, [_viewer.get_rid()], sight):
		_publish_area()


## Build the view of `character` (any one: the viewer) under `root`; null while
## `VisionConfig.enabled` is off and for a character already dead (no view of the dead).
static func watch(root: Node, character: Node2D) -> PlayerView:
	if not VisionConfig.enabled or character.get("is_dead"):
		return null
	var view := PlayerView.new()
	view.name = "PlayerView"
	view._viewer = character
	if character.has_signal(&"died"):
		character.connect(&"died", view._lift)
	# A viewer freed or taken out of the tree is not there to see by: the view lifts as on death.
	character.tree_exiting.connect(view._lift)
	root.add_child(view)
	return view


## The viewer died or left the tree: the view is lifted for good, so the whole world is drawn again,
## live. The view, its composite and its viewports are freed at the end of this frame, before it is
## drawn.
func _lift() -> void:
	# At once, so what is drawn this frame already repaints everything that was held back; a job
	# half done is dropped with the view.
	_pipeline.drop()
	SeenArea.clear()
	queue_free()


## The character this view was built for.
func viewer() -> Node2D:
	return _viewer


## The cone polygon: the eye, then one corner per ray from the left edge to the right (empty while
## the viewer has no facing).
func cone() -> PackedVector2Array:
	return _cone.cone


## How many cones have been published: a job that ran to its end (or a whole rebuild).
func rebuilds() -> int:
	return _pipeline.published


## How many rebuilds have been started: a job begun, a restart after a change of the world and a
## whole build each count.
func starts() -> int:
	return _pipeline.started


## What the cone's pipeline has spent, running totals (a perf probe's read, interface 25):
## `restarts`, whole builds by cause (`first`, `jump`, `cap`) and `units` of engine work stepped.
func rebuild_causes() -> Dictionary:
	return _pipeline.causes.duplicate()


## Whether a rebuild is in flight: the cone published is older than the world and the viewer.
func building() -> bool:
	return _pipeline.running()


## The pose the published cone is of: `{eye, facing}`, the eye and facing the viewer had when the
## job that built it started (zero before the first cone).
func published_pose() -> Dictionary:
	return { "eye": _pipeline.pose_eye, "facing": _pipeline.pose_facing }


## How many rays the last rebuild cast to learn which corners the eye sees.
func corner_rays() -> int:
	return _cone.corner_rays


## How many corners the last rebuild read from the shapes about the eye.
func corners_read() -> int:
	return _cone.corners_read


## The near bubble's polygon round the eye, bounded by the line of sight.
func bubble() -> PackedVector2Array:
	return _cone.bubble


## Whether `point` is in the cone or the bubble.
func sees(point: Vector2) -> bool:
	return _cone.contains(point)


## The memory: a world-space SubViewport over the floors' bounds, never cleared.
func memory() -> SubViewport:
	return _memory.memory


## The capture: the world as drawn without what moves and without the overlays.
func capture() -> SubViewport:
	return _memory.capture


## The mask: the cone as a screen-sized picture, its edge feathered.
func mask() -> SubViewport:
	return _mask.mask


## The memory's painter, which paints the cone from the capture.
func painter() -> Node2D:
	return _memory.painter


## The mask's painter.
func mask_painter() -> Node2D:
	return _mask.painter


## The composite drawn over the world, at `DrawLayers.VISION`.
func composite() -> Node2D:
	return _composite


## The memory's texels per world px (below the configured one when the world is too big).
func memory_scale() -> float:
	return _memory.scale


## Whether the memory is still being emptied (it starts empty).
func wiping() -> bool:
	return _memory.wiping()


## Tell General what the cone shows live (`SeenArea`), so what is drawn only while seen can skip
## its repaint while it wholly is not.
func _publish_area() -> void:
	var polygons: Array = []
	var bounds := Rect2(_cone.eye, Vector2.ZERO)
	for polygon: PackedVector2Array in [_cone.cone, _cone.bubble]:
		if polygon.size() < 3:
			continue
		polygons.append(polygon)
		for corner in polygon:
			bounds = bounds.expand(corner)
	SeenArea.set_area(polygons, bounds)


## The bounds of the world's floors (the group `floors`: `size`, `global_position`), the part of the
## world there is to remember; empty with none.
func _floor_bounds() -> Rect2:
	var found := Rect2()
	var first := true
	for ground: Node2D in get_tree().get_nodes_in_group(&"floors"):
		if not get_parent().is_ancestor_of(ground):
			continue
		var rect := Rect2(ground.global_position, ground.get("size"))
		found = rect if first else found.merge(rect)
		first = false
	return found
