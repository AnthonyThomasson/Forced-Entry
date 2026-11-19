class_name WearFactory
## Objects-domain factory: turns where wear gathers in a room (World-Gen's placement: a few
## clusters, each by a wall, a corner or a piece of furniture, seeded) into the room's wear: a
## data node (decals/room_wear.gd) that decides each cluster's marks on the room's floor and
## wall, which the 3D render lays as decals. World-Gen never touches the node's fields.

const RoomWear = preload("res://scenes/objects/decals/room_wear.gd")


## Build the wear of the room `rect` (in `parent`'s space) under `parent`, as `plan` lays it: its
## floor is the plan's `floor_definition` (a catalogue floor: the marks follow its
## `art_opts.pattern` and colour), its walls `wall_thickness` thick, and its `clusters` are
## `{ pos, wall, seed }` (the cluster's centre; the free stretch of wall it is by as `[a, b]`, its
## centre line between two points, or `[]`; the seed of its marks), all in `parent`'s space. Added
## after the house's floors and walls, so it draws over them. Returns the node (one per room: the
## CanvasItem drawing that room's wear). The room's floor and walls in `parent` (the ones at
## `rect`'s corner) are told of it as their `wear`, for the 3D render to lay the marks on them.
static func spawn(rect: Rect2, plan: WearPlan, wear_name: String, parent: Node) -> Node2D:
	var wear: Node2D = RoomWear.new()
	wear.name = wear_name
	wear.setup(rect, plan.floor_definition, plan.wall_thickness, plan.clusters)
	for sibling in parent.get_children():
		if not sibling is Node2D:
			continue
		if (sibling as Node2D).position != rect.position or sibling.get("size") != rect.size:
			_lend_marks(wear, sibling)
		elif sibling.is_in_group(&"floors") or sibling.has_method(&"wall_segments"):
			sibling.set(&"wear", wear)
	parent.add_child(wear)
	return wear


## Tell the wall `other` (not the room's own) of `wear` if a mark of it lies on a segment `other`
## owns: a stretch two rooms share is built once, so the room that does not own it has its marks on
## the wall that does (`Wall.neighbour_wear`).
static func _lend_marks(wear: Node2D, other: Node) -> void:
	if not other.has_method(&"has_segment") or not other.has_method(&"wall_segments"):
		return
	var segments: Array = other.call(&"wall_segments")
	var origin: Vector2 = (other as Node2D).position
	for mark: Dictionary in wear.call(&"wall_marks"):
		var at: Vector2 = wear.position + (mark["at"] as Vector2) - origin
		for i in segments.size():
			var seg: PackedVector2Array = segments[i]
			var off := Geometry2D.get_closest_point_to_segment(at, seg[0], seg[1]).distance_to(at)
			if off < 1.0 and other.call(&"has_segment", i):
				(other.get(&"neighbour_wear") as Array).append(wear)
				return
