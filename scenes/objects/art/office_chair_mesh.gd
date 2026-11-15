extends RefCounted
## Objects domain, the 3D mesh of an office chair (#193 phase 2; the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): at the piece's own footprint, a five-star base on casters
## (`ObjectArtTableConfig.office_chair_base_color`) under a column, a padded seat in the piece's
## colour, an armrest each side and a backrest leaning back (`office_chair_painter.gd`). Shared by
## every office chair alike.

const STARS := 5


## The node an office chair `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var mesh := FurnitureMesh.fetch(
		"office_chair", spec, _tuning(), func() -> Mesh: return _mesh(spec)
	)
	return FurnitureMesh.show(piece, mesh)


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning() -> Dictionary:
	return {
		"seat": ObjectMeshChairConfig.office_seat_height,
		"thick": ObjectMeshChairConfig.office_seat_thickness,
		"back": ObjectMeshChairConfig.office_back_height,
		"lean": ObjectMeshChairConfig.office_back_lean,
		"arm": ObjectMeshChairConfig.office_arm_height,
		"column": ObjectMeshChairConfig.office_column,
		"metal": ObjectArtTableConfig.office_chair_base_color,
	}


## The solids of the piece, built once per cache key: the five-star base and column, the seat, the
## armrests and the leaning back.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var base := spec.color
	var w := spec.size.x
	var d := spec.size.y
	var seat_top := ObjectMeshChairConfig.office_seat_height
	var seat_low := seat_top - ObjectMeshChairConfig.office_seat_thickness
	var metal := ObjectArtTableConfig.office_chair_base_color
	var reach := minf(w, d) * 0.47
	var kit := spec.kit()
	for i in STARS:
		spec.level(kit, Transform3D(Basis(Vector3.UP, TAU * i / STARS), Vector3.ZERO))
		kit.box(MeshKit.volume(Rect2(0.0, -1.2, reach, 2.4), 1.5, 2.0), metal)
		kit.cylinder(Vector3(reach, 0.0, 0.0), 1.4, 3.5, MeshKit.tone(metal, &"shadow"))
	spec.level(kit)
	kit.cylinder(Vector3(0.0, 3.5, 0.0), ObjectMeshChairConfig.office_column, seat_low - 3.5, metal)
	var reach_back := minf(d * 0.28, _back_pivot())
	kit.box(
		MeshKit.volume(
			spec.area(4, reach_back, w - 8, d - reach_back - 3), seat_low, seat_top - seat_low
		),
		MeshKit.tone(base, &"dark"),
		base,
	)
	for x: float in [1.0, w - 4.0]:
		var arm := spec.area(x, d * 0.32, 3, d * 0.42)
		kit.box(
			MeshKit.volume(arm, seat_low, ObjectMeshChairConfig.office_arm_height - seat_low),
			MeshKit.tone(base, &"shadow"),
		)
	_back(spec, kit)
	return kit.build()


## How far (px) from the back edge of the footprint the backrest's pivot stands: in by what it leans
## and half its thickness, so it stays within the footprint. The seat reaches back to it.
static func _back_pivot() -> float:
	var rise := ObjectMeshChairConfig.office_back_height - ObjectMeshChairConfig.office_seat_height
	return 1.5 + sin(ObjectMeshChairConfig.office_back_lean) * rise


## The backrest, a slab leaning away over the rear edge: its pivot stands in by what it leans, so
## it stays within the footprint.
static func _back(spec: FurnitureSpec, kit: MeshKit) -> void:
	var base := spec.color
	var seat_top := ObjectMeshChairConfig.office_seat_height
	var lean := ObjectMeshChairConfig.office_back_lean
	var rise := ObjectMeshChairConfig.office_back_height - seat_top
	var back_w := spec.size.x - 8.0
	var pivot := Vector3(0.0, seat_top, -spec.size.y * 0.5 + _back_pivot())
	spec.level(kit, Transform3D(Basis(Vector3.RIGHT, -lean), pivot))
	kit.box(
		MeshKit.volume(Rect2(-back_w * 0.5, -1.5, back_w, 3.0), 0.0, rise),
		MeshKit.tone(base, &"dark"),
		base,
	)
	spec.level(kit)
