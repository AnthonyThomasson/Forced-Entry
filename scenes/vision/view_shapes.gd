extends RefCounted
## Vision domain: the blocking shapes round an eye, read from the twin space (a 3D shape query on
## `SightRay.MASK` over the column above the viewer's `see_over`, its eye height, never a walk of
## the scene tree). A shape blocks sight when it stands above `see_over` (walls, tall furniture);
## lower furniture is seen over. Each shape a ray hits is turned into the convex polygon it casts on
## the floor (`TwinShapes.footprint_of`), which gives the corners where the cone's boundary can jump
## and the point a ray through that one shape leaves it (a `Wall` is one body of many segment
## shapes: only the shape the ray hit counts). What it read is kept for one build (`reset`): the
## world moves between frames.

## How thick (px) the slab a query reads is, from the height the plan cast runs at up: a shape that
## stands across it is one a ray at the eye can meet (a lintel over the eye, a piece hung above it,
## are not). As thin as the ray is not possible: the physics engine cannot build a convex hull of
## the sector's region thinner than a few times its margin (0.04 px), so it is a little thicker, and
## a piece whose base is within it above the ray adds a corner the ray passes under (harmless: that
## corner's rays reach what they reach).
const SLAB := 2.0
## How far (px) past the face a ray hit the point is taken that asks which shapes the ray runs into
## there, and the most shapes that point can be in.
const PROBE := 0.1
const PROBE_RESULTS := 32
## The shapes a query first asks for; a query that comes back full asks again for `GROWTH` times as
## many, until one comes back with room to spare, so no shape in reach is ever dropped.
const FIRST_RESULTS := 512
const GROWTH := 4

## The height (px) a shape must be above to block sight: the viewer's eye, set by the cone for each
## build.
var see_over := BodyHeights.eye(BodyHeights.STAND)
var _column := CylinderShape3D.new()
var _region := ConvexPolygonShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _probe := PhysicsPointQueryParameters3D.new()
## The colliders (by instance id) whose leaving the tree this has hooked, to drop what is kept of
## them.
var _hooked := {}
## The floor polygon of a shape, by twin instance id then shape index. Each entry holds the
## transform and shape resource it was made from; a move or replacement is read at lookup, and a
## body's shape-change signals clear the cache.
var _polygons := {}
## How many polygon reads reused an earlier rebuild's static shape.
var polygon_reuses := 0
## The polygons of a shape already asked for in this rebuild, by collider instance id
## then shape index: each is checked against its body once, then served from here (`reset` empties
## it, as do a dent or re-cut and a collider leaving the tree).
var _memo := {}
## How many polygon reads the memo answered (a fast-path test's observable).
var memo_hits := 0
## How many polygon reads checked a shape against its body: at most one a polygon a
## rebuild (a fast-path test's observable).
var validations := 0
## How many shape queries `corners` has asked in all (a job counts them as engine work).
var queries := 0
## The call every shape edit and child change makes (`_clear_polygons`), made once.
var _clear_cb := Callable(self, "_clear_polygons")


func _init() -> void:
	_query.collision_mask = SightRay.MASK
	_query.shape = _column
	_probe.collision_mask = SightRay.MASK


## Forget what the last build read.
func reset() -> void:
	_memo.clear()


## Whether `a` comes before `b`: the lesser x, then the lesser y. Two corners less than half a pixel
## apart are one corner (`corners`); which of them stands for it is this one, whatever order the
## physics query listed the shapes in.
static func _before(a: Vector2, b: Vector2) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## The distinct corners, in world space, of every blocking shape within `reach` of `from`, or, with
## a `region` (world-space points, the hull of what the rays can pass through), of those that touch
## it. A job does this in two steps (`read_hits`, then `fold_corners` a chunk of hits at a time);
## this is the two at once.
func corners(
	space: PhysicsDirectSpaceState3D,
	from: Vector2,
	reach: float,
	exclude: Array,
	region := PackedVector2Array(),
) -> Array:
	var hits := read_hits(space, from, reach, exclude, region)
	var seen := {}
	fold_corners(hits, 0, hits.size(), seen)
	return seen.values()


## The shapes the region (or, with none, the column of `reach` about `from`) touches: the shape
## query alone, asked again while it comes back full.
func read_hits(
	space: PhysicsDirectSpaceState3D,
	from: Vector2,
	reach: float,
	exclude: Array,
	region := PackedVector2Array(),
) -> Array[Dictionary]:
	var level := see_over + SightRay.LEVEL_OVER
	if region.is_empty():
		_column.radius = reach * RenderConfig.unit
		_column.height = SLAB * RenderConfig.unit
		_query.shape = _column
		_query.transform = Transform3D(Basis.IDENTITY, PlanSpace.lift(from, level + SLAB * 0.5))
	else:
		var cloud := PackedVector3Array()
		for point in region:
			cloud.append(PlanSpace.lift(point - from, 0.0))
			cloud.append(PlanSpace.lift(point - from, SLAB))
		_region.points = cloud
		_query.shape = _region
		_query.transform = Transform3D(Basis.IDENTITY, PlanSpace.lift(from, level))
	_query.exclude = exclude
	_probe.exclude = exclude
	return _shapes_in_reach(space)


