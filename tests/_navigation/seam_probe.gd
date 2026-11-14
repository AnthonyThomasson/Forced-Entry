extends RefCounted
## Shared helper for the navigation tests of a district's steering tiles (not a test itself):
## `const Seams := preload("res://tests/_navigation/seam_probe.gd")`. It reads the seams between
## neighbouring tiles as the NavigationServer would (an edge is its ends' 1 px cells, whatever the
## exact points) and the routes a map answers, for the tests that the tiles are welded and that the
## map needs no edge-connection pass.

## How near (px) a vertex lies to a seam's line to be on it.
const ON_LINE := 0.01
## How far (px) in from a seam edge's middle a crossing probe stands, and the shortest edge it is
## made for.
const PROBE_IN := 3.0
const PROBE_EDGE := 6.0


## One neighbouring pair of tiles: `{ a, b, vertical, line }`, `a` the tile left of (or above) `b`,
## `line` the world coordinate of their shared border (x when `vertical`, else y).
static func pairs(tiles: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a: NavigationRegion2D in tiles:
		for b: NavigationRegion2D in tiles:
			var pair := _neighbours(a, b)
			if not pair.is_empty():
				out.append(pair)
	return out


## `{ a, b, vertical, line }` when tile `b` lies right of or below tile `a` along a stretch of
## their rects' border, else `{}`.
static func _neighbours(a: NavigationRegion2D, b: NavigationRegion2D) -> Dictionary:
	if not a.has_meta(NavTiles.RECT_META) or not b.has_meta(NavTiles.RECT_META):
		return {}
	var rect_a: Rect2 = a.get_meta(NavTiles.RECT_META)
	var rect_b: Rect2 = b.get_meta(NavTiles.RECT_META)
	var end := a.to_global(rect_a.end)
	var shares_y := minf(rect_a.end.y, rect_b.end.y) > maxf(rect_a.position.y, rect_b.position.y)
	var shares_x := minf(rect_a.end.x, rect_b.end.x) > maxf(rect_a.position.x, rect_b.position.x)
	if is_equal_approx(rect_b.position.x, rect_a.end.x) and shares_y:
		return { "a": a, "b": b, "vertical": true, "line": end.x }
	if is_equal_approx(rect_b.position.y, rect_a.end.y) and shares_x:
		return { "a": a, "b": b, "vertical": false, "line": end.y }
	return {}


## The polygon edges of `tile` that lie on the line of `pair`: `{ lo, hi, key }`, the span along the
## line (world px) and the edge as the server keys it (the 1 px cells of its ends, in order).
static func seam_edges(tile: NavigationRegion2D, pair: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var poly := tile.navigation_polygon
	if poly == null:
		return out
	var verts := poly.get_vertices()
	for i in poly.get_polygon_count():
		var ring := poly.get_polygon(i)
		for k in ring.size():
			var p := tile.to_global(verts[ring[k]])
			var q := tile.to_global(verts[ring[(k + 1) % ring.size()]])
			if _across(p, pair) and _across(q, pair):
				out.append(_edge(p, q, pair["vertical"]))
	return out


## Whether `point` lies on the line of `pair`.
static func _across(point: Vector2, pair: Dictionary) -> bool:
	var across := point.x if pair["vertical"] else point.y
	return absf(across - pair["line"]) <= ON_LINE


## The edge `p` to `q` on a vertical or horizontal line: its span along it and its server key.
static func _edge(p: Vector2, q: Vector2, vertical: bool) -> Dictionary:
	var along_p := p.y if vertical else p.x
	var along_q := q.y if vertical else q.x
	var cells := [Vector2i(p.floor()), Vector2i(q.floor())]
	cells.sort_custom(func(u: Vector2i, w: Vector2i) -> bool: return u < w)
	return {
		"lo": minf(along_p, along_q),
		"hi": maxf(along_p, along_q),
		"cells": [floorf(minf(along_p, along_q)), floorf(maxf(along_p, along_q))],
		"key": cells,
	}


## What is wrong with the seams of `tiles`: for each two neighbouring tiles, every pair of edges
## that overlap along their border must be one edge to the server (the same two cells), or the map
## joins them only through its edge-connection pass. A line per fault, empty when welded.
static func unwelded(tiles: Array) -> Array[String]:
	var out: Array[String] = []
	for pair in pairs(tiles):
		var theirs := seam_edges(pair["b"], pair)
		for e in seam_edges(pair["a"], pair):
			for f in theirs:
				if _overlap(e, f) > 0.0 and e["key"] != f["key"]:
					out.append(_fault(pair, e, f))
	return out


## How far (px) the spans of the edges `e` and `f` overlap, as the server sees them: from the 1 px
## cells their ends are in, so two ends in one cell are one.
static func _overlap(e: Dictionary, f: Dictionary) -> float:
	return minf(e["cells"][1], f["cells"][1]) - maxf(e["cells"][0], f["cells"][0])


## A line naming the edges `e` and `f`, which differ, on `pair`'s border.
static func _fault(pair: Dictionary, e: Dictionary, f: Dictionary) -> String:
	return "%s | %s at %.1f: [%.2f, %.2f] %s against [%.2f, %.2f] %s" % [
		(pair["a"] as Node).name, (pair["b"] as Node).name, pair["line"],
		e["lo"], e["hi"], e["key"], f["lo"], f["hi"], f["key"],
	]


## World points on the steering `regions` to ask routes between: the point `NavTiles.probe_of`
## gives on each tile that has a navmesh; for a region that is no tile (a lone house's), the middle
## of every `stride`-th polygon.
static func points(regions: Array, stride := 1) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for region: NavigationRegion2D in regions:
		if region.has_meta(NavTiles.RECT_META):
			var probe := NavTiles.probe_of(region, Vector2.INF)
			if probe != Vector2.INF:
				out.append(probe)
		else:
			out.append_array(_middles(region, stride))
	return out


## The world point in the middle (the mean of the corners) of every `stride`-th polygon of `region`.
static func _middles(region: NavigationRegion2D, stride: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var poly := region.navigation_polygon
	var verts := poly.get_vertices()
	for i in range(0, poly.get_polygon_count(), stride):
		var sum := Vector2.ZERO
		var ring := poly.get_polygon(i)
		for index in ring:
			sum += verts[index]
		out.append(region.to_global(sum / float(ring.size())))
	return out


## Pairs of world points to cross the seams with: for each edge on a seam longer than
## `PROBE_EDGE`, `[a, b]` with `a` `PROBE_IN` px inside the first tile and `b` as far inside the
## second, both level with the edge's middle.
static func crossings(tiles: Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for pair in pairs(tiles):
		for e in seam_edges(pair["a"], pair):
			if e["hi"] - e["lo"] < PROBE_EDGE:
				continue
			var mid: float = (e["lo"] + e["hi"]) * 0.5
			var across := Vector2(PROBE_IN, 0.0) if pair["vertical"] else Vector2(0.0, PROBE_IN)
			var at := Vector2(pair["line"], mid) if pair["vertical"] else Vector2(mid, pair["line"])
			out.append(PackedVector2Array([at - across, at + across]))
	return out


## `map`'s path (`optimize`d) between each ordered pair of `spots`, in the order of the pairs
## (`a` over every `b`).
static func all_pairs(map: RID, spots: Array[Vector2]) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for a in spots:
		for b in spots:
			out.append(NavigationServer2D.map_get_path(map, a, b, true))
	return out


## `map`'s path between both ways of each of `ends` (`crossings`).
static func both_ways(map: RID, ends: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for pair in ends:
		out.append(NavigationServer2D.map_get_path(map, pair[0], pair[1], true))
		out.append(NavigationServer2D.map_get_path(map, pair[1], pair[0], true))
	return out


## How the answers `a` and `b` (the same questions asked of two maps) differ: `{ pairs, worst,
## longer, shorter, reach, detour, gain }`: how many answers are not the same path, the largest
## distance (px) between the two paths' points (a path of another length counts as its length's
## difference, at least `1`), how many are longer and how many shorter in `b`, how many one finds a
## path to the end for and the other does not, the longest `b` is over `a` and the most `b` is
## under it (px).
static func compare(a: Array[PackedVector2Array], b: Array[PackedVector2Array]) -> Dictionary:
	var out := {
		"pairs": 0,
		"worst": 0.0,
		"longer": 0,
		"shorter": 0,
		"reach": 0,
		"detour": 0.0,
		"gain": 0.0,
	}
	for i in a.size():
		var gap := _gap(a[i], b[i])
		if gap <= 0.0:
			continue
		out["pairs"] += 1
		out["worst"] = maxf(out["worst"], gap)
		var delta := _length(b[i]) - _length(a[i])
		if a[i].is_empty() != b[i].is_empty():
			out["reach"] += 1
		elif delta > 0.0:
			out["longer"] += 1
			out["detour"] = maxf(out["detour"], delta)
		elif delta < 0.0:
			out["shorter"] += 1
			out["gain"] = maxf(out["gain"], -delta)
	return out


static func _gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() != b.size():
		return maxf(1.0, absf(_length(a) - _length(b)))
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, a[i].distance_to(b[i]))
	return worst


static func _length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	return total
