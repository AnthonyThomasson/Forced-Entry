extends RefCounted
## Objects domain, the 3D mesh of a wooden chair (#193 phase 2; the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): at the piece's own footprint, a seat on four legs, two back posts and a
## crest rail across the back joined to the seat by spindles (`chair_painter.gd`: the back's depth
## and the spindle count, `ObjectArtTableConfig.chair_*` and the piece's `art_opts`), in the
## painter's wood colour and a darker tone for the legs and spindles. Shared by every chair alike.

const OPTIONS := ["back_depth", "slats"]
## How tall the crest rail is (px).
const RAIL_HEIGHT := 6.0


## The node a chair `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var mesh := FurnitureMesh.fetch(
		"chair", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	)
	return FurnitureMesh.show(piece, mesh)


## The painter's own default for each option the shape reads.
static func _defaults() -> Dictionary:
	return {
		"back_depth": ObjectArtTableConfig.chair_back_depth,
		"slats": ObjectArtTableConfig.chair_slats,
	}


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS, _defaults()),
		"seat": ObjectMeshSeatConfig.chair_seat_height,
		"thick": ObjectMeshSeatConfig.chair_seat_thickness,
		"back": ObjectMeshSeatConfig.chair_back_height,
		"leg": ObjectMeshSeatConfig.chair_leg,
	}


## The solids of the piece, built once per cache key: four legs, the seat, then the back.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var wood := spec.color
	var seat_top := ObjectMeshSeatConfig.chair_seat_height
	var seat_low := seat_top - ObjectMeshSeatConfig.chair_seat_thickness
	var inset := maxf(1.0, floorf(spec.size.x / 14.0))
	var kit := spec.kit()
	for x: float in [inset, spec.size.x - inset - ObjectMeshSeatConfig.chair_leg]:
		var leg := ObjectMeshSeatConfig.chair_leg
		var dark := MeshKit.tone(wood, &"shadow")
		kit.box(MeshKit.volume(spec.area(x, spec.size.y - leg, leg, leg), 0.0, seat_low), dark)
		kit.box(
			MeshKit.volume(spec.area(x, 0, leg, leg), 0.0, ObjectMeshSeatConfig.chair_back_height),
			dark,
		)
	kit.box(
		MeshKit.volume(
			spec.area(inset, 0, spec.size.x - 2.0 * inset, spec.size.y),
			seat_low,
			seat_top - seat_low,
		),
		MeshKit.tone(wood, &"dark"),
		wood,
	)
	_back(spec, kit, inset)
	return kit.build()


## The crest rail across the top of the back and the spindles that join it to the seat.
static func _back(spec: FurnitureSpec, kit: MeshKit, inset: float) -> void:
	var wood := spec.color
	var seat_top := ObjectMeshSeatConfig.chair_seat_height
	var back_top := ObjectMeshSeatConfig.chair_back_height
	var back_d := clampf(
		roundf(
			spec.size.y * float(spec.opts.get("back_depth", ObjectArtTableConfig.chair_back_depth))
		),
		3.0,
		floorf(spec.size.y / 2.0),
	)
	var rail_h := minf(RAIL_HEIGHT, back_top - seat_top)
	var rail_d := maxf(2.0, back_d * 0.55)
	kit.box(
		MeshKit.volume(
			spec.area(inset, 0, spec.size.x - 2.0 * inset, rail_d), back_top - rail_h, rail_h
		),
		wood,
	)
	var slats: int = spec.opts.get("slats", ObjectArtTableConfig.chair_slats)
	for i in slats:
		var x := roundf(float(i + 1) * spec.size.x / (slats + 1)) - 1.0
		kit.box(
			MeshKit.volume(spec.area(x, 0, 2, rail_d), seat_top, back_top - rail_h - seat_top),
			MeshKit.tone(wood, &"shadow"),
		)
