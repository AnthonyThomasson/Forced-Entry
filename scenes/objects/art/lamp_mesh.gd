extends RefCounted
## Objects domain, the 3D mesh of a floor lamp (#193 phase 2; the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): within the inscribed circle of its round footprint, a base, a pole and
## a tin shade (`ObjectArtDecorConfig.lamp_tin_color`, not the piece's colour: it only tints the
## debris) open at the top, dark inside, with the bare bulb showing over its rim
## (`lamp_painter.gd`). The bulb is a glow node of the piece's rig
## (`ObjectArtDecorConfig.lamp_glow_color`, or its neon): no real light, which phase 3 gives.

const Decay = preload("res://scenes/objects/art/decay.gd")


## The node a lamp `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"lamp", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	var glow := FurnitureMesh.fetch_glow(
		"lamp", spec, tuning, func() -> Mesh: return _glow(spec)
	)
	rig.add_glow(glow, _glow_color(spec), ObjectMeshStateConfig.bulb_strength)
	return rig


## The colour the bulb glows in: its neon, else the bare bulb's.
static func _glow_color(spec: FurnitureSpec) -> Color:
	var neon := Decay.neon(spec.opts)
	return neon if neon.a > 0.0 else ObjectArtDecorConfig.lamp_glow_color


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"neon": String(spec.opts.get("neon", "")),
		"height": ObjectMeshDecorConfig.lamp_height,
		"shade": ObjectMeshDecorConfig.lamp_shade,
		"pole": ObjectMeshDecorConfig.lamp_pole,
		"tin": ObjectArtDecorConfig.lamp_tin_color,
		"bulb": ObjectArtDecorConfig.lamp_glow_color,
	}


## The radius of the shade, inscribed in the round footprint.
static func _radius(spec: FurnitureSpec) -> float:
	return floorf(minf(spec.size.x, spec.size.y) / 2.0) - 2.0


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var tin := ObjectArtDecorConfig.lamp_tin_color
	var radius := _radius(spec)
	var shade_h := ObjectMeshDecorConfig.lamp_shade
	var shade_at := ObjectMeshDecorConfig.lamp_height - shade_h
	var kit := spec.kit()
	kit.cylinder(Vector3.ZERO, radius * 0.45, 1.5, MeshKit.tone(tin, &"dark"))
	kit.cylinder(
		Vector3(0.0, 1.5, 0.0),
		ObjectMeshDecorConfig.lamp_pole,
		shade_at - 1.5,
		MeshKit.tone(tin, &"dark"),
	)
	kit.revolve(
		PackedVector2Array([
			Vector2(radius, 0.0), Vector2(radius * 0.6, shade_h), Vector2(radius * 0.45, shade_h),
		]),
		Vector3(0.0, shade_at, 0.0),
		tin,
	)
	kit.cylinder(
		Vector3(0.0, shade_at + shade_h - 1.5, 0.0), radius * 0.66, 0.2, tin.darkened(0.55)
	)
	return kit.build()


## The bare bulb over the shade's dark inside.
static func _glow(spec: FurnitureSpec) -> Mesh:
	var radius := _radius(spec)
	var kit := spec.kit()
	kit.sphere(
		Vector3(0.0, ObjectMeshDecorConfig.lamp_height - 1.5, 0.0),
		maxf(1.5, radius / 3.0),
		ObjectArtDecorConfig.lamp_glow_color,
	)
	return kit.build()
