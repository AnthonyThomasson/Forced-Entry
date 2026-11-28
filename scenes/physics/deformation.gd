class_name Deformation
## Physics System: stateless damage-deformation geometry, shared by furniture, walls, characters and
## vehicles (their meshes and, for furniture/walls, collider rebuilds), so the shown silhouette and
## any collider come from the same deformed polygon. The caller owns the
## impact list. Tuning lives in PhysicsDeformConfig and PhysicsDeformLookConfig (the darkening),
## and, for a character, CharacterHitConfig.
##
## An "impact" is a Dictionary in the drawer's local space:
##   pos:    Vector2  contact point
##   inward: Vector2  unit direction INTO the surface (dents push points this way)
##   depth:  float    dent depth in px (from dealt damage)
##   chunk:  bool     true = carve a jagged missing piece instead of a shallow dent
##   seed:   int      stable RNG seed so a hit's jitter doesn't shimmer each frame
##   blood:  float    0..1 blood the striker carried onto the surface
## `new_impact` builds one and `push_impact` adds it to a list, so every caller records the same
## schema.

## Multiplier that packs two piece ids into one dictionary key in `PieceScan._try_merge`, the scan
## `_convex_pieces` runs (ids stay far below it).
const PIECE_PAIR_STRIDE := 65_536
## Dented silhouettes `shape_polygon` keeps before it starts over (a dozen bodies, a few parts
## each).
const POLYGON_CACHE_SIZE := 256
## The share of the way to a ring neighbour a dented point may be pushed along the outline (under
## half, so two neighbours pushed toward each other never meet).
const NEIGHBOUR_REACH := 0.45

## `shape_polygon`'s kept results: inputs hash -> [the inputs, the polygon].
static var _polygon_cache: Dictionary = {}
## The `n` points of the unit circle `base_ring` scales, from angle 0 round, by `n`; kept, as they
## never change.
static var _unit_rings := {}
## The dented wall segments `wall_polygon` keeps, by the hash of their inputs: [inputs, polygon].
static var _wall_cache := {}


## An impact (above) at `pos` caving along `inward` (both in the caller's local space) from `damage`
## dealt, in a body that caves as `dent` says: its depth `damage *
## PhysicsDeformConfig.depth_per_damage`, at most `dent.max_depth`; a chunk when
## `dent.allow_chunks` and `damage` reaches `PhysicsDeformConfig.chunk_damage`; a seed drawn from
## `dent.rng` (the world's); `blood` carried.
static func new_impact(
	pos: Vector2,
	inward: Vector2,
	damage: float,
	blood: float,
	dent: DentLimits,
) -> Dictionary:
	return {
		"pos": pos, "inward": inward,
		"depth": minf(damage * PhysicsDeformConfig.depth_per_damage, dent.max_depth),
		"chunk": dent.allow_chunks and damage >= PhysicsDeformConfig.chunk_damage,
		"seed": dent.rng.randi(), "blood": blood,
	}


## Append `hit` (a `new_impact`) to `list`, dropping the oldest past `max_impacts`.
static func push_impact(list: Array, hit: Dictionary, max_impacts: int) -> void:
	list.append(hit)
	if list.size() > max_impacts:
		list.pop_front()


## Closed perimeter sample ring for a primitive shape, centered on the origin.
static func base_ring(shape: String, size: Vector2) -> PackedVector2Array:
	return _ring(shape, size, true)


## `base_ring`, a circle's unit ring the one kept in `_unit_rings` (`kept`, on the main thread) or
## made afresh (pure: a worker's cut reads and writes no shared state).
static func _ring(shape: String, size: Vector2, kept: bool) -> PackedVector2Array:
	var ring := PackedVector2Array()
	match shape:
		"circle":
			var radius := size.x * 0.5
			# The unit ring scaled: a fresh array each call (callers may change theirs), with no
			# trig per point.
			var n := maxi(3, PhysicsDeformConfig.circle_points)
			var unit := _unit_ring(n) if kept else _unit_points(n)
			return Transform2D(0.0, Vector2(radius, radius), 0.0, Vector2.ZERO) * unit
		_:  # "square" / "rect"
			var half := size * 0.5
			var corners := [
				Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
				Vector2(half.x, half.y), Vector2(-half.x, half.y),
			]
			var per: int = maxi(1, PhysicsDeformConfig.rect_points_per_edge)
			for c in 4:
				var a: Vector2 = corners[c]
				var b: Vector2 = corners[(c + 1) % 4]
				for i in per:
					ring.append(a.lerp(b, float(i) / float(per)))
	return ring


