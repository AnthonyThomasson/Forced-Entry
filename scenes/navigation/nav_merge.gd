class_name NavMerge extends RefCounted
## Navigation domain: the polygon merge pass after a bake. The grid baker cuts the floor into a
## region a ridge of its distance field apart, so a district's mesh has about 3 times the polygons
## of the outline partition the 2D baker made, and the server's path query pays for each one it
## crosses. Two polygons that share an edge are one polygon when their union is still convex and
## holds at most `MAX_CORNERS` corners: the area walked is the same, the polygons are fewer. Every
## vertex stays (a merged polygon keeps its collinear ones), so the edges the map joins regions
## by, and the tile border the steering tiles are welded on (`NavSeams`), are the ones the baker
## made.

## The most corners a merged polygon may have (the server takes any count; the funnel's work grows
## with it).
const MAX_CORNERS := 12
## A corner turning by less than this (the cross of its two edges, px squared) is straight.
const STRAIGHT := 0.01


## `polygons` (each a ring of indexes into `vertices`) with neighbours merged where the union is
## convex: the same floor in fewer polygons. It runs on a worker thread (`NavSource.bake_polygon`),
## where a GDScript call and a dictionary write are dear, so it keeps each ring's turning (`sides`)
## instead of reading it again for every neighbour tried, and a merge rewrites only what it
## changes in `owner`: the shared edge goes, the union's edges are written over the two rings'.
static func merged(
	vertices: PackedVector2Array,
	polygons: Array[PackedInt32Array],
) -> Array[PackedInt32Array]:
	var rings: Array[PackedInt32Array] = polygons.duplicate()
	var count := vertices.size()
	var owner := {}
	var sides := PackedFloat32Array()
	sides.resize(rings.size())
	for p in rings.size():
		_register(owner, rings[p], p, count)
		sides[p] = _side(vertices, rings[p])
	for p in rings.size():
		while not rings[p].is_empty() and _grow(vertices, rings, sides, p, owner):
			pass
	var result: Array[PackedInt32Array] = []
	for ring in rings:
		if not ring.is_empty():
			result.append(_fan_first(vertices, ring))
	return result


## Note each edge of `ring` (ring `p`) in `owner`: the edge's ends (`a * count + b`) to the ring
## and the place the edge has in it (`p << 8 | place`).
static func _register(owner: Dictionary, ring: PackedInt32Array, p: int, count: int) -> void:
	var n := ring.size()
	var tag := p << 8
	var from := ring[n - 1]
	for i in n:
		# The edge from the vertex before `i` to vertex `i` is ring edge `i - 1`.
		var to := ring[i]
		owner[from * count + to] = tag | ((i + n - 1) % n)
		from = to


## Ring `p` merged with the first neighbour whose union with it is acceptable (the neighbour is
## gone, `owner` follows the merged ring); whether one was.
static func _grow(
	vertices: PackedVector2Array,
	rings: Array[PackedInt32Array],
	sides: PackedFloat32Array,
	p: int,
	owner: Dictionary,
) -> bool:
	var count := vertices.size()
	var ring := rings[p]
	var n := ring.size()
	for i in n:
		# The edge a -> b of this ring: its neighbour holds b -> a.
		var found: int = owner.get(ring[(i + 1) % n] * count + ring[i], -1)
		if found < 0:
			continue
		var q := found >> 8
		var union := _union(vertices, ring, rings[q], Vector2i(i, found & 255), sides[p])
		if union.is_empty():
			continue
		# The shared edge is in neither ring now; every other edge of the two is the union's, at
		# its place in it.
		owner.erase(ring[i] * count + ring[(i + 1) % n])
		owner.erase(ring[(i + 1) % n] * count + ring[i])
		rings[p] = union
		rings[q] = PackedInt32Array()
		sides[p] = _side(vertices, union)
		_register(owner, union, p, count)
		return true
	return false


