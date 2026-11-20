extends RefCounted
## Shared helper for `navigation/bake_from_twins_matches_colliders` (not a test itself): what the
## navigation bake read of a world before #194 del2d-c, from the 2D colliders (the engine's parse of
## the static bodies for the walls, each `RigidBody2D`'s and `CharacterBody2D`'s collision shapes
## for the holes), kept as the reference the bake from the twins is measured against.

const CIRCLE_SEGMENTS := 10


## The obstruction outlines of `house`'s walls as the engine's parse of its static colliders gave
## them (the house's local frame, moved by `frame`, snapped to the map's grid), the doors off the
## solid layer for the parse.
static func walls(house: Node2D, agent_radius: float, frame := Transform2D.IDENTITY) -> Dictionary:
	var source := NavigationMeshSourceGeometryData2D.new()
	var doors := NavLeaves.doors_of(house)
	var layers: Array[int] = []
	for door in doors:
		layers.append(door.collision_layer)
		door.collision_layer = 0
	NavigationServer2D.parse_source_geometry_data(
		NavSource.new_polygon(agent_radius),
		source,
		house,
	)
	for i in doors.size():
		doors[i].collision_layer = layers[i]
	var obstruction: Array = source.get_obstruction_outlines()
	if frame != Transform2D.IDENTITY:
		var moved: Array = []
		for outline: PackedVector2Array in obstruction:
			moved.append(frame * outline)
		obstruction = moved
	return NavSource.walls(
		NavSource.on_grid(obstruction),
		source.get_traversable_outlines(),
		source.get_projected_obstructions(),
	)


## The footprints of every solid piece under `house` and the doors' leaves standing clear of their
## doorways, cut from the 2D shapes.
static func furniture(house: Node2D) -> Array:
	var out: Array = []
	for node in house.find_children("*", "RigidBody2D", true, false):
		var hull := cut(node as RigidBody2D)
		if not hull.is_empty():
			out.append(hull)
	NavLeaves.append_holes(out, house)
	return out


## The footprints of the living characters at rest under `root`, cut from the 2D shapes.
static func characters(root: Node) -> Array:
	var out: Array = []
	for node in root.get_children():
		var body := node as CharacterBody2D
		if (body == null
				or body.collision_layer == 0
				or TwinSpace.real_velocity_of(body).length() >= NavBuilder.REST_SPEED):
			continue
		var hull := cut(body)
		if not hull.is_empty():
			out.append(hull)
	return out


## The world-space footprint of `body`: the convex hull of its collision shapes, each grown by
## `NavBuilder.OBSTACLE_MARGIN`, as an open ring.
static func cut(body: Node2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	for child in body.get_children():
		var col := child as CollisionShape2D
		if col == null or col.shape == null:
			continue
		points.append_array(_footprint_world(col))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1:
		hull.remove_at(hull.size() - 1)
	return hull if hull.size() >= 3 else PackedVector2Array()


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
		var points := (shape as ConvexPolygonShape2D).points
		local = points
		for poly: PackedVector2Array in Geometry2D.offset_polygon(points, margin):
			if poly.size() > local.size():
				local = poly
	var out := PackedVector2Array()
	for p in local:
		out.append(col.global_transform * p)
	return out