## The unit ring of `n` points kept in `_unit_rings`, made there on its first ask (main thread only:
## it writes the shared cache).
static func _unit_ring(n: int) -> PackedVector2Array:
	var ring: Variant = _unit_rings.get(n)
	if ring == null:
		ring = _unit_points(n)
		_unit_rings[n] = ring
	return ring


## The `n` points of the unit circle from angle 0 round, made afresh: pure, so a worker thread may
## make them.
static func _unit_points(n: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		points.append(Vector2(cos(a), sin(a)))
	return points


## Displace ring points near each impact: shallow smooth dents, or a deep jagged notch
## for `chunk` impacts (a "missing piece"). Points are clamped so they can't cross the
## shape center (which would fold the polygon inside out), nor pass a neighbour along the
## outline (`NEIGHBOUR_REACH`).
static func deform(ring: PackedVector2Array, impacts: Array, radius: float,
		core: float = PhysicsDeformConfig.back_margin) -> PackedVector2Array:
	if impacts.is_empty():
		return ring
	var center := _centroid(ring)
	var out := PackedVector2Array()
	var n := ring.size()
	out.resize(n)
	for i in n:
		var p: Vector2 = ring[i]
		var offset := _cap_along(ring, i, _dent_offset(p, i, impacts, radius))
		# Clamp the displacement so a dent can't push the point past the object's opposite
		# face (which would grow the silhouette out the back on repeated hits).
		out[i] = _clamp_inside(ring, center, p, offset, core)
	return out


## The summed push of `impacts` on ring point `i` at `p`: a smooth dent from each within `radius`,
## a deep jagged notch from a chunk within its wider reach.
static func _dent_offset(p: Vector2, i: int, impacts: Array, radius: float) -> Vector2:
	var offset := Vector2.ZERO
	for impact in impacts:
		var d: float = p.distance_to(impact["pos"])
		var reach: float = (radius
				* (PhysicsDeformConfig.chunk_reach_scale if impact["chunk"] else 1.0))
		if d >= reach:
			continue
		var t := 1.0 - d / reach  # 1 at the impact, 0 at the edge of reach
		if impact["chunk"]:
			# Deep carve + seeded jitter so the bite looks torn, not smooth.
			var rng := RandomNumberGenerator.new()
			rng.seed = int(impact["seed"]) + i * 7
			var jag := 1.0 + rng.randf_range(
				-PhysicsDeformConfig.chunk_jitter,
				PhysicsDeformConfig.chunk_jitter,
			)
			offset += (impact["inward"] * impact["depth"] * PhysicsDeformConfig.chunk_depth
					* smoothstep(0.0, 1.0, t) * jag)
		else:
			offset += impact["inward"] * impact["depth"] * (t * t)
	return offset


## Ring point `i`'s `offset` with its push along the outline (a corner dented from one face slides
## along the other) cut to at most `NEIGHBOUR_REACH` of the way toward either neighbour, so no point
## passes one and folds the ring onto itself; a push into the face is untouched.
static func _cap_along(ring: PackedVector2Array, i: int, offset: Vector2) -> Vector2:
	var n := ring.size()
	var p := ring[i]
	for q: Vector2 in [ring[(i + n - 1) % n], ring[(i + 1) % n]]:
		var toward := (q - p).normalized()
		var cap := p.distance_to(q) * NEIGHBOUR_REACH
		var along := offset.dot(toward)
		if along > cap:
			offset -= toward * (along - cap)
	return offset


## Centroid (average) of a ring of points, used as the interior limit a dent can't pass.
static func _centroid(ring: PackedVector2Array) -> Vector2:
	if ring.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for pt in ring:
		sum += pt
	return sum / float(ring.size())


## A displaced boundary point kept inside the base outline. A dent may only cave the point
## INWARD: an offset that points out of the solid (e.g. an impact reaching a far-face point)
## leaves it put, and an inward offset is capped so it can't travel past the opposite face
## minus a thin margin, nor into the solid `core` around the shape's center (so opposite
## dents can't meet and fold a small silhouette inside out). Returns `p` unmoved or a point
## that stays inside.
static func _clamp_inside(ring: PackedVector2Array, center: Vector2, p: Vector2, offset: Vector2,
		core: float) -> Vector2:
	if offset == Vector2.ZERO:
		return p
	var dir := offset.normalized()
	# A step along the offset that leaves the outline means the dent would bulge outward.
	if not Geometry2D.is_point_in_polygon(p + dir * 0.05, ring):
		return p
	var span := _exit_distance(ring, p, dir)
	var limit := maxf(span - PhysicsDeformConfig.back_margin, 0.0)
	# Stop the point at the edge of the central core, so it keeps its distance from the
	# center. On big furniture this is slack (dents are far shallower); on a small body (a
	# character) it is what lets dents go deep without opposite edges crossing.
	var to_center := maxf(p.distance_to(center) - core, 0.0)
	limit = minf(limit, to_center)
	return p + dir * minf(offset.length(), limit)


## Distance from boundary point `p` along `dir` to where it exits `ring` again (the far
## face), or INF if the ray leaves without re-crossing. `p` is a vertex of `ring`, so
## intersections closer than a hair are its own adjacent edges and are ignored.
static func _exit_distance(ring: PackedVector2Array, p: Vector2, dir: Vector2) -> float:
	var start := p + dir * 0.05
	var far := p + dir * 100_000.0
	var best := INF
	var n := ring.size()
	for i in n:
		var hit = Geometry2D.segment_intersects_segment(start, far, ring[i], ring[(i + 1) % n])
		if hit != null:
			var dist: float = p.distance_to(hit)
			if dist > 0.1 and dist < best:
				best = dist
	return best


## Deformed perimeter polygon for a furniture shape — the single source both the visuals
## and the collider use. The central core scales with the shape, so a small body dents
## deeply without folding while big furniture (whose dents never reach the core) is unchanged.
## A dented silhouette is the same until the next hit, but it is asked for several times by each hit
## (the collider rebuild, the drop shadow, the drawing) and again by every repaint of a character,
## so the last few are kept, keyed by everything the result is made from.
static func shape_polygon(shape: String, size: Vector2, impacts: Array) -> PackedVector2Array:
	if impacts.is_empty():
		return _shape_polygon(shape, size, impacts)
	var inputs: Array = [
		shape, size, impacts, PhysicsDeformConfig.core_fraction,
		PhysicsDeformConfig.circle_points, PhysicsDeformConfig.rect_points_per_edge,
	] + _deform_knobs()
	return _cached(_polygon_cache, inputs, func(): return _shape_polygon(shape, size, impacts))


## The silhouette of `shape` at `size` dented by `impacts`, computed afresh (`shape_polygon` caches
## it); its ring from the kept unit ring when `kept`, else made afresh (`_ring`).
static func _shape_polygon(
	shape: String,
	size: Vector2,
	impacts: Array,
	kept := true,
) -> PackedVector2Array:
	var core := minf(size.x, size.y) * 0.5 * PhysicsDeformConfig.core_fraction
	return deform(_ring(shape, size, kept), impacts, PhysicsDeformConfig.radius, core)


## Deformed polygon for one wall segment: a thick rectangle (quad) along the centerline
## a→b, ends extended by half-thickness (like the collider), long edges subdivided so
## dents have resolution. Shared by the wall visuals and the wall collider rebuild.
static func wall_polygon(
	a: Vector2,
	b: Vector2,
	thickness: float,
	impacts: Array,
) -> PackedVector2Array:
	if impacts.is_empty():
		return _wall_polygon(a, b, thickness, impacts)
	# A dented segment is the same until its next hit, and a wall repaints all its segments whenever
	# one is struck: the last few are kept like `shape_polygon`'s, keyed by everything they are made
	# from.
	var inputs: Array = [a, b, thickness, impacts] + _deform_knobs()
	var make := func(): return _wall_polygon(a, b, thickness, impacts)
	return _cached(_wall_cache, inputs, make).duplicate()


## The `PhysicsDeformConfig` knobs `deform` reads, which every kept dented polygon is keyed by (a
## knob missing here would let a cache serve a polygon made with its old value).
static func _deform_knobs() -> Array:
	return [
		PhysicsDeformConfig.radius, PhysicsDeformConfig.back_margin,
		PhysicsDeformConfig.chunk_reach_scale, PhysicsDeformConfig.chunk_jitter,
		PhysicsDeformConfig.chunk_depth,
	]


## The polygon kept in `cache` for `inputs`, else `make`'s, kept (the cache starts over once it
## holds `POLYGON_CACHE_SIZE`). The kept polygon itself is returned: a caller that hands it on to be
## changed copies it.
static func _cached(cache: Dictionary, inputs: Array, make: Callable) -> PackedVector2Array:
	var key := inputs.hash()
	var kept = cache.get(key)
	if kept != null and kept[0] == inputs:
		return kept[1]
	var poly: PackedVector2Array = make.call()
	if cache.size() >= POLYGON_CACHE_SIZE:
		cache.clear()
	cache[key] = [inputs.duplicate(true), poly]
	return poly


## The polygon of one wall segment, computed afresh (`wall_polygon` keeps the dented ones).
static func _wall_polygon(
	a: Vector2,
	b: Vector2,
	thickness: float,
	impacts: Array,
) -> PackedVector2Array:
	var dir := (b - a).normalized()
	var half_n := dir.orthogonal() * (thickness * 0.5)
	var s := a - dir * (thickness * 0.5)
	var e := b + dir * (thickness * 0.5)
	var ring := PackedVector2Array()
	var steps := 16
	for i in steps + 1:  # near edge (+half_n): s -> e
		ring.append(s.lerp(e, float(i) / float(steps)) + half_n)
	for i in steps + 1:  # far edge (-half_n): e -> s
		ring.append(e.lerp(s, float(i) / float(steps)) - half_n)
	return deform(ring, impacts, PhysicsDeformConfig.radius)


## True when `poly` is a valid simple polygon the engine can triangulate. A silhouette
## deformed by many overlapping dents on a small body can pinch itself into a degenerate
## (self-touching) polygon; `draw_colored_polygon` rejects those, so callers check this first
## and skip the deformed polygon that frame.
static func is_valid_polygon(poly: PackedVector2Array) -> bool:
	return poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty()


## Decompose a (possibly concave) polygon into the convex pieces a static collider is rebuilt from
## (`shapes_of` makes their shapes), as their points (`PackedVector2Array` each); [] for a
## degenerate polygon (caller keeps the old collider). Merges the triangulation itself rather than
## calling `Geometry2D.decompose_polygon_in_convex`, which logs "Convex decomposing failed!" on some
## near-degenerate polygons that do triangulate. Pure: it touches no shared state and makes no
## resource, so it may run on a worker thread (Objects works out the pieces of every collider
## rebuilt in a frame together).
static func convex_pieces(polygon: PackedVector2Array) -> Array:
	var out: Array = []
	if not is_valid_polygon(polygon):
		return out
	for piece in _convex_pieces(polygon):
		var points := PackedVector2Array()
		for i in piece:
			points.append(polygon[i])
		out.append(points)
	return out


## `[wall_polygon(a, b, thickness, impacts), its convex_pieces]`, worked out afresh: pure (no cache
## read or written, no resource made), so it may run on a worker thread with its own copy of
## `impacts`. Objects cuts a dented wall segment's outline this way as it is struck.
static func cut_wall(a: Vector2, b: Vector2, thickness: float, impacts: Array) -> Array:
	var poly := _wall_polygon(a, b, thickness, impacts)
	return [poly, convex_pieces(poly)]


## Convex pieces of `polygon` as vertex-index loops (Hertel-Mehlhorn): start from its
## triangulation, wound like the polygon, and keep merging two pieces across a shared edge
## while the union stays convex. Needs `is_valid_polygon(polygon)`.
static func _convex_pieces(polygon: PackedVector2Array) -> Array:
	# The scan takes the first pair, in piece order, that is neighbours across an edge and whose
	# union is convex, merges it and scans again. Only neighbours can merge, so they are found
	# through a map of who owns each directed edge (a piece's edge i -> j meets its neighbour's j ->
	# i), and a neighbouring pair that failed is remembered by the pieces' ids (the failure holds
	# until one of them changes). A scan that starts over need not walk the pieces before the merge
	# again: every pair there was tried and failed, but those with the piece the merge just made
	# (`fresh`), which are tried first, in order, before the scan goes on from it. The same merges
	# happen in the same order as a scan from the start.
	var scan := PieceScan.new(polygon)
	# the scan goes on from this piece; every pair before it has failed, but those with `fresh`
	var from := 0
	var fresh := -1  # the piece the last merge made (-1: none yet)
	while true:
		var found: Array = scan.merge_with(fresh) if fresh > 0 else []
		if found.is_empty():
			found = scan.first_merge(from)
		if found.is_empty():
			break
		from = scan.apply(found[0], found[1])
		fresh = from
	return scan.pieces


## The ids of the pieces across each edge of piece `loop`, in the loop's order (`owner` as
## `_own_edges` keeps it).
static func _neighbour_ids(owner: Dictionary, loop: Array, count: int) -> Array:
	var out: Array = []
	for k in loop.size():
		var other = owner.get(int(loop[(k + 1) % loop.size()]) * count + int(loop[k]))
		if other != null:
			out.append(other)
	return out


## Record (`add`) or forget the directed edges of piece `loop` in `owner`, keyed
## `from * count + to`, as piece `id`'s.
static func _own_edges(owner: Dictionary, loop: Array, id: int, count: int, add: bool) -> void:
	for k in loop.size():
		var key: int = int(loop[k]) * count + int(loop[(k + 1) % loop.size()])
		if add:
			owner[key] = id
		else:
			owner.erase(key)


## Cross product of the turn at `b` on the way a -> b -> c (positive = counter-clockwise).
static func _turn(polygon: PackedVector2Array, a: int, b: int, c: int) -> float:
	return (polygon[b] - polygon[a]).cross(polygon[c] - polygon[b])


## The loop `a` + `b` form when they share an edge (a runs i -> j, b runs j -> i), or [] when
## they share none.
static func _merge_across_edge(a: Array, b: Array) -> Array:
	for k in a.size():
		var i: int = a[k]
		var j: int = a[(k + 1) % a.size()]
		var m := b.find(j)
		if m == -1 or b[(m + 1) % b.size()] != i:
			continue
		var out: Array = []
		for n in a.size():  # a rotated to start at j and end at i
			out.append(a[(k + 1 + n) % a.size()])
		for n in range(2, b.size()):  # b's vertices strictly between i and j
			out.append(b[(m + n) % b.size()])
		return out
	return []


## True when `loop` turns the polygon's way (`sign_` = +1 / -1, straight allowed) at its vertex
## number `at`.
static func _turns_right_at(
	polygon: PackedVector2Array,
	loop: Array,
	at: int,
	sign_: float,
) -> bool:
	var n := loop.size()
	var a: Vector2 = polygon[loop[(at - 1 + n) % n]]
	var b: Vector2 = polygon[loop[at]]
	var c: Vector2 = polygon[loop[(at + 1) % n]]
	return not ((b - a).cross(c - b) * sign_ < 0.0)


## How far (0..1, `Color.darkened`'s weight) a mesh darkens a shape that has taken
## `damage_total` damage: up to `PhysicsDeformLookConfig.darken_max`, reached at
## `PhysicsDeformLookConfig.darken_full`.
## A textured shape is shown in white darkened by it, so a caller showing a textured shape's own
## way draws it in the same colour.
static func darken(damage_total: float) -> float:
	if damage_total <= 0.0 or PhysicsDeformLookConfig.darken_full <= 0.0:
		return 0.0
	return (clampf(damage_total / PhysicsDeformLookConfig.darken_full, 0.0, 1.0)
			* PhysicsDeformLookConfig.darken_max)


## `_convex_pieces`' merge scan over one polygon: the pieces as vertex-index loops (from its
## triangulation, wound like the polygon), each piece's id, who owns each directed edge
## (`_own_edges`) and the neighbouring pairs that failed to merge, by the pieces' ids.
class PieceScan:
	## The pieces, as vertex-index loops, in order.
	var pieces: Array = []
	## The polygon cut.
	var _polygon: PackedVector2Array
	## +1 / -1: the polygon's winding.
	var _sign: float
	## Each piece's id, by its position in `pieces`.
	var _ids: Array = []
	## The id the next merged piece takes.
	var _next_id := 0
	## The piece id owning each directed edge (`_own_edges`).
	var _owner := {}
	## The neighbouring pairs that failed to merge, by their ids.
	var _failed := {}
	## The polygon's vertex count (the edge keys' stride).
	var _count := 0

	func _init(polygon: PackedVector2Array) -> void:
		_polygon = polygon
		_sign = -1.0 if Geometry2D.is_polygon_clockwise(polygon) else 1.0
		var tris := Geometry2D.triangulate_polygon(polygon)
		for t in range(0, tris.size(), 3):
			var tri := [tris[t], tris[t + 1], tris[t + 2]]
			if Deformation._turn(polygon, tri[0], tri[1], tri[2]) * _sign < 0.0:
				tri = [tri[0], tri[2], tri[1]]
			pieces.append(tri)
		_count = polygon.size()
		_ids = range(pieces.size())
		_next_id = pieces.size()
		for p in pieces.size():
			Deformation._own_edges(_owner, pieces[p], _ids[p], _count, true)

	## The first merge of the piece at `fresh` with a neighbour before it, in their order, as
	## `[Vector2i(that one, fresh), union]`, or [] when none merges.
	func merge_with(fresh: int) -> Array:
		var before: Array = []
		for other in Deformation._neighbour_ids(_owner, pieces[fresh], _count):
			var x: int = _ids.find(other)
			if x < fresh:
				before.append(x)
		before.sort()
		for x in before:
			var union := _try_merge(x, fresh)
			if not union.is_empty():
				return [Vector2i(x, fresh), union]
		return []

	## The first merge of a piece from `from` on with a neighbour after it, as
	## `[Vector2i(a, b), union]`, or [] when none merges.
	func first_merge(from: int) -> Array:
		for a in range(maxi(from, 0), pieces.size()):
			var neighbours: Array = []
			for other in Deformation._neighbour_ids(_owner, pieces[a], _count):
				var b: int = _ids.find(other)
				if b > a:
					neighbours.append(b)
			neighbours.sort()
			for b in neighbours:
				var union := _try_merge(a, b)
				if not union.is_empty():
					return [Vector2i(a, b), union]
		return []

	## The convex piece the neighbouring pieces at positions `a` < `b` merge into
	## (`_merge_across_edge`), or [] when they do not; a pair that does not is remembered (by the
	## pieces' ids) and not tried again.
	func _try_merge(a: int, b: int) -> Array:
		var pair: int = (mini(_ids[a], _ids[b]) * Deformation.PIECE_PAIR_STRIDE
				+ maxi(_ids[a], _ids[b]))
		if _failed.has(pair):
			return []
		var union := Deformation._merge_across_edge(pieces[a], pieces[b])
		# Both pieces are convex already, so only the two corners where they now join can turn the
		# wrong way: the union's first vertex and the one ending piece a's run (see
		# _merge_across_edge).
		if union.is_empty() or not (Deformation._turns_right_at(_polygon, union, 0, _sign)
				and Deformation._turns_right_at(_polygon, union, pieces[a].size() - 1, _sign)):
			_failed[pair] = true
			return []
		return union

	## Put `union` in place of the pieces at `merge` (x < y), under a new id; returns where it is.
	func apply(merge: Vector2i, union: Array) -> int:
		Deformation._own_edges(_owner, pieces[merge.x], _ids[merge.x], _count, false)
		Deformation._own_edges(_owner, pieces[merge.y], _ids[merge.y], _count, false)
		pieces[merge.x] = union
		_ids[merge.x] = _next_id
		_next_id += 1
		Deformation._own_edges(_owner, union, _ids[merge.x], _count, true)
		pieces.remove_at(merge.y)
		_ids.remove_at(merge.y)
		return merge.x
