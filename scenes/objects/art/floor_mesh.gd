extends RefCounted
## Objects domain, the 3D mesh of a floor (`structure_meshes.gd`, `domain-art/meshes.md`): a flat
## slab at the floor's footprint, its top `floor_lift` over the ground (a thin slab sunk below it),
## in the colour its painter draws and a darker tone at its edge. The pattern (planks, tiles) is not
## modelled: a floor reads by its colour. A floor is a static node, so its mesh is built once, in a
## frame whose origin is the floor's corner, shared by every floor of one size and colour, and casts
## no shadow (it is the ground).

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")


## The node a `floor_node` (a `Floor`: its `size` and `color`) is shown by.
static func build(floor_node: Node2D) -> Node3D:
	var size: Vector2 = floor_node.get("size")
	var colour := ObjectArt.drawn_color(floor_node.get("color"))
	return MeshNodes.instance(
		MeshCache.fetch(
			MeshCache.key("floor", size, colour, _tuning()),
			func() -> Mesh: return _mesh(size, colour),
		),
		Color.WHITE,
		false,
	)


## The slab of a floor of `size` px: a corner at the origin, its top `floor_lift` over the ground,
## its edge `ObjectStructureMeshConfig.floor_edge_tone` of `colour`.
static func _mesh(size: Vector2, colour: Color) -> Mesh:
	var thickness := ObjectStructureMeshConfig.floor_thickness
	var lift := ObjectStructureMeshConfig.floor_lift
	var kit := MeshKit.new()
	kit.box(
		MeshKit.volume(Rect2(Vector2.ZERO, size), lift - thickness, thickness),
		MeshKit.tone(colour, StringName(ObjectStructureMeshConfig.floor_edge_tone)),
		colour,
	)
	return kit.build()


## Every value the shape reads, so a change of any is another mesh.
static func _tuning() -> Dictionary:
	return {
		"thickness": ObjectStructureMeshConfig.floor_thickness,
		"lift": ObjectStructureMeshConfig.floor_lift,
		"edge": ObjectStructureMeshConfig.floor_edge_tone,
	}
