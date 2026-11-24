extends Node
## Test helper (not a test) for the cone tests: every physics frame, after the view has stepped its
## job (the view runs at priority 100, this at 200), it holds the view's polygon to the plainest
## cone there is. In a frame the view published a cone, it builds a fresh one by the reference
## algorithm (`reference_view_cone.gd`, which keeps nothing from one frame to the next) in the same
## physics space from the pose the view says the cone is of (`PlayerView.published_pose()`: the
## viewer's pose when the job started, `docs/player-vision.md` V1) and compares it with the
## polygon the view holds, vertex for vertex. In a frame it published none, the polygon must be the
## one it held the frame before: a half-built cone is never shown. And once the view is settled (no
## job in flight or started and its cone of the viewer's pose, for two frames) its cone is the
## reference cone of the viewer's live pose in every frame. It also counts the view's
## publishes (`PlayerView.rebuilds()`), its job starts (`starts()`) and the longest run of frames
## between two starts, and keeps the ages of the cone in `age` (`cone_age.gd`).

const Reference := preload("res://tests/_vision/reference_view_cone.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
const Age := preload("res://tests/_vision/cone_age.gd")
## The most differences kept for the report.
const KEPT := 6
## The most area (px^2) a cone may differ from the live world's by while a blocker in reach creeps:
## a sliver 0.0004 rad wide at 500 px is 0.2 px by 160 px. The measured worst is 12.6 px^2.
const SLIVER := 20.0
## The frames a view is settled before its cone is held to the live pose's reference.
const SETTLED := 2

## The view and the character it is of.
var view: PlayerView
var viewer: Node2D
## Frames compared, frames its polygon differed from the last frame's.
var frames := 0
var changed := 0
## Frames the view was settled in (held to the live pose's reference).
var settled := 0
## The most frames in a row the view started no job (the backstop's bound).
var longest_wait := 0
## The cone's age, frame by frame.
var age := Age.new()
## Frames the view's polygon was not what it should be: `"frame N: what"`.
var mismatches: Array[String] = []
var _plain := Reference.new()
var _last_published := -1
var _last_starts := -1
var _waited := 0
var _settled_run := 0
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
	var published_now := _last_published >= 0 and count != _last_published
	var pose := view.published_pose()
	age.frame(viewer.global_position, viewer.get("facing"), pose, view.cone(), published_now)
	_count_wait()
	var differs := view.cone() != _last_cone or view.bubble() != _last_bubble
	if differs:
		changed += 1
	var reason := ""
	age.creep_frames += int(view.creeping_in_reach() > 0)
	if published_now:
		reason = _reference_differs(pose)
	elif differs and _last_published >= 0:
		reason = "the held cone changed with no publish"
	if reason == "" and _settled(pose):
		settled += 1
		var live := { "eye": viewer.global_position, "facing": viewer.get("facing") }
		reason = _reference_differs(live)
		reason = "settled, the cone is not the live pose's: " + reason if reason != "" else ""
	_last_published = count
	_last_starts = view.starts()
	_last_cone = view.cone()
	_last_bubble = view.bubble()
	if reason != "" and mismatches.size() < KEPT:
		mismatches.append("frame %d (publishes %d): %s" % [frames, count, reason])
	elif reason != "":
		mismatches.append("")


## Whether the view is settled: for `SETTLED` frames running it has had no job in flight and has
## started none, and its cone is of the pose the viewer has now, so it must be the reference cone of
## the live pose (the every-frame exactness of a view with nothing to catch up on).
func _settled(pose: Dictionary) -> bool:
	var at_rest: bool = (
		not view.building()
		and view.starts() == _last_starts
		and pose["eye"] == viewer.global_position
		and pose["facing"] == viewer.get("facing")
	)
	_settled_run = _settled_run + 1 if at_rest else 0
	return _settled_run >= SETTLED


## Why the view's polygons differ from the reference cone of `pose` in the world as it is, or "".
func _reference_differs(pose: Dictionary) -> String:
	_plain.rebuild(
		TwinSpace.space_of(viewer),
		pose["eye"],
		pose["facing"],
		[],
		viewer.sight(),
	)
	var differs := Probe.polygons_differ(view.cone(), view.bubble(), _plain.cone, _plain.bubble)
	if differs != "" and view.creeping_in_reach() > 0:
		return _creep_explains(differs)
	return differs


## The cone is built from the blockers as the job snapshot them, and a blocker that crept under
## `ViewWatch.STILL_PX` since is where it was for the job (the view's bound, held by
## `vision/view_watch_creep_suite`): the reference, built in the live world, may differ from it by
## a sliver where a corner's side ray (0.0002 rad) grazes the creeping blocker and flips between
## hit and miss. Only a creeper in reach of a ray can (`creeping_in_reach`: one behind the viewer
## loosens nothing). Then the two polygons may differ in no more than `SLIVER` px of area; any
## other difference is the view's. The job reads the live space each slice, so no exact check
## against the held snapshot can be built: the sliver bound is the check.
func _creep_explains(differs: String) -> String:
	var area := 0.0
	for pair in [[view.cone(), _plain.cone], [view.bubble(), _plain.bubble]]:
		for piece: PackedVector2Array in Geometry2D.exclude_polygons(pair[0], pair[1]):
			area += absf(_area_of(piece))
	if area <= SLIVER:
		return ""
	return "%s (and %.1f px^2 apart with %d creeping in reach)" % [
		differs,
		area,
		view.creeping_in_reach(),
	]


## The area of a polygon.
static func _area_of(polygon: PackedVector2Array) -> float:
	var twice := 0.0
	for i in polygon.size():
		twice += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return twice * 0.5


## Frames since the view last started a job, and the longest such wait so far.
func _count_wait() -> void:
	if _last_starts < 0:
		return
	_waited = 0 if view.starts() != _last_starts else _waited + 1
	longest_wait = maxi(longest_wait, _waited)


## The number of frames the view's polygon was not what it should be.
func wrong() -> int:
	return mismatches.size()


## The differences kept, for a failure message.
func report() -> String:
	return "; ".join(mismatches.filter(func(m: String) -> bool: return m != ""))
