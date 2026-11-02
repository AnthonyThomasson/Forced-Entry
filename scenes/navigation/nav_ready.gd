class_name NavReady extends RefCounted
## Navigation domain: whether a map answers yet. A map synchronizes on a worker thread, a frame or
## more after a region joins it, and at a match's start the world's map is live with the previous
## navmesh (the menu's, the last match's) and takes the new house in only a frame or so later: until
## a region answers a query, a query still answers from the old mesh. `NavBuilder.build` notes each
## region it adds with a probe point, and `NavBuilder.ready` (the one rule every caller uses) is
## true only once each has answered.

## The regions a map has been given but may not have taken in yet (map RID -> Array of
## `{ region: RID, probe: Vector2 }`). An entry leaves when its region answers, or when the region
## leaves the tree.
static var _awaiting: Dictionary = {}


## Whether `map` alone is baked: valid, synchronized at least once, and has taken in every region
## noted for it.
static func taken_in(map: RID) -> bool:
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return false
	var waiting: Array = _awaiting.get(map, [])
	for entry in waiting.duplicate():
		# Asked only after the map's first sync: before it the query is an engine error.
		if NavigationServer2D.map_get_closest_point_owner(map, entry["probe"]) == entry["region"]:
			waiting.erase(entry)
	if waiting.is_empty():
		_awaiting.erase(map)
		return true
	return false


## Note that `region`, just added to `map`, is not in the map's queries until one at `probe` (a
## world point on the region) is answered by it. Forgotten when the region leaves the tree.
static func await_region(map: RID, region: NavigationRegion2D, probe: Vector2) -> void:
	var entry := { "region": region.get_rid(), "probe": probe }
	var waiting: Array = _awaiting.get(map, [])
	waiting.append(entry)
	_awaiting[map] = waiting
	region.tree_exited.connect(_forget.bind(map, entry), CONNECT_ONE_SHOT)


## Drop `entry` from `map`'s awaited regions (its region left the tree).
static func _forget(map: RID, entry: Dictionary) -> void:
	var waiting: Array = _awaiting.get(map, [])
	waiting.erase(entry)
	if waiting.is_empty():
		_awaiting.erase(map)
