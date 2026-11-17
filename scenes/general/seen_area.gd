class_name SeenArea
extends RefCounted
## General domain: the part of the world the player's view shows live (interface 11,
## `docs/player-vision.md` V11), a static holder. The Vision domain writes it each time it
## rebuilds the cone (`set_area`: the polygons of what is seen and their bounds) and clears it when
## the view lifts (`clear`); what shows something that is only ever seen inside the cone asks
## whether a disc of it (`reaches`) reaches the area, and skips the work while it wholly does not
## (Art's mirror, the shots). With no area
## set (no view, a view lifted, a switch off) every disc reaches, so nothing is skipped.

## The polygons of the seen area (the cone, the bubble) and their bounds; `_set` says whether an
## area is set at all.
static var _polygons: Array = []
static var _bounds := Rect2()
static var _set := false
static var _version := 0


## Set the seen area to `polygons` (`PackedVector2Array`s, each a simple polygon: the cone, the
## bubble) lying inside `bounds`, replacing the last. An empty list is a view that sees nothing.
static func set_area(polygons: Array, bounds: Rect2) -> void:
	_polygons = polygons
	_bounds = bounds
	_set = true
	_version += 1


## Whether an area is set: a view is on and has published a cone (false: every disc reaches).
static func active() -> bool:
	return _set


## How many times the area was set or cleared: a caller that asks only of a changed area compares
## it.
static func version() -> int:
	return _version


## Forget the area: every disc reaches again.
static func clear() -> void:
	_polygons = []
	_bounds = Rect2()
	_set = false
	_version += 1


## Whether any part of the disc at `center` of `radius` px lies inside the seen area; always true
## while no area is set.
static func reaches(center: Vector2, radius: float) -> bool:
	if not _set:
		return true
	if not _bounds.grow(radius).has_point(center):
		return false
	for polygon: PackedVector2Array in _polygons:
		if _reaches(polygon, center, radius):
			return true
	return false


## Whether the disc touches `polygon`: its centre is inside, or an edge passes within `radius` of it
## (which also holds when the polygon lies inside the disc).
static func _reaches(polygon: PackedVector2Array, center: Vector2, radius: float) -> bool:
	var count := polygon.size()
	if count < 3:
		return false
	var limit := radius * radius
	var previous := polygon[count - 1]
	for corner in polygon:
		var nearest := Geometry2D.get_closest_point_to_segment(center, previous, corner)
		if nearest.distance_squared_to(center) <= limit:
			return true
		previous = corner
	return contains(polygon, center)


## Whether `point` is inside `polygon` (at least three corners; its edges excluded), by the even-odd
## rule. Vision's `sees` and the tests ask it too. Not the engine's
## `Geometry2D.is_point_in_polygon`, which says a point is inside some simple polygons it lies
## well outside of (a cone with many collinear corners on a wall).
static func contains(polygon: PackedVector2Array, point: Vector2) -> bool:
	if polygon.size() < 3:
		return false
	var inside := false
	var previous := polygon[polygon.size() - 1]
	for corner in polygon:
		if (corner.y > point.y) != (previous.y > point.y):
			var crossing := previous.x + (point.y - previous.y) / (corner.y - previous.y) * (
				corner.x - previous.x
			)
			if point.x < crossing:
				inside = not inside
		previous = corner
	return inside
