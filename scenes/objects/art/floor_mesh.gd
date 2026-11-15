extends RefCounted
## Objects domain, the 3D mesh of a floor (`structure_meshes.gd`, `domain-art/meshes.md`): a flat
## slab at the floor's footprint, its top `floor_lift` over the ground (a thin slab sunk below it),
## wearing its painter's tile, repeated (`MeshNodes.textured`, `tiled`: the planks, tiles, carpet of
## the 2D floor, painted flat, the tile's grid laid from the floor's `tile_offset` as in 2D); its
## edge is the tile's edge texels a step darker. A floor is a static node, so its mesh is built
## once, in a frame whose origin is the floor's corner, shared by every floor of one size, and casts
## no shadow (it is the ground). Its room's floor wear lies on it as decals (`wear_mesh.gd`).


## The node a `floor_node` (a `Floor`: its `size` and `color`) is shown by.
static func build(floor_node: Node2D) -> Node3D:
	var size: Vector2 = floor_node.get("size")
	var node := MeshNodes.instance(
		MeshCache.fetch(
			MeshCache.key("floor", size, Color.WHITE, _tuning()),
			func() -> Mesh: return _mesh(size),
		),
		Color.WHITE,
		false,
	)
	StructureSkin.tile(node, floor_node)
	WearMesh.attach_floor(node, floor_node)
	return node


## The slab of a floor of `size` px: a corner at the origin, its top `floor_lift` over the ground,
## white (the tile's art is multiplied by it).
static func _mesh(size: Vector2) -> Mesh:
	var thickness := ObjectStructureMeshConfig.floor_thickness
	var lift := ObjectStructureMeshConfig.floor_lift
	var kit := MeshKit.new()
	kit.box(
		MeshKit.volume(Rect2(Vector2.ZERO, size), lift - thickness, thickness),
		Color.WHITE,
	)
	return kit.build()


## Every value the shape reads, so a change of any is another mesh.
static func _tuning() -> Dictionary:
	return {
		"thickness": ObjectStructureMeshConfig.floor_thickness,
		"lift": ObjectStructureMeshConfig.floor_lift,
	}
