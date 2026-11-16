extends RefCounted
## Objects domain, the 3D mesh of a table (the pattern every furniture mesh follows,
## `object_meshes.gd` and `domain-art/meshes.md`): a top slab over four legs built from Art's mesh
## kit, at the piece's own footprint, the painter's colour on the top and a darker tone of it on the
## legs, wearing the painter's flat art (`FurnitureRig`). The mesh is built once per footprint,
## colour and facing (`FurnitureMesh.fetch`) and shared by every table alike.


## The node a table `piece` (an `EnvironmentObject`: its `size` and `color`) is shown by, in 3D
## units with its origin at the piece's origin (the footprint centred on it).
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var height := height_of(spec.size, spec.opts)
	var mesh := FurnitureMesh.fetch(
		"table", spec, _tuning(height), func() -> Mesh: return _mesh(spec, height)
	)
	return FurnitureMesh.show(piece, mesh)


## How tall a table of `size` stands: the piece's own `art_opts.height` when it names one, else the
## low table's for a small footprint (a side table), else the standard table's. The pattern every
## piece with a size-dependent height follows: the number is the piece's data or a rule of its
## size, in a holder, never a literal in the builder.
static func height_of(size: Vector2, opts: Dictionary) -> float:
	var own: Variant = opts.get("height")
	if own is float or own is int:
		return float(own)
	if size.x * size.y <= ObjectMeshConfig.table_low_area:
		return ObjectMeshConfig.table_low_height
	return ObjectMeshConfig.table_height


## Every value the shape reads (the table's `height`, and the holder's proportions), so a change of
## any is a different mesh.
static func _tuning(height: float) -> Dictionary:
	return {
		"height": height,
		"top": ObjectMeshConfig.table_top_thickness,
		"leg": ObjectMeshConfig.table_leg,
		"inset": ObjectMeshConfig.table_leg_inset,
	}


## The table: slab on top, a leg in each corner (inset) under it, `wood` its colour.
static func _mesh(spec: FurnitureSpec, height: float) -> Mesh:
	var size := spec.size
	var wood := spec.color
	var top_at := height - ObjectMeshConfig.table_top_thickness
	var half := size * 0.5
	var kit := spec.kit()
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
