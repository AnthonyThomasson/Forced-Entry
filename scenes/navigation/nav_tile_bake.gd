class_name NavTileBake extends RefCounted
## Navigation domain: one steering tile's bake in flight (`NavTiles.prepare`): the tile, the polygon
## it is baked into, the walls and holes it is baked from, and the pool task that bakes it. The
## main thread owns this record and its `task`; the worker is handed only the values it works on
## (`run`'s arguments), never the record, so nothing the main thread writes while the bake runs is
## something the worker reads. A record is read again (`poly`) only after `NavTiles.land` joined
## the task.

## The tile the polygon is for.
var tile: NavigationRegion3D
## The polygon the bake fills in (baked into on the worker, then the tile's).
var poly: NavigationPolygon
## The wall outlines and the footprints of the furniture and characters it is baked from, kept on
## the tile when it lands.
var walls: Dictionary = {}
var holes: Array = []
## The source geometry the bake reads (the holes are added to it by the bake) and the house's
## position, the bake's frame.
var source: NavigationMeshSourceGeometryData2D
var origin := Vector2.ZERO
## The tile's rect (`NavTiles.RECT_META`), what the worker reads the border's seams in, and the
## seams it read (`NavSeams.read`; {} until the bake has run, joined).
var rect := Rect2()
var seams: Dictionary = {}
## What the worker is handed to read the seams: `{ rect, read }`, it sets `read` once (a record it
## alone writes, the main thread reads it after the join).
var _seam := { "rect": Rect2(), "read": {} }
## The `WorkerThreadPool` task baking it, -1 when none is (never started, or joined).
var task := -1


## Add `holes` to `source`, bake `poly` from it and read its border's seams (`NavSeams.read`, into
## `made`): the work of a worker thread, which reads nothing but these values (the tile, the tree
## and the record are the main thread's).
static func run(
	geometry: NavigationMeshSourceGeometryData2D,
	frame: Vector2,
	footprints: Array,
	nav_poly: NavigationPolygon,
	seam: Dictionary,
) -> void:
	NavSource.add_holes(geometry, frame, footprints)
	NavSource.bake_polygon(nav_poly, geometry, frame)
	seam["read"] = NavSeams.read(nav_poly, seam["rect"])


## Bake on the calling thread.
func run_here() -> void:
	_seam["rect"] = rect
	run(source, origin, holes, poly, _seam)
	seams = _seam["read"]


## Start the bake on the worker pool, handing it the values only.
func start() -> void:
	var geometry := source
	var frame := origin
	var footprints := holes
	var nav_poly := poly
	var seam := _seam
	seam["rect"] = rect
	task = WorkerThreadPool.add_task(
		func() -> void: run(geometry, frame, footprints, nav_poly, seam), true, "nav tile bake")


## Wait for the bake when it is still running (true when it was), then forget the task: the record
## is the main thread's again.
func join() -> bool:
	if task < 0:
		return false
	var late := not WorkerThreadPool.is_task_completed(task)
	WorkerThreadPool.wait_for_task_completion(task)
	task = -1
	seams = _seam["read"]
	return late
