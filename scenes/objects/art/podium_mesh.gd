extends RefCounted
## Objects domain, the 3D mesh of a segment of a tower's podium (#193 phase 2; the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and `podium_painter.gd`'s
## proportions, a thick concrete slab with a joint cut across it every `joint_step` and square
## pillars standing along its street edge, one every `pillar_step` (the painter takes its colour as
## given: `ObjectArtPodiumConfig.podium_color`, or the piece's `art_opts.color`). Anchored and
## solid; it casts the shadow the 2D art drags across the street.

const OPTIONS := ["color", "pillar_step", "pillar_px", "joint_step", "height"]


## The node a podium `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	return FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"podium", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	))


## The slab's colour: the piece's `art_opts.color`, else the holder's.
static func _slab(spec: FurnitureSpec) -> Color:
	return spec.opts.get("color", ObjectArtPodiumConfig.podium_color)


## How tall the slab stands: its `art_opts.height`, else the holder's.
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	return float(own) if own is float or own is int else ObjectMeshStreetConfig.podium_height


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS),
		"slab": _slab(spec),
		"height": height_of(spec),
		"pillar": ObjectMeshStreetConfig.pillar_height,
		"pillar_step": spec.opts.get("pillar_step", ObjectArtPodiumConfig.podium_pillar_step),
		"pillar_px": spec.opts.get("pillar_px", ObjectArtPodiumConfig.podium_pillar_px),
		"joint_step": spec.opts.get("joint_step", ObjectArtPodiumConfig.podium_joint_step),
	}


## The solids of the piece, built once per cache key: the slab, its joints and the pillars.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var slab := _slab(spec)
	var height := height_of(spec)
	var kit := spec.kit()
	kit.box(
		MeshKit.volume(spec.area(0, 0, spec.size.x, spec.size.y), 0.0, height),
		MeshKit.tone(slab, &"dark"),
		slab,
	)
	var joints := maxi(2, int(spec.opts.get("joint_step", ObjectArtPodiumConfig.podium_joint_step)))
	for x in range(joints, int(spec.size.x), joints):
		kit.box(MeshKit.volume(spec.area(x, 0, 1, spec.size.y), height, 0.2), slab.darkened(0.3))
	var step := maxi(2, int(spec.opts.get("pillar_step", ObjectArtPodiumConfig.podium_pillar_step)))
	var span := mini(
		int(spec.opts.get("pillar_px", ObjectArtPodiumConfig.podium_pillar_px)),
		int(spec.size.y) - 2,
	)
	for x in range(int(step / 4.0), int(spec.size.x) - span, step):
		kit.box(
			MeshKit.volume(
				spec.area(x, spec.size.y - span - 1.0, span, span),
				height,
				maxf(0.1, ObjectMeshStreetConfig.pillar_height - height),
			),
			slab.lightened(0.1),
			slab.darkened(0.12),
		)
	return kit.build()
