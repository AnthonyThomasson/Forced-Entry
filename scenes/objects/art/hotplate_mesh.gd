extends RefCounted
## Objects domain, the 3D mesh of the kitchenette's hotplate (#193 phase 2; the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint, a plate in the piece's
## colour on a crate, a pan on the right ring and the left ring hot and glowing
## (`hotplate_painter.gd`; `ObjectArtKitchenBathConfig.hotplate_*`). The ring is a glow node of the
## piece's rig.


## The node a hotplate `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"hotplate", spec, _tuning(), func() -> Mesh: return _mesh(spec)
	))
	rig.add_glow(
		FurnitureMesh.fetch_glow("hotplate", spec, _tuning(), func() -> Mesh: return _glow(spec)),
		ObjectArtKitchenBathConfig.hotplate_ring_color,
	)
	return rig


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning() -> Dictionary:
	return {
		"crate": ObjectMeshKitchenConfig.hotplate_crate_height,
		"plate": ObjectMeshKitchenConfig.hotplate_plate_height,
		"pan": ObjectMeshKitchenConfig.hotplate_pan_height,
		"crate_colour": ObjectArtKitchenBathConfig.hotplate_crate_color,
		"pan_colour": ObjectArtKitchenBathConfig.hotplate_pan_color,
		"ring": ObjectArtKitchenBathConfig.hotplate_ring_color,
	}


## Where the two rings are and how big (the painter's rule): the plate's rectangle, the radius, the
## hot ring's centre and the pan's.
static func rings(spec: FurnitureSpec) -> Dictionary:
	var plate := Rect2(3, 4, spec.size.x - 6, spec.size.y - 8)
	var r := maxf(3.0, floorf(plate.size.y / 2.0) - 2.0)
	var y := plate.position.y + floorf(plate.size.y / 2.0)
	return {
		"plate": plate,
		"radius": r,
		"left": Vector2(plate.position.x + r + 2.0, y) - spec.half(),
		"right": Vector2(plate.end.x - r - 3.0, y) - spec.half(),
	}


## The solids of the piece, built once per cache key: the crate, the plate and the pan.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var crate_h := ObjectMeshKitchenConfig.hotplate_crate_height
	var crate := ObjectArtKitchenBathConfig.hotplate_crate_color
	var plate: Rect2 = rings(spec)["plate"]
	var kit := spec.kit()
	kit.box(
		MeshKit.volume(spec.area(0, 0, spec.size.x, spec.size.y), 0.0, crate_h),
		MeshKit.tone(crate, &"dark"),
		crate,
	)
	kit.box(
		MeshKit.volume(
			spec.area(plate.position.x, plate.position.y, plate.size.x, plate.size.y),
			crate_h,
			ObjectMeshKitchenConfig.hotplate_plate_height,
		),
		spec.color,
		MeshKit.tone(spec.color, &"light"),
	)
	_pan(spec, kit)
	return kit.build()


## The pan on the right ring, its handle reaching out to the right.
static func _pan(spec: FurnitureSpec, kit: MeshKit) -> void:
	var found := rings(spec)
	var radius: float = found["radius"]
	var right: Vector2 = found["right"]
	var pan := ObjectArtKitchenBathConfig.hotplate_pan_color
	var pan_h := ObjectMeshKitchenConfig.hotplate_pan_height
	var top := ObjectMeshKitchenConfig.hotplate_crate_height
	top += ObjectMeshKitchenConfig.hotplate_plate_height
	kit.cylinder(
		Vector3(right.x, top, right.y),
		radius + 1.0,
		pan_h,
		pan,
		MeshKit.tone(pan, &"light"),
	)
	var grip := Rect2(right + Vector2(radius + 1.0, -1.0), Vector2(5, 2))
	kit.box(MeshKit.volume(grip, top + pan_h - 1.5, 1.5), pan)


## The hot ring: a glowing disc on the left of the plate.
static func _glow(spec: FurnitureSpec) -> Mesh:
	var found := rings(spec)
	var left: Vector2 = found["left"]
	var top := ObjectMeshKitchenConfig.hotplate_crate_height
	top += ObjectMeshKitchenConfig.hotplate_plate_height
	var kit := spec.kit()
	kit.cylinder(
		Vector3(left.x, top, left.y),
		float(found["radius"]),
		0.6,
		ObjectArtKitchenBathConfig.hotplate_ring_color,
	)
	return kit.build()
