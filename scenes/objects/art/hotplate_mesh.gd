extends RefCounted
## Objects domain, the 3D mesh of the kitchenette's hotplate (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): the crate it stands on, at the piece's own footprint
## (`hotplate_painter.gd`; `ObjectArtKitchenBathConfig.hotplate_crate_color`). The plate with its
## glowing ring and the pan are loose items on it (decision D21, `PieceCarries`; the `hob` and
## `pan` kinds of `item_stock_mesh.gd`); the piece itself still gives the ring's light.


## The node a hotplate `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	return FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"hotplate", spec, _tuning(), func() -> Mesh: return _mesh(spec)
	))


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning() -> Dictionary:
	return {
		"crate": ObjectMeshKitchenConfig.hotplate_crate_height,
		"crate_colour": ObjectArtKitchenBathConfig.hotplate_crate_color,
	}


## The solids of the piece, built once per cache key: the crate.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var crate := ObjectArtKitchenBathConfig.hotplate_crate_color
	var kit := spec.kit()
	kit.box(
		MeshKit.volume(
			spec.area(
				0,
				0,
				spec.size.x,
				spec.size.y,
			), 0.0, ObjectMeshKitchenConfig.hotplate_crate_height
		),
		MeshKit.tone(crate, &"dark"),
		crate,
	)
	return kit.build()
