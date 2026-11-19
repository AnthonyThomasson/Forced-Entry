class_name WallWearMesh
extends RefCounted
## Objects domain, a wall's wear in the 3D render (`domain-objects/meshes.md`): the
## marks of its room's wear (`RoomWear.wall_marks`) stand on the face of the wall segment they lie
## on, the face toward the room, at a height by kind (`ObjectWearMeshConfig`), painted by the same
## wear painter, kind and variant as the 2D mark (on a canvas as long as the mark and as tall as
## its kind). Each is a child of its segment's mesh instance, so it turns with the wall, stays with
## the segment and is faded with it (the wall fade makes a unit of a segment's children,
## `domain-art/wall-fade.md`); `WallMesh` hands them to a rebuilt segment (`dress`).

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")


## The decals of `wall`'s wear by the segment (an index into its `wall_segments()`) each lies on,
## `{ index: Array[MeshInstance3D] }`, in the wall's frame, not yet in the tree: `dress` puts them
## on a segment's instance. Empty for a wall with no wear. A mark on no segment is left out.
static func decals_of(wall: Node2D) -> Dictionary:
	var out := {}
	var segments: Array = wall.call(&"wall_segments")
	var thickness: float = wall.get("wall_thickness")
	var wears: Array = []
	var own: Variant = wall.get("wear")
	if is_instance_valid(own):
		wears.append(own)
	for lent: Node2D in wall.get("neighbour_wear") if wall.get("neighbour_wear") else []:
		if is_instance_valid(lent):
			wears.append(lent)
	for wear: Node2D in wears:
		var marks: Array = wear.call(&"wall_marks")
		# a neighbour's marks are in its own frame, the room's corner
		var shift: Vector2 = wear.position - wall.position
		for i in marks.size():
			var index := _segment_of(wall, segments, (marks[i]["at"] as Vector2) + shift)
			if index < 0:
				continue
			if not out.has(index):
				out[index] = []
			var mark: Dictionary = marks[i].duplicate()
			mark["at"] = (marks[i]["at"] as Vector2) + shift
			out[index].append(_decal(mark, thickness, WearMesh.order_layer(i, marks.size())))
	return out


## Put `decals` (a segment's, from `decals_of`) on `part`, the segment's instance: its children,
## placed as they lie on the wall (`part` need not stand at the wall's origin).
static func dress(part: Node3D, decals: Array) -> void:
	for decal: MeshInstance3D in decals:
		if not is_instance_valid(decal):
			continue
		var holder := decal.get_parent()
		if holder != null:
			holder.remove_child(decal)
		decal.position = (decal.get_meta(&"wall_position") as Vector3) - part.position
		part.add_child(decal)


## The index of the segment (of `wall_segments()`) the wall owns whose centre line `at` lies on, or
## -1 (a stretch another wall owns has its marks laid on that wall).
static func _segment_of(wall: Node2D, segments: Array, at: Vector2) -> int:
	var best := -1
	var nearest := 1.0
	for i in segments.size():
		if not wall.call(&"has_segment", i):
			continue
		var seg: PackedVector2Array = segments[i]
		var d := Geometry2D.get_closest_point_to_segment(at, seg[0], seg[1]).distance_to(at)
		if d < nearest:
			nearest = d
			best = i
	return best


## The decal of `mark` on the face of a wall `thickness` thick, in the wall's frame, on `layer` off
## the face (the mark's draw order, as a fraction of a tier: two marks never share a depth).
static func _decal(mark: Dictionary, thickness: float, layer: float) -> MeshInstance3D:
	var kind := String(mark["kind"])
	var length: float = mark["length"]
	var height: float = ObjectWearMeshConfig.wall_mark_height.get(
		kind, ObjectWearMeshConfig.wall_mark_height_default
	)
	var up_at: float = ObjectWearMeshConfig.wall_mark_at.get(
		kind, ObjectWearMeshConfig.wall_mark_at_default
	)
	var normal: Vector2 = mark["normal"]
	var on_face: Vector2 = (mark["at"] as Vector2) + normal * (thickness * 0.5)
	var texture := ObjectArt.flat_facing(
		"wear",
		Vector2(length, height),
		ObjectArtWearConfig.plaster_color,
		Vector2.DOWN,
		{ "kind": kind, "v": mark["v"] },
	)
	var frame := MeshNodes.surface_frame(
		Vector3(on_face.x, up_at, on_face.y), Vector3(normal.x, 0.0, normal.y)
	)
	var decal := MeshNodes.decal(Vector2(length, height), frame, texture, Color.WHITE, layer)
	decal.set_meta(&"wall_position", decal.position)
	return decal
