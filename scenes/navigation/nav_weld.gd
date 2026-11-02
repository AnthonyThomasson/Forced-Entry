class_name NavWeld extends RefCounted
## Navigation domain: what every bake ends with. The baker's polygon has vertices a fraction of a
## pixel apart and slivers the NavigationServer rejects; welding them to the map's 1 px grid and
## dropping the slivers leaves a mesh it can merge. `NavBuilder` calls `finish` on each bake.

## Baked polygons smaller than this (px^2) are slivers and are dropped (see `drop_slivers`).
const MIN_POLYGON_AREA := 0.5


## `nav_poly` welded (`weld_vertices`) and without slivers (`drop_slivers`); `origin` is the
## region's offset.
static func finish(nav_poly: NavigationPolygon, origin: Vector2) -> void:
	weld_vertices(nav_poly, origin)
	drop_slivers(nav_poly)


## Merge the baked vertices that share a 1 px cell of the map (in world space: `origin` is the
## region's offset), the first one standing for them all, and drop the polygon corners that
## collapse. The baker's round joins and the cuts where a hole meets a wall leave vertices a
## fraction of a pixel apart, and the NavigationServer, which merges edges by 1 px cell, rejects an
## edge whose two ends share a cell ("navigation map synchronization error"). A character standing
## against a wall makes such cuts anywhere. Every other vertex keeps its exact place, so away from
## the cuts the mesh (and the paths along it) is the one the baker made.
static func weld_vertices(nav_poly: NavigationPolygon, origin: Vector2) -> void:
	var verts := nav_poly.get_vertices()
	var welded := PackedVector2Array()
	var index_in_cell := {}  # cell -> the index in `welded` of the vertex that stands for it
	var stands_for := PackedInt32Array()
	stands_for.resize(verts.size())
	for i in verts.size():
		var cell := Vector2i((verts[i] + origin).floor())
		if not index_in_cell.has(cell):
			index_in_cell[cell] = welded.size()
			welded.append(verts[i])
		stands_for[i] = index_in_cell[cell]
	var rings: Array = []
	for i in nav_poly.get_polygon_count():
		var ring := PackedInt32Array()
		for index in nav_poly.get_polygon(i):
			var j := stands_for[index]
			if ring.is_empty() or ring[ring.size() - 1] != j:
				ring.append(j)
		if ring.size() > 1 and ring[0] == ring[ring.size() - 1]:
			ring.remove_at(ring.size() - 1)
		if ring.size() >= 3:
			rings.append(ring)
	nav_poly.clear_polygons()
	nav_poly.vertices = welded
	for ring in rings:
		nav_poly.add_polygon(ring)


## Remove the baked polygons with (almost) no area. Where furniture sits flush against a wall the
## bake can leave a zero-width sliver whose edges coincide with its neighbours'; it covers no
## walkable ground, and the NavigationServer rejects the map ("navigation map synchronization
## error") when it tries to merge those coincident edges.
static func drop_slivers(nav_poly: NavigationPolygon) -> void:
	var verts := nav_poly.get_vertices()
	var kept: Array = []
	for i in nav_poly.get_polygon_count():
		var indices := nav_poly.get_polygon(i)
		var ring := PackedVector2Array()
		for index in indices:
			ring.append(verts[index])
		if absf(signed_area(ring)) >= MIN_POLYGON_AREA:
			kept.append(indices)
	if kept.size() == nav_poly.get_polygon_count():
		return
	nav_poly.clear_polygons()
	for indices in kept:
		nav_poly.add_polygon(indices)


## Shoelace area of `ring` (positive when counter-clockwise).
static func signed_area(ring: PackedVector2Array) -> float:
	var area := 0.0
	for i in ring.size():
		area += ring[i].cross(ring[(i + 1) % ring.size()])
	return area * 0.5
