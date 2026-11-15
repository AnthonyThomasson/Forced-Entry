extends RefCounted
## Objects domain, the 3D mesh of a table (the pattern every furniture mesh follows,
## `object_meshes.gd` and `domain-art/meshes.md`): a top slab over four legs built from Art's mesh
## kit, at the piece's own footprint, the painter's colour on the top and a darker tone of it on the
## legs. The mesh is built once per footprint and colour (`MeshCache`) and shared by every table
## alike.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")


## The node a table `piece` (an `EnvironmentObject`: its `size` and `color`) is shown by, in 3D
## units with its origin at the piece's origin (the footprint centred on it).
static func build(piece: Node2D) -> Node3D:
	var size: Vector2 = piece.get("size")
	var wood := ObjectArt.drawn_color(piece.get("color"))
	var key := MeshCache.key("table", size, wood, _tuning())
	return MeshNodes.instance(MeshCache.fetch(key, func() -> Mesh: return _mesh(size, wood)))


## Every tuning value the shape reads, so a change of it is a different mesh.
static func _tuning() -> Dictionary:
	return {
		"height": ObjectMeshConfig.table_height,
		"top": ObjectMeshConfig.table_top_thickness,
		"leg": ObjectMeshConfig.table_leg,
		"inset": ObjectMeshConfig.table_leg_inset,
	}


## The table: slab on top, a leg in each corner (inset) under it, `wood` its colour.
static func _mesh(size: Vector2, wood: Color) -> Mesh:
	var top_at := ObjectMeshConfig.table_height - ObjectMeshConfig.table_top_thickness
	var half := size * 0.5
	var kit := MeshKit.new()
	kit.box(
		MeshKit.volume(Rect2(-half, size), top_at, ObjectMeshConfig.table_top_thickness),
		MeshKit.tone(wood, &"dark"),
		wood,
	)
	var leg := ObjectMeshConfig.table_leg
	var inset := ObjectMeshConfig.table_leg_inset
	var leg_colour := MeshKit.tone(wood, &"shadow")
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var outer: Vector2 = half * corner - corner * inset
		var leg_rect := Rect2(
			outer - Vector2(leg, leg) * 0.5 - corner * leg * 0.5,
			Vector2(leg, leg),
		)
		kit.box(MeshKit.volume(leg_rect, 0.0, top_at), leg_colour)
	return kit.build()
