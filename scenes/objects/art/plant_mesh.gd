extends RefCounted
## Objects domain, the 3D mesh of a potted plant (the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): within the inscribed circle of its round footprint, a tapering
## terracotta pot with dark soil and a crown of `leaves` (`art_opts.leaves`,
## `ObjectArtDecorConfig.plant_*`) arching out of it, each a flat strip swept up and over, in two
## tones of the foliage wilted toward dead brown as the painter wilts it. Shared by every plant of
## one look.

const OPTIONS := ["leaves"]


## The node a plant `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var mesh := FurnitureMesh.fetch(
		"plant", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	)
	return FurnitureMesh.show(piece, mesh)


## How many leaves the crown has: the piece's `art_opts.leaves`, else the painter's.
static func leaves_of(spec: FurnitureSpec) -> int:
	return int(spec.opts.get("leaves", ObjectArtDecorConfig.plant_leaves))


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"leaves": leaves_of(spec),
		"pot": ObjectMeshDecorConfig.plant_pot_height,
		"height": ObjectMeshDecorConfig.plant_height,
		"leaf": ObjectMeshDecorConfig.plant_leaf,
		"pot_colour": ObjectArtDecorConfig.plant_pot_color,
		"soil": ObjectArtDecorConfig.plant_soil_color,
		"wilt": ObjectArtDecorConfig.plant_wilt,
		"dead": ObjectArtDecorConfig.plant_dead_color,
	}


## The solids of the piece, built once per cache key: the pot, its soil and the crown of leaves.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var radius := floorf(minf(spec.size.x, spec.size.y) / 2.0) - 1.0
	var pot_h := ObjectMeshDecorConfig.plant_pot_height
	var pot_top := roundf(radius * 0.72)
	var kit := spec.kit()
	kit.revolve(
		PackedVector2Array([
			Vector2(0, 0), Vector2(pot_top * 0.7, 0), Vector2(pot_top, pot_h), Vector2(0, pot_h),
		]),
		Vector3.ZERO,
		ObjectArtDecorConfig.plant_pot_color,
	)
	kit.cylinder(
		Vector3(0.0, pot_h, 0.0), roundf(radius * 0.55), 0.5, ObjectArtDecorConfig.plant_soil_color
	)
	_leaves(spec, kit, radius * 0.9)
	return kit.build()


## `leaves_of(spec)` flat strips swept up and out from the pot, `length` long, alternating tones.
static func _leaves(spec: FurnitureSpec, kit: MeshKit, length: float) -> void:
	var leaf := spec.color.lerp(
		ObjectArtDecorConfig.plant_dead_color,
		ObjectArtDecorConfig.plant_wilt,
	)
	var half := ObjectMeshDecorConfig.plant_leaf * 0.5
	var strip := PackedVector2Array([
		Vector2(-half, -0.4), Vector2(half, -0.4), Vector2(half, 0.4), Vector2(-half, 0.4),
	])
	var top := ObjectMeshDecorConfig.plant_height
	var root := ObjectMeshDecorConfig.plant_pot_height + 1.0
	var n := leaves_of(spec)
	for i in n:
		var dir := Vector2.from_angle(TAU * i / n)
		kit.loft(
			PackedVector3Array([
				_at(dir * length * 0.1, root),
				_at(dir * length * 0.55, top),
				_at(dir * length, top - 5.0),
			]),
			strip,
			leaf if i % 2 == 0 else leaf.darkened(0.14),
		)


## The 3D point over the ground point `plane` (2D px) at `height`.
static func _at(plane: Vector2, height: float) -> Vector3:
	return Vector3(plane.x, height, plane.y)
