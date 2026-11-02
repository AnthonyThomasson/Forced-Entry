class_name NavSnaps extends RefCounted
## Navigation domain: what `NavBuilder.snap` has learned. The server scans every polygon of a map
## for the closest point to a point, and a decision's snapshot snaps the same room centres and spots
## again for each NPC, so an answer stands while the map's iteration does (the same answer the
## server gives; a re-bake starts the answers afresh).

## Most answers kept per map before they are dropped to start afresh.
const KEPT := 4096
## Most maps whose answers are kept.
const MAPS_KEPT := 32

## Per map: { iteration (the map's when they were asked), points: { point: answer } }.
static var _answers: Dictionary = {}


## `p` snapped onto `map`, from what was learned of it if it was asked again.
static func closest(map: RID, p: Vector2) -> Vector2:
	var iteration := NavigationServer2D.map_get_iteration_id(map)
	var kept: Dictionary = _answers.get(map, {})
	if kept.get("iteration", -1) != iteration or (kept["points"] as Dictionary).size() >= KEPT:
		if _answers.size() > MAPS_KEPT:
			_answers.clear()  # maps come and go with the worlds: start afresh
		kept = { "iteration": iteration, "points": {} }
		_answers[map] = kept
	var points: Dictionary = kept["points"]
	if points.has(p):
		return points[p]
	var answer := NavigationServer2D.map_get_closest_point(map, p)
	points[p] = answer
	return answer


## Forget what was learned of `map` (it was freed).
static func forget(map: RID) -> void:
	_answers.erase(map)
