extends RefCounted
## Shared helper for the navigation tests that a bake beside a wall comes out clean (not a test
## itself): `const Bake := preload("res://tests/_navigation/bake_probe.gd")`.


## What is wrong with `region`'s baked polygon, as the NavigationServer would see it ("" = nothing):
## a polygon edge whose ends fall in one 1 px cell, or that more than two polygons share.
static func problem(region: NavigationRegion2D) -> String:
	var poly := region.navigation_polygon
	var verts := poly.get_vertices()
	var offset := region.global_position
	var shared := {}
	for i in poly.get_polygon_count():
		var indices := poly.get_polygon(i)
		for k in indices.size():
			var a := verts[indices[k]] + offset
			var b := verts[indices[(k + 1) % indices.size()]] + offset
			var cell_a := Vector2i(a.floor())
			var cell_b := Vector2i(b.floor())
			if cell_a == cell_b:
				return "an edge collapses at %s" % a
			var key := ([cell_a, cell_b]
					if (cell_a.x < cell_b.x or (cell_a.x == cell_b.x and cell_a.y < cell_b.y))
					else [cell_b, cell_a])
			shared[key] = int(shared.get(key, 0)) + 1
			if shared[key] > 2:
				return "an edge at %s is shared by three polygons" % a
	return ""
