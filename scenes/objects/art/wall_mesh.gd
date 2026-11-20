class_name WallMesh
extends Node3D
## Objects domain, the 3D mesh of a room's walls (`structure_meshes.gd`, `domain-art/meshes.md`):
## every wall segment a full-height solid at its collider's own footprint (its real thickness, the
## doorways and gaps left open) wearing the wall painter's tile, painted flat (`StructureSkin`): the
## cap on top, the tile's edge texels (plaster grain, brick joints) stretched down the face, a step
## darker. A wall with no art keeps the cap colour on its sides and a lighter tone on top. Each
## segment is its own `MeshInstance3D` (`Segment<i>`, the segment's index in `wall_segments()`), so
## the wall-fade job fades them one by one. A whole segment is the one cached box every segment of
## that size and colour shares; a dented one is built from the convex pieces of its collider.
##
## The node follows its wall's colliders itself (`follows_shapes`: the mirror leaves it alone when
## a collider comes or goes): when a hit rebuilds segment `i` the wall says so (`segment_rebuilt`)
## and only `Segment<i>` is replaced, by a new instance (`segment_replaced`: a fade set on the old
## one is gone, so whoever fades a wall sets it again on the new part).

## `Segment<index>` was rebuilt: `part` is its new mesh instance.
signal segment_replaced(index: int, part: MeshInstance3D)

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

## How many segments this node has rebuilt since it was made (a test reads it).
var rebuilds := 0
## The wall (a `Wall`) and the cap colour its segments are built in.
var _wall: Node2D
var _colour := Color.WHITE
## The wall's wear marks by the segment each stands on (`WallWearMesh.decals_of`): children of that
## segment's instance, handed to a rebuilt one.
var _marks := {}


## The marks no segment carries (not in the tree) go with the mesh.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for decals: Array in _marks.values():
		for decal: Variant in decals:
			if is_instance_valid(decal) and (decal as Node).get_parent() == null:
				(decal as Node).free()


## The node a `wall` (a `Wall`: `segment_shapes()`, `art`, `art_color`) is shown by, in 3D units in
## the wall's own frame; null for a body that is no wall.
static func build(wall: Node2D) -> Node3D:
	if not wall.has_method(&"segment_shapes") or not wall.has_signal(&"segment_rebuilt"):
		return null
	var node := WallMesh.new()
	node.name = "WallMesh"
	node._wall = wall
	node._colour = colour_of(wall)
	node._marks = WallWearMesh.decals_of(wall)
	var shapes: Dictionary = wall.call(&"segment_shapes")
	var indices: Array = shapes.keys()
	indices.sort()
	for i: int in indices:
		node._put(i, shapes[i])
	wall.connect(&"segment_rebuilt", node.rebuild_segment)
	return node


## Tell the mirror this mesh keeps up with the wall's colliders itself.
func follows_shapes() -> bool:
	return true


## The segments now, index -> instance (the wall fade fades them one by one).
func segments() -> Dictionary:
	var out := {}
	for child in get_children():
		if child is MeshInstance3D and child.name.begins_with("Segment"):
			out[int(String(child.name).trim_prefix("Segment"))] = child
	return out


## Replace `Segment<index>` by one built from the wall's colliders for it now.
func rebuild_segment(index: int) -> void:
	if not is_instance_valid(_wall):
		return
	var old := get_node_or_null("Segment%d" % index)
	if old != null:
		for decal: Variant in _marks.get(index, []):
			if is_instance_valid(decal) and (decal as Node).get_parent() == old:
				old.remove_child(decal)  # the new segment carries the wear on
		remove_child(old)
		old.queue_free()
	var part := _put(index, (_wall.call(&"segment_shapes") as Dictionary).get(index, []))
	rebuilds += 1
	if part != null:
		segment_replaced.emit(index, part)


## Add the instance of segment `index` (its collider `shapes`) as a child; null when it has none.
func _put(index: int, shapes: Array) -> MeshInstance3D:
	var seg: PackedVector2Array = (_wall.call(&"wall_segments") as Array)[index]
	var part := _segment(shapes, _colour, StructureSkin.wall_skin(_wall, seg), _height(seg))
	if part != null:
		part.name = "Segment%d" % index
		add_child(part)
		WallWearMesh.dress(part, _marks.get(index, []))
	return part