## The ring `a` and `b` make across their shared edge (`a`'s edge `edges.x`, `b`'s edge `edges.y`;
## `side` is `a`'s turning, `_side`), or an empty one when it is not convex or has more than
## `MAX_CORNERS` corners.
static func _union(
	vertices: PackedVector2Array,
	a: PackedInt32Array,
	b: PackedInt32Array,
	edges: Vector2i,
	side: float,
) -> PackedInt32Array:
	var i := edges.x
	var j := edges.y
	var na := a.size()
	var nb := b.size()
	if na + nb - 2 > MAX_CORNERS:
		return PackedInt32Array()
	# The two corners the edge's ends become: a's before one, b's after it, and b's before the
	# other, a's after it.
	if not _turns(vertices, a[(i + na - 1) % na], a[i], b[(j + 2) % nb], side):
		return PackedInt32Array()
	if not _turns(vertices, b[(j + nb - 1) % nb], a[(i + 1) % na], a[(i + 2) % na], side):
		return PackedInt32Array()
	# `a` from its edge's end round to the edge's start, then `b` from the corner past the edge's
	# start (`b`'s edge `j` ends at `a`'s start of edge `i`) round to the one before it.
	var ring := a.slice(i + 1)
	ring.append_array(a.slice(0, i + 1))
	var first := (j + 2) % nb
	if first + nb - 2 <= nb:
		ring.append_array(b.slice(first, first + nb - 2))
	else:
		ring.append_array(b.slice(first))
		ring.append_array(b.slice(0, nb - 2 - (nb - first)))
	if _fan_start(vertices, ring) < 0:
		return PackedInt32Array()
	return ring


## The way ring `a` turns (1 or -1): the sign of its area. A convex ring turns that way all round.
static func _side(vertices: PackedVector2Array, a: PackedInt32Array) -> float:
	var area := 0.0
	var n := a.size()
	for i in n:
		area += vertices[a[i]].cross(vertices[a[(i + 1) % n]])
	return 1.0 if area >= 0.0 else -1.0


## Whether the corner at `at` between `before` and `after` turns `side`'s way (or is straight).
static func _turns(
	vertices: PackedVector2Array,
	before: int,
	at: int,
	after: int,
	side: float,
) -> bool:
	return _cross(vertices[before], vertices[at], vertices[after]) * side >= -STRAIGHT


## `ring` turned to start where the server's fan from the first vertex has no flat triangle, or
## `ring` as it is when no start does.
static func _fan_first(vertices: PackedVector2Array, ring: PackedInt32Array) -> PackedInt32Array:
	var start := _fan_start(vertices, ring)
	if start <= 0:
		return ring
	return ring.slice(start) + ring.slice(0, start)


## The place in `ring` to start it at, -1 for none. The server finds the closest point of a polygon
## by fanning it from its first vertex into triangles (v0, v(k-1), vk) and loses the polygon when
## the first or the last of them is flat: that is when the corner at the second vertex or the one
## before the first is straight (a point 8 px inside a 12-corner polygon was 8 px off the map, and
## which start is flat shows in a standalone mesh of that ring: only the ones whose first three
## vertices are on a line). A start is good when both its neighbours are real corners.
static func _fan_start(vertices: PackedVector2Array, ring: PackedInt32Array) -> int:
	var n := ring.size()
	for i in n:
		if _corner(vertices, ring, (i + 1) % n) and _corner(vertices, ring, (i + n - 1) % n):
			return i
	return -1


## Whether the ring turns at its vertex `at`: it is no point on a straight run.
static func _corner(vertices: PackedVector2Array, ring: PackedInt32Array, at: int) -> bool:
	var n := ring.size()
	var cross := _cross(
		vertices[ring[(at + n - 1) % n]], vertices[ring[at]], vertices[ring[(at + 1) % n]],
	)
	return absf(cross) > STRAIGHT


## The cross of the edges `p -> q` and `q -> r`.
static func _cross(p: Vector2, q: Vector2, r: Vector2) -> float:
	return (q - p).cross(r - q)