## Fold the corners of `hits[start]` up to `stop` (exclusive) into `seen`, which maps a corner's
## half-pixel cell to the corner there: of two corners in one cell the lesser (`_before`) stays,
## and the cells are kept in the order first met (`seen.values()` are the distinct corners in that
## order). `seen` carries across the chunks of one job, which fold to the same corners as one
## `corners` read. A shape's own cells are kept with its polygon (`_entry_of`) and merged in one
## step; only a shape that shares a cell with one met before is looked at corner by corner.
func fold_corners(hits: Array[Dictionary], start: int, stop: int, seen: Dictionary) -> void:
	var last_id := 0
	var last_memo: Dictionary = {}
	for i in range(start, stop):
		var held: Variant = hits[i]["collider"]
		if not _blocks(held):
			continue
		var id: int = held.get_instance_id()
		if id != last_id:
			last_id = id
			last_memo = _memo.get(id, {})
			if last_memo.is_empty():
				_memo[id] = last_memo
		var index: int = hits[i]["shape"]
		var entry: Variant = last_memo.get(index)
		if entry == null:
			entry = _validated_entry(held, id, index)
			last_memo[index] = entry
		else:
			memo_hits += 1
		var cells: Dictionary = entry[3]
		var before := seen.size()
		seen.merge(cells)
		if seen.size() - before < cells.size():
			_keep_lesser(cells, seen)


## Whether the shape a hit names still blocks sight: its body is not freed (a hit is held across
## ticks, and a glass door's twin may have been retwinned since: a freed one that did not block
## gives no corner) and is not looked through (`SightRay.looks_through`, its answer read off the
## meta here: the call makes it once for a twin).
func _blocks(held: Variant) -> bool:
	if not is_instance_valid(held):
		return false
	var known: Variant = held.get_meta(SightRay.THROUGH_META, -1)
	return not known if known is bool else not SightRay.looks_through(held)


## Of the cells `seen` held before a shape's own were merged in, the lesser corner stays.
func _keep_lesser(cells: Dictionary, seen: Dictionary) -> void:
	for key: int in cells:
		var point: Vector2 = cells[key]
		if _before(point, seen[key]):
			seen[key] = point


## Every blocking shape the query column touches. The physics query returns at most as many as it is
## asked for, so a result that comes back full is asked again with a larger cap.
func _shapes_in_reach(space: PhysicsDirectSpaceState3D) -> Array[Dictionary]:
	var cap := FIRST_RESULTS
	queries += 1
	var hits := space.intersect_shape(_query, cap)
	while hits.size() >= cap:
		cap *= GROWTH
		queries += 1
		hits = space.intersect_shape(_query, cap)
	return hits


## The floor polygon of shape `index` of the twin `collider` (empty for a shape with no extent: a
## plane or a concave mesh). A shape is checked against its twin once a rebuild.
func polygon_of(collider: Object, index: int) -> PackedVector2Array:
	return _entry_of(collider, index)[2]


## The entry of a shape with no polygon (a plane, a concave mesh, no body).
static func _no_entry() -> Array:
	return [null, null, PackedVector2Array(), {}]


## What is kept of shape `index` of `collider`: `[transform, shape, polygon, cells]`, `cells` being
## the corners of the polygon by their half-pixel cell (`corners`' dedupe), made once with it.
## Checked against the body once a rebuild, then served from the memo.
func _entry_of(collider: Object, index: int) -> Array:
	var id := collider.get_instance_id()
	var in_memo: Variant = _memo.get(id)
	if in_memo == null:
		in_memo = {}
		_memo[id] = in_memo
	var held: Variant = in_memo.get(index)
	if held != null:
		memo_hits += 1
		return held
	var entry := _validated_entry(collider, id, index)
	in_memo[index] = entry
	return entry


