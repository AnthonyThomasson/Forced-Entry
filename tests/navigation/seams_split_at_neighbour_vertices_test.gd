extends GameTest
## Two steering tiles side by side (`NavSeams`): the left tile's polygon edge along their border
## runs the whole stretch where the right tile's has a notch (a wall's tip on the line). Welded,
## the left tile's edge is cut at the notch's ends, so it and the right tile's edges are the same
## edges to the server; a vertex in a cell the edge's end is in is no cut; the tile keeps the
## polygon it was baked with, so a neighbour's re-bake starts from that, not from a split.

const Seams := preload("res://tests/_navigation/seam_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A tile's border edge is cut at the vertices its neighbour has there",
		"description": "NavSeams splits a steering tile's edge along a border at the neighbour's "
			+ "vertices inside it, once per cell, and re-bakes start from the raw polygon.",
		"tags": ["navigation", "district", "steering"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var parent := Node2D.new()
	t.world.add_child(parent)
	# Left tile [0, 100] x [0, 100]: one square. Right tile [100, 200] x [0, 100]: its left edge has
	# a notch between y 40 and 60, and a vertex at y 80.4 shares a cell with the left's own at 80.
	var left := _tile(parent, Rect2(0, 0, 100, 100), [
		[Vector2(0, 0), Vector2(100, 0), Vector2(100, 80), Vector2(100, 100), Vector2(0, 100)],
	])
	var right := _tile(parent, Rect2(100, 0, 100, 100), [
		[Vector2(100, 0), Vector2(200, 0), Vector2(150, 50), Vector2(100, 40)],
		[
			Vector2(100, 60), Vector2(100, 80.4), Vector2(100, 100),
			Vector2(200, 100), Vector2(150, 50),
		],
		[Vector2(200, 0), Vector2(200, 100), Vector2(150, 50)],
	])
	NavSeams.weld([left, right])
	t.check(
		Seams.unwelded([left, right]).is_empty(),
		"the border is welded: %s" % [Seams.unwelded([left, right])],
	)
	var edges := Seams.seam_edges(left, Seams.pairs([left, right])[0])
	t.expect_eq(edges.size(), 4, "the left tile's border edge is cut at 40 and 60, not at 80.4")
	t.expect_eq(
		right.navigation_polygon,
		right.get_meta(NavSeams.RAW_META),
		"the right tile needs no cut",
	)
	t.check(
		left.navigation_polygon != left.get_meta(NavSeams.RAW_META),
		"the left tile holds a split copy",
	)
	var raw: NavigationPolygon = left.get_meta(NavSeams.RAW_META)
	t.expect_eq(raw.get_vertices().size(), 5, "the raw polygon keeps its five vertices")
	# The right tile re-baked without the notch: the left's cuts go, back to the raw polygon.
	NavSeams.take(
		right,
		_poly([[Vector2(100, 0), Vector2(200, 0), Vector2(200, 100), Vector2(100, 100)]]),
	)
	right.navigation_polygon = right.get_meta(NavSeams.RAW_META)
	NavSeams.weld([right])
	t.expect_eq(
		left.navigation_polygon,
		left.get_meta(NavSeams.RAW_META),
		"the left tile is whole again",
	)
	t.check(Seams.unwelded([left, right]).is_empty(), "the border is still welded")


## A tile region over `rect` holding `rings` (polygons of points), welded as a baked tile is.
func _tile(parent: Node2D, rect: Rect2, rings: Array) -> NavigationRegion2D:
	var tile := NavigationRegion2D.new()
	tile.set_meta(NavTiles.RECT_META, rect)
	parent.add_child(tile)
	var poly := _poly(rings)
	NavSeams.take(tile, poly)
	tile.navigation_polygon = poly
	return tile


## A navigation polygon of `rings`, each a list of points.
func _poly(rings: Array) -> NavigationPolygon:
	var poly := NavigationPolygon.new()
	var points := PackedVector2Array()
	for ring: Array in rings:
		var indices := PackedInt32Array()
		for point: Vector2 in ring:
			indices.append(points.size())
			points.append(point)
		poly.add_polygon(indices)
	poly.vertices = points
	return poly
