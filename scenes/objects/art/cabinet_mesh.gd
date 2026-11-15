extends RefCounted
## Objects domain, the 3D mesh of a cabinet (#193 phase 2; the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): at the piece's own footprint, a carcass in the piece's colour with a
## front of doors across it or drawers stacked up it (`cabinet_painter.gd`: `front`, `count`,
## `crown`, `handle`), a handle on each, and a crown slab on a wardrobe. How tall it stands is the
## piece's own `art_opts.height`, else a rule of its footprint and look (`height_of`). Shared by
## every cabinet alike.

const OPTIONS := ["front", "count", "crown", "handle", "height"]
## The gap (px) at the bottom and the top of the carcass left bare by its front.
const FRONT_MARGIN := 2.0


## The node a cabinet `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var mesh := FurnitureMesh.fetch(
		"cabinet", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	)
	return FurnitureMesh.show(piece, mesh)


## How tall a cabinet of `spec` stands: its `art_opts.height`, else a wardrobe's (a crown), else a
## nightstand's for a small footprint, else the standard.
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	if spec.opts.get("crown", ObjectArtStorageConfig.cabinet_crown):
		return ObjectMeshStorageConfig.cabinet_tall_height
	if spec.size.x * spec.size.y <= ObjectMeshStorageConfig.cabinet_low_area:
		return ObjectMeshStorageConfig.cabinet_low_height
	return ObjectMeshStorageConfig.cabinet_height


## The painter's own default for each option the shape reads.
static func _defaults() -> Dictionary:
	return {
		"front": ObjectArtStorageConfig.cabinet_front,
		"count": ObjectArtStorageConfig.cabinet_count,
		"crown": ObjectArtStorageConfig.cabinet_crown,
		"handle": ObjectArtStorageConfig.cabinet_handle_color,
	}


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS, _defaults()),
		"height": height_of(spec),
		"top": ObjectMeshStorageConfig.cabinet_top,
		"gap": ObjectMeshStorageConfig.cabinet_gap,
		"front": ObjectMeshStorageConfig.cabinet_front,
	}


## The solids of the piece, built once per cache key: the carcass and its crown, then the front.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var h := height_of(spec)
	var crown: bool = spec.opts.get("crown", ObjectArtStorageConfig.cabinet_crown)
	var proud := ObjectMeshStorageConfig.cabinet_front
	var kit := spec.kit()
	var carcass_top := h - (ObjectMeshStorageConfig.cabinet_top if crown else 0.0)
	var inset := 1.0 if crown else 0.0
	var w := spec.size.x
	var d := spec.size.y
	kit.box(
		MeshKit.volume(spec.area(inset, 0, w - 2.0 * inset, d - 2.0 * proud), 0.0, carcass_top),
		MeshKit.tone(spec.color, &"dark"),
		spec.color,
	)
	if crown:
		kit.box(
			MeshKit.volume(spec.area(0, 0, w, d - proud), carcass_top, h - carcass_top), spec.color
		)
	var front := String(spec.opts.get("front", ObjectArtStorageConfig.cabinet_front))
	var count := maxi(1, int(spec.opts.get("count", ObjectArtStorageConfig.cabinet_count)))
	if front == "drawers":
		_drawers(spec, kit, count, carcass_top)
	elif front == "doors":
		_doors(spec, kit, count, carcass_top)
	return kit.build()


## `count` drawers stacked up the front, each with a handle across its middle.
static func _drawers(spec: FurnitureSpec, kit: MeshKit, count: int, top: float) -> void:
	var proud := ObjectMeshStorageConfig.cabinet_front
	var gap := ObjectMeshStorageConfig.cabinet_gap
	var handle: Color = spec.opts.get("handle", ObjectArtStorageConfig.cabinet_handle_color)
	var d := spec.size.y
	var each := (top - FRONT_MARGIN * 2.0) / count
	for i in count:
		var at := FRONT_MARGIN + each * i
		kit.box(
			MeshKit.volume(spec.area(2, d - 2.0 * proud, spec.size.x - 4, proud), at, each - gap),
			spec.color,
		)
		var grip := spec.area(spec.size.x * 0.5 - 4.0, d - proud, 8, proud)
		kit.box(MeshKit.volume(grip, at + (each - gap) * 0.5 - 0.75, 1.5), handle)


## `count` doors across the front, each with a handle on the side away from its hinge.
static func _doors(spec: FurnitureSpec, kit: MeshKit, count: int, top: float) -> void:
	var proud := ObjectMeshStorageConfig.cabinet_front
	var gap := ObjectMeshStorageConfig.cabinet_gap
	var handle: Color = spec.opts.get("handle", ObjectArtStorageConfig.cabinet_handle_color)
	var d := spec.size.y
	var each := (spec.size.x - 4.0) / count
	for i in count:
		var panel := spec.area(2.0 + each * i, d - 2.0 * proud, each - gap, proud)
		kit.box(MeshKit.volume(panel, FRONT_MARGIN, top - FRONT_MARGIN * 2.0), spec.color)
		var edge := (each * (i + 1) - gap - 3.0) if i % 2 == 0 else (each * i + 2.0)
		var grip := spec.area(2.0 + edge, d - proud, 1.5, proud)
		kit.box(MeshKit.volume(grip, top * 0.5 - 3.0, 6.0), handle)
