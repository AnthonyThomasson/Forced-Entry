extends RefCounted
## Objects domain, the 3D mesh of a bed (#193 phase 2; the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): at the piece's own footprint, foot toward the front, a low frame with a
## headboard at the head, the bare ticking mattress (`ObjectArtFabricConfig.bed_mattress_color`)
## with a pillow at the head, and the blanket in the piece's colour over its foot
## (`bed_painter.gd`). The blanket is a part of its own on the bed's rig (`FurnitureBedRig`), laid
## flat while someone lies on the bed.


## The node a bed `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning()
	var rig := FurnitureBedRig.new().with_body(piece, FurnitureMesh.fetch(
		"bed", spec, tuning, func() -> Mesh: return _mesh(spec)
	)) as FurnitureBedRig
	var blanket := FurnitureMesh.fetch(
		"bed_blanket", spec, tuning, func() -> Mesh: return _blanket(spec)
	)
	rig.blanket = rig.add_part(
		"Blanket",
		blanket,
		Vector3(0.0, ObjectMeshRoomConfig.bed_mattress_height, 0.0),
	)
	return rig


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning() -> Dictionary:
	return {
		"frame": ObjectMeshRoomConfig.bed_frame_height,
		"mattress": ObjectMeshRoomConfig.bed_mattress_height,
		"pillow": ObjectMeshRoomConfig.bed_pillow_height,
		"blanket": ObjectMeshRoomConfig.bed_blanket_height,
		"head": ObjectMeshRoomConfig.bed_headboard_height,
		"ticking": ObjectArtFabricConfig.bed_mattress_color,
	}


## The mattress's rectangle in the bed's frame, as the painter lays it.
static func mattress_rect(spec: FurnitureSpec) -> Rect2:
	return Rect2(3, 6, spec.size.x - 6, spec.size.y - 9)


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var ticking := ObjectArtFabricConfig.bed_mattress_color
	var rect := mattress_rect(spec)
	var frame_h := ObjectMeshRoomConfig.bed_frame_height
	var mattress_h := ObjectMeshRoomConfig.bed_mattress_height
	var kit := spec.kit()
	kit.box(
		MeshKit.volume(spec.area(0, 0, spec.size.x, spec.size.y), 0.0, frame_h),
		MeshKit.tone(ticking, &"shadow"),
	)
	kit.box(
		MeshKit.volume(
			spec.area(0, 0, spec.size.x, 4),
			0.0,
			ObjectMeshRoomConfig.bed_headboard_height,
		),
		MeshKit.tone(spec.color, &"shadow"),
	)
	kit.box(
		MeshKit.volume(spec.area(rect.position.x, rect.position.y, rect.size.x, rect.size.y),
			frame_h, mattress_h - frame_h),
		ticking,
	)
	kit.box(
		MeshKit.volume(
			spec.area(rect.position.x + 6, rect.position.y + 4, rect.size.x * 0.45, 14),
			mattress_h, ObjectMeshRoomConfig.bed_pillow_height
		),
		ticking.lightened(0.08),
	)
	return kit.build()


## The blanket over the foot of the mattress, its underside at the part's origin.
static func _blanket(spec: FurnitureSpec) -> Mesh:
	var rect := mattress_rect(spec)
	var kit := spec.kit()
	kit.box(
		MeshKit.volume(
			spec.area(
				rect.position.x - 1.0,
				floorf(rect.size.y * 0.5),
				rect.size.x + 2.0,
				floorf(rect.size.y * 0.42),
			),
			0.0, ObjectMeshRoomConfig.bed_blanket_height
		),
		MeshKit.tone(spec.color, &"dark"),
		spec.color,
	)
	return kit.build()
