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
## The wall's cap tile along x and turned for a wall along z (null: a wall with no art).
var _tile: Texture2D
var _tile_up: Texture2D
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
	node._tile = StructureSkin.wall_tile(wall)
	node._tile_up = StructureSkin.wall_tile(wall, true)
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
	var part := _segment(shapes, _colour, _skin(index))
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
		"height": ObjectStructureMeshConfig.wall_height,
		"top": ObjectStructureMeshConfig.wall_top_tone,
		"side": ObjectStructureMeshConfig.wall_side_tone,
	}


## How segment `index` wears the tile: its texture and the rect (px, in the wall's frame) one tile
## covers, laid from the segment's start. Empty without art.
func _skin(index: int) -> Dictionary:
	if _tile == null:
		return {}
	var seg: PackedVector2Array = (_wall.call(&"wall_segments") as Array)[index]
	var half := float(_wall.get("wall_thickness")) * 0.5
	var along_x := absf(seg[1].x - seg[0].x) >= absf(seg[1].y - seg[0].y)
	var texture := _tile if along_x else _tile_up
	var corner := (
		Vector2(minf(seg[0].x, seg[1].x), seg[0].y - half)
		if along_x
		else Vector2(seg[0].x - half, minf(seg[0].y, seg[1].y))
	)
	return { "texture": texture, "rect": Rect2(corner, StructureSkin.extent(texture)) }


## The solid of one segment's collider shapes, or null when it has none now (a collider on its way
## out is not counted). A `skin` (`_skin`) makes it white, for the tile to colour.
static func _segment(shapes: Array, colour: Color, skin: Dictionary) -> MeshInstance3D:
	var live: Array[CollisionShape2D] = []
	for shape: Variant in shapes:
		if is_instance_valid(shape):
			var node := shape as CollisionShape2D
			if node.shape != null and not node.is_queued_for_deletion():
				live.append(node)
	if live.is_empty():
		return null
	var worn := not skin.is_empty()
	var origin := Vector2.ZERO
	var instance: MeshInstance3D
	if live.size() == 1 and _is_whole(live[0]):
		origin = live[0].position
		instance = _whole(live[0], colour, worn)
	else:
		instance = _pieces(live, colour, worn)
	if worn:
		var rect: Rect2 = skin["rect"]
		rect.position -= origin
		MeshNodes.textured(instance, skin["texture"], rect, { "tiled": true })
	return instance


## The cached box of one whole segment, placed at its collider; `worn` makes it white.
static func _whole(shape_node: CollisionShape2D, colour: Color, worn: bool) -> MeshInstance3D:
	var size := (shape_node.shape as RectangleShape2D).size
	var side := Color.WHITE if worn else _side(colour)
	var top := Color.WHITE if worn else _top(colour)
	var key := MeshCache.key("wall", size, Color.WHITE if worn else colour, _tuning())
	var instance := MeshNodes.instance(
		MeshCache.fetch(key, func() -> Mesh: return _box(size, side, top))
	)
	var centre := shape_node.position
	MeshNodes.place(instance, Vector3(centre.x, 0.0, centre.y))
	return instance


## A dented segment: the extruded outlines of its convex pieces, in the wall's frame.
static func _pieces(live: Array[CollisionShape2D], colour: Color, worn: bool) -> MeshInstance3D:
	var kit := MeshKit.new()
	var side := Color.WHITE if worn else _side(colour)
	var top := Color.WHITE if worn else _top(colour)
	for shape in live:
		kit.extrude(_outline(shape), 0.0, ObjectStructureMeshConfig.wall_height, side, top)
	return MeshNodes.instance(kit.build())


## Whether `shape_node` is an upright rectangle with nothing but a position (a whole segment).
static func _is_whole(shape_node: CollisionShape2D) -> bool:
	return (
		shape_node.shape is RectangleShape2D
		and is_zero_approx(shape_node.rotation)
		and shape_node.scale.is_equal_approx(Vector2.ONE)
	)


## `size` px wide and deep, centred on the origin: the whole segment, `side` and `top` coloured.
static func _box(size: Vector2, side: Color, top: Color) -> Mesh:
	var kit := MeshKit.new()
	kit.box(
		MeshKit.volume(Rect2(-size * 0.5, size), 0.0, ObjectStructureMeshConfig.wall_height),
		side,
		top,
	)
	return kit.build()


## The outline of `shape_node`'s shape in the wall's frame.
static func _outline(shape_node: CollisionShape2D) -> PackedVector2Array:
	var local := PackedVector2Array()
	if shape_node.shape is ConvexPolygonShape2D:
		local = (shape_node.shape as ConvexPolygonShape2D).points
	elif shape_node.shape is RectangleShape2D:
		var half := (shape_node.shape as RectangleShape2D).size * 0.5
		local = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y),
		])
	return shape_node.transform * local


## The tone of the cap colour a wall's sides take.
static func _side(colour: Color) -> Color:
	return MeshKit.tone(colour, StringName(ObjectStructureMeshConfig.wall_side_tone))


## The tone of the cap colour a wall's top takes.
static func _top(colour: Color) -> Color:
	return MeshKit.tone(colour, StringName(ObjectStructureMeshConfig.wall_top_tone))
