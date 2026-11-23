extends GameTest
## A steering tile holds the cells of its border column that an obstruction or the lack of floor
## holds, found a line of cell centres at a time (`NavBorder.runs`). This pins it to asking
## the engine about each centre in turn (`Geometry2D.is_point_in_polygon`), over polygons whose
## edges sit on the centres' lines (the engine's answer on an edge differs along it),
## through them at a slant, past a tile's corner and with the floor ending inside the border band.


func describe() -> Dictionary:
	return {
		"name": "A tile's border cells are the ones asked of the engine one by one",
		"description": "The scanline read of a tile's border gives the runs a point-by-point read "
			+ "gives, edges on the centres included.",
		"tags": ["bake", "tiles", "seams"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var tile := Rect2(-16, 40, 512, 256)
	var blocks: Array[PackedVector2Array] = [
		_rect(Rect2(-40, 62, 40, 46)),  # edges on the centres of the column and of the cells
		_rect(Rect2(-22, 120, 30, 40)),  # an edge on the line of the column's centres
		_rect(Rect2(100, 20, 33, 21)),  # across the top border by a hair
		_rect(Rect2(150, 290, 50, 30)),  # across the bottom border
		PackedVector2Array([Vector2(480, 100), Vector2(520, 130), Vector2(500, 200)]),  # a slant
		PackedVector2Array(
			[Vector2(300, 12), Vector2(340, 38), Vector2(330, 60), Vector2(310, 60)]
		),
	]
	var boxes: Array[Rect2] = []
	for block in blocks:
		boxes.append(NavSource.outline_bounds(block))
	var cases: Array = [
		[_rect(Rect2(-1542, -2202, 3104, 4000))],
		[_rect(Rect2(-18, 38, 800, 300))],  # its left edge between the border's two columns
		[_rect(Rect2(-60, 42, 900, 254))],  # its top edge on a line of centres
		[],
	]
	for case: Array in cases:
		var floors: Array[PackedVector2Array] = []
		floors.assign(case)
		var ours := NavBorder.runs(blocks, boxes, floors, tile)
		var theirs := _asked_one_by_one(blocks, floors, tile)
		t.check(
			ours == theirs,
			"the floor %s: the runs are the ones a point-by-point read gives (%d against %d)"
				% [floors, ours.size(), theirs.size()],
		)


## The four corners of `rect` as a polygon.
func _rect(rect: Rect2) -> PackedVector2Array:
	return NavSource.rect_outline(rect)


## What `NavBorder.runs` finds, a cell at a time: the cell of `tile`'s outermost column on
## each side level with a centre, or the one across the border from it, held by a block or by no
## floor, joined to its neighbours.
func _asked_one_by_one(
	blocks: Array[PackedVector2Array],
	floors: Array[PackedVector2Array],
	tile: Rect2,
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for side in 4:
		var along := side <= 1
		var first := (tile.position.y if along else tile.position.x) + NavSource.CELL_SIZE * 0.5
		var last := (tile.end.y if along else tile.end.x) - NavSource.CELL_SIZE * 0.5
		var outer := NavBorder.strip_across(tile, side).get_center()
		var inner := NavBorder.strip_inside(tile, side).get_center()
		var from := -INF
		var mid := first
		while mid <= last:
			var held := false
			for centre: Vector2 in [outer, inner]:
				var point := Vector2(centre.x, mid) if along else Vector2(mid, centre.y)
				held = held or _held(point, blocks, floors)
			if held and from == -INF:
				from = mid
			elif not held and from != -INF:
				out.append(NavBorder.run_inside(tile, side, from, mid - NavSource.CELL_SIZE))
				from = -INF
			mid += NavSource.CELL_SIZE
		if from != -INF:
			out.append(NavBorder.run_inside(tile, side, from, last))
	return out


## Whether the cell centred at `point` is in a block or in no floor.
func _held(
	point: Vector2,
	blocks: Array[PackedVector2Array],
	floors: Array[PackedVector2Array],
) -> bool:
	for block in blocks:
		if Geometry2D.is_point_in_polygon(point, block):
			return true
	for floor_outline in floors:
		if Geometry2D.is_point_in_polygon(point, floor_outline):
			return false
	return true
