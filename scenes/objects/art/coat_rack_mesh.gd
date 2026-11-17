extends RefCounted
## Objects domain, the 3D mesh of a coat rack (the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): within the inscribed circle of its round footprint, a wooden post on a
## round foot with four hook arms at the top, three coats hanging round it and a hat on top
## (`coat_rack_painter.gd`; the coats' and the hat's colours are picked by a generator seeded from
## the look from `ObjectArtDecorConfig.prop_colors`). Shared by every coat rack of one look.


## The node a coat rack `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var mesh := FurnitureMesh.fetch(
		"coat_rack", spec, _tuning(), func() -> Mesh: return _mesh(spec)
	)
	return FurnitureMesh.show(piece, mesh)


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning() -> Dictionary:
	return {
		"height": ObjectMeshDecorConfig.coat_rack_height,
		"coat": ObjectMeshDecorConfig.coat_rack_coat,
		"props": ObjectArtDecorConfig.prop_colors,
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var wood := spec.color
	var radius := floorf(minf(spec.size.x, spec.size.y) / 2.0) - 1.0
	var height := ObjectMeshDecorConfig.coat_rack_height
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["coat_rack", spec.size, spec.color])
	var kit := spec.kit()
	kit.cylinder(Vector3.ZERO, radius * 0.4, 1.5, MeshKit.tone(wood, &"shadow"))
	kit.cylinder(Vector3(0.0, 1.5, 0.0), 1.4, height - 1.5, wood, MeshKit.tone(wood, &"light"))
	for i in 4:
		spec.level(kit, Transform3D(Basis(Vector3.UP, PI * 0.25 + TAU * i / 4.0), Vector3.ZERO))
		kit.box(
			MeshKit.volume(Rect2(0.0, -0.75, radius * 0.7, 1.5), height - 5.0, 1.5),
			MeshKit.tone(wood, &"dark"),
		)
	var spin := 0.3
	var coat_h := ObjectMeshDecorConfig.coat_rack_coat
	for i in 3:
		spec.level(kit, Transform3D(Basis(Vector3.UP, spin + TAU * i / 3.0), Vector3.ZERO))
		var wide := radius * 0.7
		kit.box(
			MeshKit.volume(
				Rect2(radius * 0.35, -wide * 0.5, 3.0, wide),
				height - 5.0 - coat_h,
				coat_h,
			),
			_pick(rng, "coats"),
		)
	spec.level(kit)
	var hat := _pick(rng, "coats")
	kit.cylinder(Vector3(0.0, height, 0.0), maxf(2.0, radius * 0.42), 1.0, hat.darkened(0.2))
	kit.cylinder(Vector3(0.0, height + 1.0, 0.0), maxf(1.0, radius * 0.27), 3.0, hat)
	return kit.build()


## A colour of `list` of `ObjectArtDecorConfig.prop_colors`, picked by `rng`.
static func _pick(rng: RandomNumberGenerator, list: String) -> Color:
	var colours: Array = ObjectArtDecorConfig.prop_colors[list]
	return colours[rng.randi_range(0, colours.size() - 1)]
