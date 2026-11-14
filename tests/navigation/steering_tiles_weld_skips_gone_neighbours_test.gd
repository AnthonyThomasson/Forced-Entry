extends "res://tests/navigation/seams_split_at_neighbour_vertices_test.gd"
## A tile freed or taken out of the tree while a burst of baked tiles is on its way to landing (the
## district goes, a tick lands late) is left alone by the weld and by `NavTiles.land`: its
## neighbour's cached list still names it, and neither reads it, nor errors on it.


func describe() -> Dictionary:
	return {
		"name": "Welding and landing skip a tile that is freed or out of the tree",
		"description": "NavSeams.weld and NavTiles.land leave a freed neighbour and a tile taken "
			+ "out of the tree as they are, and the tile beside them is whole again.",
		"tags": ["navigation", "district", "steering"],
		"timeout": 30.0,
	}


func run(t: TestContext) -> void:
	var parent := Node2D.new()
	t.world.add_child(parent)
	var left := _tile(parent, Rect2(0, 0, 100, 100), [
		[Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)],
	])
	var right := _tile(parent, Rect2(100, 0, 100, 100), [
		[Vector2(100, 0), Vector2(200, 0), Vector2(150, 50), Vector2(100, 40)],
		[
			Vector2(100, 60), Vector2(100, 100), Vector2(200, 100), Vector2(150, 50),
		],
		[Vector2(200, 0), Vector2(200, 100), Vector2(150, 50)],
	])
	NavSeams.weld([left, right])
	t.check(left.navigation_polygon != left.get_meta(NavSeams.RAW_META), "premise: left is split")
	var away := _tile(parent, Rect2(200, 0, 100, 100), [
		[Vector2(200, 0), Vector2(300, 0), Vector2(300, 100), Vector2(200, 100)],
	])
	NavSeams.weld([away])
	parent.remove_child(away)
	var held := { "tile": away, "poly": _poly([[Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]]) }
	held["walls"] = { "obstruction": [] }
	held["holes"] = []
	var kept: NavigationPolygon = away.get_meta(NavSeams.RAW_META)
	NavTiles.land([held])
	t.check(
		away.get_meta(NavSeams.RAW_META) == kept,
		"a tile out of the tree is not given its landed polygon",
	)
	NavSeams.weld([away, right])
	right.free()
	NavSeams.weld([left])
	t.expect_eq(
		left.navigation_polygon,
		left.get_meta(NavSeams.RAW_META),
		"the tile beside a freed one is whole again",
	)
	NavTiles.land([{ "tile": right }])
	t.expect_eq(NavSeams.unsplit_total, 0, "no edge was left uncut")
	away.free()