## The entry of a shape: the kept one while its transform and shape resource are those it was made
## from, else one made now and kept.
func _validated_entry(collider: Object, id: int, index: int) -> Array:
	validations += 1
	if not collider is CollisionObject3D:
		return _no_entry()
	var body := collider as CollisionObject3D
	var owner_id := body.shape_find_owner(index)
	if owner_id < 0:
		return _no_entry()
	var shape := _shape_at(body, owner_id, index)
	if shape == null:
		return _no_entry()
	var transform := body.global_transform * body.shape_owner_get_transform(owner_id)
	var by_shape: Variant = _polygons.get(id)
	if by_shape == null:
		by_shape = {}
		_polygons[id] = by_shape
	var entry: Variant = by_shape.get(index)
	if entry != null and entry[0] == transform and is_same(entry[1], shape):
		polygon_reuses += 1
		return entry
	_watch_polygon_shape(collider, shape)
	var polygon := TwinShapes.footprint_of(shape, transform)
	var cells := {}
	for point in polygon:
		var cell := Vector2i((point * 2.0).round())
		var key := (cell.x << 32) + cell.y
		if not cells.has(key) or _before(point, cells[key]):
			cells[key] = point
	entry = [transform, shape, polygon, cells]
	by_shape[index] = entry
	return entry


## The shape resource of shape `index`, which belongs to the owner `owner_id` of `body`.
func _shape_at(body: CollisionObject3D, owner_id: int, index: int) -> Shape3D:
	for k in body.shape_owner_get_shape_count(owner_id):
		if body.shape_owner_get_shape_index(owner_id, k) == index:
			return body.shape_owner_get_shape(owner_id, k)
	return null


## How many polygons the memo of this rebuild holds.
func memoed() -> int:
	var count := 0
	for by_shape: Dictionary in _memo.values():
		count += by_shape.size()
	return count


## A dent, re-cut or in-place shape edit invalidates every kept polygon; a move misses on lookup.
func _watch_polygon_shape(collider: Object, shape: Shape3D) -> void:
	var changed := _clear_cb
	if collider is Node:
		var id := collider.get_instance_id()
		if not _hooked.has(id):
			_hooked[id] = true
			var node := collider as Node
			node.tree_exiting.connect(_forget.bind(id), CONNECT_ONE_SHOT)
			for signal_name in [&"child_entered_tree", &"child_exiting_tree", &"changed"]:
				if node.has_signal(signal_name) and not node.is_connected(signal_name, changed):
					node.connect(signal_name, changed)
	if shape != null and not shape.changed.is_connected(changed):
		shape.changed.connect(changed)


## Drop every kept polygon after a shape edit (one body can share a resource with another).
func _clear_polygons(_child: Variant = null) -> void:
	_polygons.clear()
	_memo.clear()


## How far a ray from `origin` along `dir`, which has just hit a blocker there, runs before it
## leaves the solid it entered: the farthest it leaves any blocking shape that holds the point
## `PROBE` px along it, -1 when it leaves such a shape through no edge, and 0 when no blocking shape
## holds the point (the ray only touches a corner). The shapes of the viewer itself are left out
## by the `exclude` of the last `corners` call, so that runs first in every build. Where shapes
## overlap or touch (a wall's segments at a corner, the walls of two rooms sharing a face, the
## pieces a dented wardrobe is cut into) the physics query may name any of them for the same ray,
## from one frame to the next, and one it names need not even be entered: so the answer is read off
## no shape the ray hit, but off the shapes `space` says hold that point.
func far_exit(space: PhysicsDirectSpaceState3D, hit: Dictionary, dir: Vector2) -> float:
	var origin: Vector2 = hit["position"]
	var polygons: Array = []
	_probe.position = PlanSpace.lift(origin + dir * PROBE, see_over + SightRay.LEVEL_OVER)
	for found in space.intersect_point(_probe, PROBE_RESULTS):
		if not SightRay.looks_through(found["collider"]):
			polygons.append(polygon_of(found["collider"], found["shape"]))
	var farthest := -INF
	for polygon: PackedVector2Array in polygons:
		farthest = maxf(farthest, exit_distance(polygon, origin, dir))
	return 0.0 if farthest == -INF else farthest


## How far a ray from `origin` (on or in the shape) along `dir` runs before it leaves the convex
## `polygon`, or -1 when it does not.
func exit_distance(polygon: PackedVector2Array, origin: Vector2, dir: Vector2) -> float:
	var turn := signf(_signed_area(polygon))
	var exit := INF
	for i in polygon.size():
		var edge := polygon[(i + 1) % polygon.size()] - polygon[i]
		# The edge's outward normal; the ray leaves through the nearest edge it heads out of.
		var normal := Vector2(edge.y, -edge.x) * turn
		var along := normal.dot(dir)
		if along > 0.000001:
			exit = minf(exit, normal.dot(polygon[i] - origin) / along)
	return exit if exit < INF else -1.0


## Twice the signed area of `polygon`; its sign says which way it winds.
func _signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return area


## Drop what is kept of the collider `id` (it left the tree).
func _forget(id: int) -> void:
	_hooked.erase(id)
	_polygons.erase(id)
	_memo.erase(id)
