class_name NavHoles extends RefCounted
## Navigation domain: the footprints a bake carves as holes, measured from the colliders. A body's
## footprint is the convex hull of its collision shapes (`cut`); `NavBuilder.furniture_holes` and
## `character_holes` hand them out. `walks` and `cuts` count the work done, for the tests.

## Hulls kept per body (`hull_of`) before the freed bodies' are dropped.
const HULLS_KEPT := 512
## Segment count approximating a circular footprint as an obstruction polygon.
const CIRCLE_SEGMENTS := 10

## Tree walks made to find the furniture, and footprints cut from a body's shapes, since the start.
static var walks := 0
static var cuts := 0
## Body instance id -> [inputs, hull] as `hull_of` last made it.
static var _hulls := {}


## The footprints of every solid piece under `house`, in the order a walk of its descendants finds
## them, then the doors' leaves standing clear of their doorways (`NavLeaves.hole`).
static func furniture(house: Node2D) -> Array:
	if not house.is_inside_tree():
		return plain(house)
	return NavPieces.of(house).holes()


## `furniture` with nothing kept: every piece's footprint cut afresh, the reference the cached one
## equals.
static func plain(house: Node2D) -> Array:
	var out: Array = []
	for node in house.find_children("*", "RigidBody2D", true, false):
		var hull := cut(node as RigidBody2D)
		if not hull.is_empty():
			out.append(hull)
	NavLeaves.append_holes(out, house)
	return out


## The world-space footprint of `body`, kept with what it was made from (`inputs_of`) and cut again
## only when that changes: a character at rest is measured every tick, a dented piece's hull costs a
## grown outline per convex piece.
static func hull_of(body: Node2D) -> PackedVector2Array:
	var inputs := inputs_of(body)
	var kept: Array = _hulls.get(body.get_instance_id(), [])
	if not kept.is_empty() and kept[0] == inputs:
		return (kept[1] as PackedVector2Array).duplicate()
	var hull := cut(body)
	if _hulls.size() >= HULLS_KEPT:
		for id in _hulls.keys():
			if not is_instance_id_valid(id):
				_hulls.erase(id)
	_hulls[body.get_instance_id()] = [inputs, hull.duplicate()]
	return hull


## The world-space footprint of `body` cut afresh: the convex hull of its collision shapes as an
## open ring (the closing point dropped), or empty when fewer than three points come out of it.
static func cut(body: Node2D) -> PackedVector2Array:
	cuts += 1
	var points := PackedVector2Array()
	for child in body.get_children():
		var col := child as CollisionShape2D
		if col == null or col.shape == null:
			continue
		points.append_array(_footprint_world(col))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1:
		hull.remove_at(hull.size() - 1)  # convex_hull closes the ring by repeating the first point
	return hull if hull.size() >= 3 else PackedVector2Array()


## Everything `hull_of` makes `body`'s hull from: for each collision shape, its global transform and
## what `_footprint_world` reads of its shape (a rect's size, a circle's radius, a convex piece's
## points; the shape itself for any other kind).
static func inputs_of(body: Node2D) -> Array:
	var out: Array = []
	for child in body.get_children():
		var col := child as CollisionShape2D
		if col == null or col.shape == null:
			continue
		out.append(col.global_transform)
		var shape := col.shape
		if shape is RectangleShape2D:
			out.append((shape as RectangleShape2D).size)
		elif shape is CircleShape2D:
			out.append((shape as CircleShape2D).radius)
		elif shape is ConvexPolygonShape2D:
			out.append((shape as ConvexPolygonShape2D).points)
		else:
			out.append(shape)
	return out


## The collider's footprint as a closed polygon in WORLD space, grown by
## `NavBuilder.OBSTACLE_MARGIN`. Reads only the generic Shape2D: the intact primitives
## (RectangleShape2D / CircleShape2D) and the ConvexPolygonShape2D a damaged piece's collider is
## rebuilt into (its points inflated by the margin via Geometry2D.offset_polygon), mapped through
## the collider's global transform so an offset or rotated collider still lines up. Empty for an
## unsupported shape.
static func _footprint_world(col: CollisionShape2D) -> PackedVector2Array:
	var margin := NavBuilder.OBSTACLE_MARGIN
	var shape := col.shape
	var local := PackedVector2Array()
	if shape is RectangleShape2D:
		var h := (shape as RectangleShape2D).size * 0.5 + Vector2(margin, margin)
		local = PackedVector2Array([
			Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
		])
	elif shape is CircleShape2D:
		var r := (shape as CircleShape2D).radius + margin
		for i in CIRCLE_SEGMENTS:
			var a := TAU * float(i) / float(CIRCLE_SEGMENTS)
			local.append(Vector2(cos(a), sin(a)) * r)
	elif shape is ConvexPolygonShape2D:
		# A deformed piece: inflate its silhouette by the margin. offset_polygon returns the grown
		# ring(s); take the largest (a convex grow yields one), falling back to the raw points.
		var grown := Geometry2D.offset_polygon((shape as ConvexPolygonShape2D).points, margin)
		local = _largest_polygon(grown, (shape as ConvexPolygonShape2D).points)
	var xform := col.global_transform
	var out := PackedVector2Array()
	for p in local:
		out.append(xform * p)
	return out


## The polygon with the most points among `polys` (Geometry2D.offset_polygon's output) and
## `fallback` (`fallback` on a tie).
static func _largest_polygon(polys: Array, fallback: PackedVector2Array) -> PackedVector2Array:
	var best := fallback
	for poly in polys:
		if (poly as PackedVector2Array).size() > best.size():
			best = poly
	return best
