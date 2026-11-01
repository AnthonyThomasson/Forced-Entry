class_name PlayerView
extends Node2D
## The Vision domain's one node: what one character sees, drawn for the player
## (`docs/player-vision.md`), a leaf like Lighting. The match builder builds it through
## `watch(root, viewer)` for Main's human and the Testing world's viewer (interface 24); it reads
## the viewer only duck-typed (`facing`, `global_position`, `get_rid()`, `sight()`) and imports
## nothing but General.
##
## Each physics frame, after its viewer has moved and turned, it builds the exact polygon of the
## viewer's sight (`ViewCone`): the cone round its facing and the bubble round its eye, bounded by
## the walls and tall pieces `SightRay` says break the line.

const GROUP := &"player_view"
const Cone := preload("res://scenes/vision/view_cone.gd")
## It runs after the characters it watches (their default priority is 0).
const PRIORITY := 100

## The character whose sight this is.
var _viewer: Node2D
var _cone := Cone.new()


func _enter_tree() -> void:
	add_to_group(GROUP)
	process_physics_priority = PRIORITY


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_viewer):
		return
	var space := get_world_2d().direct_space_state
	var facing: Vector2 = _viewer.get("facing")
	_cone.rebuild(space, _viewer.global_position, facing, [_viewer.get_rid()], _viewer.sight())


## Build the view of `viewer` (any character) under `root`; null while `VisionConfig.enabled` is
## off.
static func watch(root: Node, viewer: Node2D) -> PlayerView:
	if not VisionConfig.enabled:
		return null
	var view := PlayerView.new()
	view.name = "PlayerView"
	view._viewer = viewer
	root.add_child(view)
	return view


## The cone polygon: the eye, then one corner per ray from the left edge to the right (empty while
## the viewer has no facing).
func cone() -> PackedVector2Array:
	return _cone.cone


## The near bubble's polygon round the eye, bounded by the line of sight.
func bubble() -> PackedVector2Array:
	return _cone.bubble


## Whether `point` is in the cone or the bubble.
func sees(point: Vector2) -> bool:
	return _cone.contains(point)
