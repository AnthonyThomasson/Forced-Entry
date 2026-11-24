extends GameTest
## A tile polygon whose border edge to cut lies between two straight corners (a merged polygon
## keeps the collinear vertices a border run had, `NavMerge`) is cut all the same (`NavSeams`): the
## edge's triangles are fanned from the nearest vertex off its line, so the border is welded and
## no edge is left uncut (`unsplit_total`).

const Seams := preload("res://tests/_navigation/seam_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A border edge between two straight corners is cut at the neighbour's vertex",
		"description": "NavSeams cuts a tile's border edge whose corners either side are in line "
			+ "with it, fanning from a vertex off the line: welded, nothing left uncut.",
		"tags": ["navigation", "district", "steering"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var parent := Node2D.new()
	t.world.add_child(parent)
	var unsplit := NavSeams.unsplit_total
	# Left tile [0, 100]^2: one polygon with four vertices in a line on its right border; the edge
	# from y 40 to y 64 has a straight corner at each end. Right tile: a vertex at y 52 between.
	var left := _tile(parent, Rect2(0, 0, 100, 100), [
		[
			Vector2(0, 0), Vector2(100, 0), Vector2(100, 40), Vector2(100, 64),
			Vector2(100, 100), Vector2(0, 100),
		],
	])
	var right := _tile(parent, Rect2(100, 0, 100, 100), [
		[Vector2(100, 0), Vector2(200, 0), Vector2(200, 100), Vector2(100, 100), Vector2(100, 52)],
	])
	NavSeams.weld([left, right])
	t.expect_eq(NavSeams.unsplit_total, unsplit, "no edge was left uncut")
	t.check(
		Seams.unwelded([left, right]).is_empty(),
		"the border is welded: %s" % [Seams.unwelded([left, right])],
	)
	var edges := Seams.seam_edges(left, Seams.pairs([left, right])[0])
	t.check(edges.size() >= 4, "the border edge was cut at 52 (%d edges)" % edges.size())
	var area := 0.0
	var poly := NavPlan.polygon_of(left)
	var vertices := poly.get_vertices()
	for i in poly.get_polygon_count():
		var ring := poly.get_polygon(i)
		for k in range(1, ring.size() - 1):
			area += absf(
				(vertices[ring[k]] - vertices[ring[0]]).cross(
					vertices[ring[k + 1]] - vertices[ring[0]]) * 0.5)
	t.check(is_equal_approx(area, 10_000.0), "the pieces still cover the tile (%.1f)" % area)


## A tile region over `rect` holding `rings` (polygons of points), welded as a baked tile is.
func _tile(parent: Node2D, rect: Rect2, rings: Array) -> NavigationRegion3D:
	var tile := NavigationRegion3D.new()
	tile.set_meta(NavTiles.RECT_META, rect)
	parent.add_child(tile)
	var poly := NavigationPolygon.new()
	poly.cell_size = NavSource.CELL_SIZE
	var points := PackedVector2Array()
	for ring: Array in rings:
		var indices := PackedInt32Array()
		for point: Vector2 in ring:
			indices.append(points.size())
			points.append(point)
		poly.add_polygon(indices)
	poly.vertices = points
	NavSeams.take(tile, poly)
	NavPlan.assign(tile, poly)
	return tile