## The cap colour as drawn: the painter's run-down grade of `art_color`, or the flat line's own
## when the wall has no art (as `Wall.get_surface` gives its debris).
static func colour_of(wall: Node) -> Color:
	var colour: Color = wall.get("art_color")
	return ObjectArt.drawn_color(colour) if String(wall.get("art")) != "" else colour


## Every value the shape reads, so a change of any is a different mesh.
static func _tuning() -> Dictionary:
	return {
		"top": ObjectStructureMeshConfig.wall_top_tone,
		"side": ObjectStructureMeshConfig.wall_side_tone,
	}


## How tall the segment `seg` stands: a segment along z a hair taller than one along x, so the caps
## of two walls that meet (a corner, a T) do not share one plane and fight over it.
static func _height(seg: PackedVector2Array) -> float:
	var along_z := absf(seg[1].y - seg[0].y) > absf(seg[1].x - seg[0].x)
	return ObjectStructureMeshConfig.wall_height + (
		ObjectStructureMeshConfig.wall_cross_lift if along_z else 0.0
	)


## The solid of one segment's collider shapes, or null when it has none now (a collider on its way
## out is not counted), `height` px tall. A `skin` (`StructureSkin.wall_skin`) makes it white, for
## the tile to colour.
static func _segment(
	shapes: Array,
	colour: Color,
	skin: Dictionary,
	height: float,
) -> MeshInstance3D:
	var live: Array[PackedVector2Array] = []
	for outline: Variant in shapes:
		if (outline as PackedVector2Array).size() >= 3:
			live.append(outline)
	if live.is_empty():
		return null
	var worn := not skin.is_empty()
	var origin := Vector2.ZERO
	var instance: MeshInstance3D
	if live.size() == 1 and TwinShapes.rect_of(live[0]).has_area():
		var box := _bounds(live[0])
		origin = box.get_center()
		instance = _whole(box.size, origin, colour, worn, height)
	else:
		instance = _pieces(live, colour, worn, height)
	if worn:
		var rect: Rect2 = skin["rect"]
		rect.position -= origin
		MeshNodes.textured(instance, skin["texture"], rect, { "tiled": true })
	return instance


## The cached box of one whole segment, placed at its collider; `worn` makes it white.
static func _whole(
	size: Vector2,
	centre: Vector2,
	colour: Color,
	worn: bool,
	height: float,
) -> MeshInstance3D:
	var side := Color.WHITE if worn else _side(colour)
	var top := Color.WHITE if worn else _top(colour)
	var opts := _tuning()
	opts["tall"] = height
	var key := MeshCache.key("wall", size, Color.WHITE if worn else colour, opts)
	var instance := MeshNodes.instance(
		MeshCache.fetch(key, func() -> Mesh: return _box(size, height, side, top))
	)
	MeshNodes.place(instance, Vector3(centre.x, 0.0, centre.y))
	return instance


## A dented segment: the extruded outlines of its convex pieces, in the wall's frame.
static func _pieces(
	live: Array[PackedVector2Array],
	colour: Color,
	worn: bool,
	height: float,
) -> MeshInstance3D:
	var kit := MeshKit.new()
	var side := Color.WHITE if worn else _side(colour)
	var top := Color.WHITE if worn else _top(colour)
	for outline in live:
		kit.extrude(outline, 0.0, height, side, top)
	return MeshNodes.instance(kit.build())


## The rectangle `outline` span.
static func _bounds(outline: PackedVector2Array) -> Rect2:
	var box := Rect2(outline[0], Vector2.ZERO)
	for point in outline:
		box = box.expand(point)
	return box


## `size` px wide and deep and `height` tall, centred on the origin: the whole segment, `side` and
## `top` coloured.
static func _box(size: Vector2, height: float, side: Color, top: Color) -> Mesh:
	var kit := MeshKit.new()
	kit.box(
		MeshKit.volume(Rect2(-size * 0.5, size), 0.0, height),
		side,
		top,
	)
	return kit.build()


## The tone of the cap colour a wall's sides take.
static func _side(colour: Color) -> Color:
	return MeshKit.tone(colour, StringName(ObjectStructureMeshConfig.wall_side_tone))


## The tone of the cap colour a wall's top takes.
static func _top(colour: Color) -> Color:
	return MeshKit.tone(colour, StringName(ObjectStructureMeshConfig.wall_top_tone))
