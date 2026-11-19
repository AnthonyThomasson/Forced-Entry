class_name WallFactory
## Objects-domain factory: turns a plain rect + doorway openings into a runtime Wall entity
## (a StaticBody2D that builds its own colliders and is hittable/deformable). World-Gen
## calls this with geometry and an optional style dict — it never touches the Wall's fields.

const WallScript = preload("res://scenes/objects/wall/wall.gd")
## Two walls this close (px) are along one line, and two that share more than this run along one
## another.
const SEAM_TOLERANCE := 0.5


## The doorways in `doors` (`{ pos, width }`, one point on a wall's centerline each) that lie on one
## of `rect`'s walls, as the `openings` array `spawn` takes. A door whose point is on no wall of
## `rect` is skipped.
static func openings_for(rect: Rect2, doors: Array) -> Array:
	var cut: Array = []
	for door in doors:
		var p: Vector2 = door["pos"]
		var width: float = door["width"]
		var within_x := p.x > rect.position.x and p.x < rect.end.x
		var within_y := p.y > rect.position.y and p.y < rect.end.y
		if within_x and is_equal_approx(p.y, rect.position.y):
			cut.append({
				"side": WallScript.Side.TOP,
				"offset": p.x - rect.position.x,
				"width": width,
			})
		elif within_x and is_equal_approx(p.y, rect.end.y):
			cut.append({
				"side": WallScript.Side.BOTTOM,
				"offset": p.x - rect.position.x,
				"width": width,
			})
		elif within_y and is_equal_approx(p.x, rect.position.x):
			cut.append({
				"side": WallScript.Side.LEFT,
				"offset": p.y - rect.position.y,
				"width": width,
			})
		elif within_y and is_equal_approx(p.x, rect.end.x):
			cut.append({
				"side": WallScript.Side.RIGHT,
				"offset": p.y - rect.position.y,
				"width": width,
			})
	return cut


## The stretches of `rect`'s walls that run along a wall of one of `built` (the outlines of the
## walls already built, `Rect2`s), as the `seams` array `spawn` takes: `{ side, from, to }`, along
## the side from its start corner. The walls of two rooms that touch are the same wall there, built
## once by whichever came first.
static func seams_for(rect: Rect2, built: Array) -> Array:
	var cut: Array = []
	for other: Rect2 in built:
		_along(cut, rect, other, true)
		_along(cut, rect, other, false)
	return cut


## Append to `cut` the stretches the walls of `rect` that run along x (`horizontal`: its top and
## bottom) or along y (its left and right) have in common with those of `other`.
static func _along(cut: Array, rect: Rect2, other: Rect2, horizontal: bool) -> void:
	var fixed := 1 if horizontal else 0  # the coordinate a wall's line is at
	var span := 1 - fixed  # the one it runs along
	var sides: Array = (
		[WallScript.Side.TOP, WallScript.Side.BOTTOM]
		if horizontal
		else [WallScript.Side.LEFT, WallScript.Side.RIGHT]
	)
	var mine := Vector2(rect.position[span], rect.end[span])
	var theirs := Vector2(other.position[span], other.end[span])
	for i in 2:
		var line: float = rect.position[fixed] if i == 0 else rect.end[fixed]
		for other_line: float in [other.position[fixed], other.end[fixed]]:
			if absf(line - other_line) < SEAM_TOLERANCE:
				_overlap(cut, sides[i], mine, theirs)


## Append to `cut` the stretch `side` of a wall spanning `mine` (low, high) has in common with a
## wall along the same line spanning `other`, as `{ side, from, to }` along it from `mine.x`.
static func _overlap(cut: Array, side: int, mine: Vector2, other: Vector2) -> void:
	var from := maxf(mine.x, other.x) - mine.x
	var to := minf(mine.y, other.y) - mine.x
	if to - from > SEAM_TOLERANCE:
		cut.append({ "side": side, "from": from, "to": to })


## `rect` is the room's outline (walls run along its centerline); `walls` says how they are built:
## their `thickness`, their `openings` (doorways in Wall.Side format, see wall.gd) and their `style`
## (the cap's look: `art` (a tiling painter id), `color`, `art_opts`; empty = a flat gray line).
static func spawn(rect: Rect2, walls: RoomWalls, wall_name: String, parent: Node) -> Node:
	var wall := StaticBody2D.new()
	wall.name = wall_name
	wall.position = rect.position
	wall.script = WallScript

	wall.size = rect.size
	wall.wall_thickness = walls.thickness
	wall.openings = walls.openings
	wall.seams = walls.seams
	var style := walls.style
	wall.art = style.get("art", "")
	wall.art_color = style.get("color", Color(0.6, 0.6, 0.6))
	wall.art_opts = style.get("art_opts", {})

	parent.add_child(wall)
	return wall
