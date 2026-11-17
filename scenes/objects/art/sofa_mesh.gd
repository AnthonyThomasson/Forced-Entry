extends RefCounted
## Objects domain, the 3D mesh of a sofa or armchair (the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): at the piece's own footprint and the painter's own proportions
## (`sofa_painter.gd`: the backrest's depth, the armrests' width, the cushions across the seat,
## `ObjectArtFabricConfig.sofa_*` and the piece's `art_opts`), a frame under a row of seat
## cushions, a backrest across the back and a rolled armrest at each end, in the upholstery colour.
## Built once per footprint, colour and look (`MeshCache`) and shared by every sofa alike.

const OPTIONS := ["back_depth", "arm_width", "cushion_width", "max_cushions"]


## The node a sofa `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var mesh := FurnitureMesh.fetch(
		"sofa", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	)
	return FurnitureMesh.show(piece, mesh)


## The backrest's depth, an armrest's width and how many cushions lie across the seat, from the
## painter's rules (`sofa_painter.gd`).
static func layout(spec: FurnitureSpec) -> Dictionary:
	var back := clampi(
		roundi(spec.size.y * float(_opt(spec, "back_depth"))), 4, int(spec.size.y / 2.0)
	)
	var arm := clampi(
		roundi(spec.size.x * float(_opt(spec, "arm_width"))), 3, int(spec.size.x / 4.0)
	)
	var cushion := float(_opt(spec, "cushion_width")) * ArtCanvasConfig.pixel_size
	var count := clampi(
		roundi((spec.size.x - 2.0 * arm) / cushion), 1, int(_opt(spec, "max_cushions"))
	)
	return { "back": back, "arm": arm, "count": count }


## The option `name` of `spec`, else the painter's default.
static func _opt(spec: FurnitureSpec, name: String) -> Variant:
	return spec.opts.get(name, _defaults()[name])


## The painter's own default for each option the shape reads.
static func _defaults() -> Dictionary:
	return {
		"back_depth": ObjectArtFabricConfig.sofa_back_depth,
		"arm_width": ObjectArtFabricConfig.sofa_arm_width,
		"cushion_width": ObjectArtFabricConfig.sofa_cushion_width,
		"max_cushions": ObjectArtFabricConfig.sofa_max_cushions,
	}


## Every value the shape reads: the painter's options (with their defaults) and the holder's
## heights.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS, _defaults()),
		"pixel": ArtCanvasConfig.pixel_size,
		"frame": ObjectMeshSeatConfig.sofa_frame_height,
		"seat": ObjectMeshSeatConfig.sofa_seat_height,
		"arm": ObjectMeshSeatConfig.sofa_arm_height,
		"back": ObjectMeshSeatConfig.sofa_back_height,
		"seam": ObjectMeshSeatConfig.sofa_seam,
	}


## The solids of the piece, built once per cache key: the frame, the cushions, the back and arms.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var base := spec.color
	var rows := layout(spec)
	var back_d: float = rows["back"]
	var arm_w: float = rows["arm"]
	var w := spec.size.x
	var d := spec.size.y
	var kit := spec.kit()
	kit.box(
		MeshKit.volume(spec.area(0, 0, w, d), 0.0, ObjectMeshSeatConfig.sofa_frame_height),
		MeshKit.tone(base, &"shadow"),
	)
	_cushions(spec, kit, rows)
	kit.box(
		MeshKit.volume(
			spec.area(arm_w, 0, w - 2.0 * arm_w, back_d),
			0.0,
			ObjectMeshSeatConfig.sofa_back_height,
		),
		MeshKit.tone(base, &"dark"),
		base,
	)
	for x: float in [0.0, w - arm_w]:
		kit.box(
			MeshKit.volume(spec.area(x, 0, arm_w, d), 0.0, ObjectMeshSeatConfig.sofa_arm_height),
			base,
			MeshKit.tone(base, &"light"),
		)
	return kit.build()


## The row of seat cushions between the arms, a seam between two.
static func _cushions(spec: FurnitureSpec, kit: MeshKit, rows: Dictionary) -> void:
	var count: int = rows["count"]
	var arm_w: float = rows["arm"]
	var back_d: float = rows["back"]
	var frame := ObjectMeshSeatConfig.sofa_frame_height
	var seam := ObjectMeshSeatConfig.sofa_seam
	var seat_w := spec.size.x - 2.0 * arm_w
	for i in count:
		var x0 := arm_w + roundf(float(i) * seat_w / count)
		var x1 := arm_w + roundf(float(i + 1) * seat_w / count)
		var rect := spec.area(x0 + seam * 0.5, back_d, x1 - x0 - seam, spec.size.y - back_d)
		kit.box(
			MeshKit.volume(rect, frame, ObjectMeshSeatConfig.sofa_seat_height - frame), spec.color
		)
