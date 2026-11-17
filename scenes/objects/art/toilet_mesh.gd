extends RefCounted
## Objects domain, the 3D mesh of a toilet (the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): at the piece's own footprint, bowl toward the front, an oval bowl on a
## narrower pedestal with its water, and the cistern against the back with its flush button
## (`toilet_painter.gd`'s proportions), in the piece's glaze. Shared by every toilet alike.


## The node a toilet `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var mesh := FurnitureMesh.fetch(
		"toilet", spec, _tuning(), func() -> Mesh: return _mesh(spec)
	)
	return FurnitureMesh.show(piece, mesh)


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning() -> Dictionary:
	return {
		"bowl": ObjectMeshRoomConfig.toilet_bowl_height,
		"pedestal": ObjectMeshRoomConfig.toilet_pedestal_height,
		"tank": ObjectMeshRoomConfig.toilet_tank_height,
		"water": ObjectArtKitchenBathConfig.bath_water_color,
		"button": ObjectArtKitchenBathConfig.counter_tap_color,
	}


## The solids of the piece, built once per cache key: the pedestal, the bowl with its water and
## the cistern with its button.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var base := spec.color
	var w := spec.size.x
	var d := spec.size.y
	var bowl_h := ObjectMeshRoomConfig.toilet_bowl_height
	var ped_h := ObjectMeshRoomConfig.toilet_pedestal_height
	var bowl := spec.area(roundf(w * 0.21), roundf(d * 0.26), roundf(w * 0.58), roundf(d * 0.68))
	var kit := spec.kit()
	kit.extrude(
		FurnitureSpec.ellipse(Rect2(bowl.get_center() - bowl.size * 0.3, bowl.size * 0.6)),
		0.0,
		ped_h,
		MeshKit.tone(base, &"shadow"),
	)
	kit.extrude(
		FurnitureSpec.ellipse(bowl), ped_h, bowl_h - ped_h, base, MeshKit.tone(base, &"highlight")
	)
	kit.extrude(
		FurnitureSpec.ellipse(bowl.grow(-maxf(2.0, floorf(w / 10.0)))),
		bowl_h,
		0.4,
		ObjectArtKitchenBathConfig.bath_water_color,
	)
	_tank(spec, kit)
	return kit.build()


## The cistern behind the bowl, a flush button on its top.
static func _tank(spec: FurnitureSpec, kit: MeshKit) -> void:
	var base := spec.color
	var tank_h := ObjectMeshRoomConfig.toilet_tank_height
	var tank := spec.area(
		roundf(spec.size.x * 0.2),
		roundf(spec.size.y * 0.06),
		roundf(spec.size.x * 0.6),
		roundf(spec.size.y * 0.24),
	)
	kit.box(MeshKit.volume(tank, 0.0, tank_h), base, MeshKit.tone(base, &"light"))
	var middle := tank.get_center()
	kit.cylinder(
		Vector3(middle.x, tank_h, middle.y), 1.0, 1.0, ObjectArtKitchenBathConfig.counter_tap_color
	)
