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
		if not sibling is Node2D or (sibling as Node2D).position != rect.position:
			continue
		if sibling.is_in_group(&"floors") and sibling.get("size") == rect.size:
			sibling.set(&"wear", wear)
		elif sibling.has_method(&"wall_segments") and sibling.get("size") == rect.size:
			sibling.set(&"wear", wear)
	parent.add_child(wear)
	return wear
