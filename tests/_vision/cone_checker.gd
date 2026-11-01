extends Node
## Test helper (not a test) for `vision/cone_skip_exact`: every physics frame, after the view has
## settled its cone (the view runs at priority 100, this at 200), it builds a fresh cone from the
## viewer's place by the reference algorithm (`reference_view_cone.gd`, which keeps nothing from
## one frame to the next) in the same physics space, and compares it vertex for vertex with the
## polygon the view holds. A frame the view skipped must still hold the fresh cone. It also counts
## the view's rebuilds (`PlayerView.rebuilds()`) and the longest run of frames between two.

const Reference := preload("res://tests/_vision/reference_view_cone.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
## The most differences kept for the report.
const KEPT := 6

## The view and the character it is of.
var view: PlayerView
var viewer: Node2D
## Frames compared, frames the view rebuilt in, frames its polygon differed from the last frame's.
var frames := 0
var rebuilt := 0
var changed := 0
## The most frames in a row the view held its polygon without a rebuild.
var longest_wait := 0
## Frames the view's polygon differed from the fresh cone's: `"frame N: what"`.
var mismatches: Array[String] = []
var _plain := Reference.new()
var _last_count := -1
var _waited := 0
var _last_cone := PackedVector2Array()
var _last_bubble := PackedVector2Array()


func _init(of_view: PlayerView, of_viewer: Node2D) -> void:
	view = of_view
	viewer = of_viewer
	process_physics_priority = 200


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(view) or not is_instance_valid(viewer):
		return
	frames += 1
	var count := view.rebuilds()
	if _last_count >= 0:
		if count != _last_count:
			rebuilt += 1
			_waited = 0
		else:
			_waited += 1
			longest_wait = maxi(longest_wait, _waited)
	_last_count = count
	if view.cone() != _last_cone or view.bubble() != _last_bubble:
		changed += 1
	_last_cone = view.cone()
	_last_bubble = view.bubble()
	_plain.rebuild(
		viewer.get_world_2d().direct_space_state,
		viewer.global_position,
		viewer.get("facing"),
		[viewer.get_rid()],
		viewer.sight(),
	)
	var reason := _difference()
	if reason != "" and mismatches.size() < KEPT:
		mismatches.append("frame %d (rebuilds %d): %s" % [frames, count, reason])
	elif reason != "":
		mismatches.append("")


## Why the view's polygons differ from the fresh cone's, or "" when they are the same.
func _difference() -> String:
	return Probe.polygons_differ(view.cone(), view.bubble(), _plain.cone, _plain.bubble)


## The number of frames the view's polygon differed from the fresh cone's.
func wrong() -> int:
	return mismatches.size()


## The differences kept, for a failure message.
func report() -> String:
	return "; ".join(mismatches.filter(func(m: String) -> bool: return m != ""))
