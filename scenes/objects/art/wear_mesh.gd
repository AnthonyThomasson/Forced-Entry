class_name WearMesh
extends RefCounted
## Objects domain, wear and decals in the 3D render (#193 phase 2; `domain-objects/wear-meshes.md`):
## what Objects draws as wear in 2D is a decal in 3D (`MeshNodes.decal`), laid on its surface from
## the very textures the 2D marks draw, placed by the same rects. A room's floor marks lie on its
## floor's mesh (`attach_floor`: the slab's top, `ObjectStructureMeshConfig.floor_lift`, each mark
## a step over the one drawn before it, all under a rug's top: `order_layer`), a street piece's on
## its pavement or on its road a kerb lower (`attach_street`: not at the ground; each on the layer
## of its kind and draw order, `layer_of`; the lane's dashes and the crossings are the street
## mesh's own and are not laid twice). A floor stencil is `StencilMesh`'s, on `tier_stencil`. A
## wall's marks stand on its segments (`wall_wear_mesh.gd`). A tower's shadow is not a decal in 3D:
## the sun casts a real one. Everything is static (a decal is a child of its surface's mesh,
## written once), so it costs nothing per frame; a mark's quad mesh is shared by size and its
## material by texture.


## Lay the floor marks of `floor_node`'s room (its `wear`, a `RoomWear`) as decals on `node`, the
## floor's mesh (its corner the origin: the wear's frame), each a step (`order_layer`) over the one
## drawn before it and no tier: the 2D layer draws a room's wear under a rug, so a mark never
## reaches a rug's top.
static func attach_floor(node: Node3D, floor_node: Node2D) -> void:
	var wear: Variant = floor_node.get("wear")
	if not is_instance_valid(wear):
		return
	var marks: Array = (wear as Node2D).call(&"floor_marks")
	for i in marks.size():
		var layer := order_layer(i, marks.size())
		node.add_child(_flat(marks[i], ObjectStructureMeshConfig.floor_lift, layer))


## Lay the marks of a street piece `floor_node` (its `StreetMarks` child) as decals on `node`, its
## mesh (its corner the origin): at the pavement's height (the ground) or the road's (a kerb
## lower), each on the layer of its kind and draw order (`layer_of`), the dashes and crossings left
## to the mesh.
static func attach_street(node: Node3D, floor_node: Node2D) -> void:
	var layer := floor_node.find_child("StreetMarks", true, false)
	if layer == null:
		return
	var opts: Dictionary = floor_node.get("art_opts")
	var top := 0.0 if String(opts.get("kind", "asphalt")) == "sidewalk" else (
		-ObjectStreetMeshConfig.kerb
	)
	var marks: Array = layer.call(&"decals").filter(
		func(m: Array) -> bool: return not (m[2] in ObjectWearMeshConfig.street_drawn)
	)
	for i in marks.size():
		node.add_child(_flat(marks[i], top, layer_of(marks, i)))


## The decal layer (`MeshNodes.decal`) of mark `index` of `marks` (`[texture, rect, kind]` each, in
## the order they are drawn): the tier of its kind plus its place in the draw order as a fraction
## of a tier (`order_fraction`), so of the marks that overlap the later lies over the earlier, a
## chip over a slab, a glyph over both, and no two share a depth.
static func layer_of(marks: Array, index: int) -> float:
	return tier_of(marks[index][2]) + order_layer(index, marks.size())


## The tier (`ObjectWearMeshConfig`) a mark of `kind` lies on.
static func tier_of(kind: StringName) -> float:
	return ObjectWearMeshConfig.kind_tier.get(kind, ObjectWearMeshConfig.tier_mark)


## The fraction of a tier mark `index` of `count` marks, in draw order, lies up: a step each, under
## `order_fraction` in all.
static func order_layer(index: int, count: int) -> float:
	return ObjectWearMeshConfig.order_fraction * index / maxf(count, 1.0)


## A decal showing `mark`'s texture over its rect (the frame's px), `height` px over the ground,
## lying flat, on `layer`.
static func _flat(mark: Array, height: float, layer: float) -> MeshInstance3D:
	var centre: Vector2 = (mark[1] as Rect2).get_center()
	return MeshNodes.decal(
		(mark[1] as Rect2).size,
		MeshNodes.surface_frame(Vector3(centre.x, height, centre.y)),
		mark[0],
		Color.WHITE,
		layer,
	)
