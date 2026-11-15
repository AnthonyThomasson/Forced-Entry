extends RefCounted
## Objects domain, the 3D mesh of a table (the pattern every furniture mesh follows,
## `object_meshes.gd` and `domain-art/meshes.md`): a top slab over four legs built from Art's mesh
## kit, at the piece's own footprint, the painter's colour on the top and a darker tone of it on the
## legs. The mesh is built once per footprint and colour (`MeshCache`) and shared by every table
## alike.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")


## The node a table `piece` (an `EnvironmentObject`: its `size` and `color`) is shown by, in 3D
## units with its origin at the piece's origin (the footprint centred on it).
static func build(piece: Node2D) -> Node3D:
	var size: Vector2 = piece.get("size")
	var wood := ObjectArt.drawn_color(piece.get("color"))
	var height := height_of(size, _opts_of(piece))
	var key := MeshCache.key("table", size, wood, _tuning(height))
	return MeshNodes.instance(
		MeshCache.fetch(key, func() -> Mesh: return _mesh(size, wood, height))
	)


## How tall a table of `size` stands: the piece's own `art_opts.height` when it names one, else the
## low table's for a small footprint (a side table), else the standard table's. The pattern every
## piece with a size-dependent height follows: the number is the piece's data or a rule of its
## size, in a holder, never a literal in the builder.
static func height_of(size: Vector2, opts: Dictionary) -> float:
	var own: Variant = opts.get("height")
	if own is float or own is int:
		return float(own)
	if size.x * size.y <= ObjectMeshConfig.table_low_area:
		return ObjectMeshConfig.table_low_height
	return ObjectMeshConfig.table_height


## `piece`'s `look.art_opts` (empty when it has none), read duck-typed.
static func _opts_of(piece: Node2D) -> Dictionary:
	var look: Variant = piece.get("look")
	if look is Object and (look as Object).get("art_opts") is Dictionary:
		return (look as Object).get("art_opts")
	return {}


## Every value the shape reads (the table's `height`, and the holder's proportions), so a change of
## any is a different mesh.
static func _tuning(height: float) -> Dictionary:
	return {
		"height": height,
		"top": ObjectMeshConfig.table_top_thickness,
		"leg": ObjectMeshConfig.table_leg,
		"inset": ObjectMeshConfig.table_leg_inset,
	}


## The table: slab on top, a leg in each corner (inset) under it, `wood` its colour.
static func _mesh(size: Vector2, wood: Color, height: float) -> Mesh:
	var top_at := height - ObjectMeshConfig.table_top_thickness
	var half := size * 0.5
	var kit := MeshKit.new()
	kit.box(
		MeshKit.volume(Rect2(-half, size), top_at, ObjectMeshConfig.table_top_thickness),
		MeshKit.tone(wood, &"dark"),
		wood,
	)
	var leg := ObjectMeshConfig.table_leg
	var inset := ObjectMeshConfig.table_leg_inset
	var leg_colour := MeshKit.tone(wood, &"shadow")
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var outer: Vector2 = half * corner - corner * inset
		var leg_rect := Rect2(
			outer - Vector2(leg, leg) * 0.5 - corner * leg * 0.5,
			Vector2(leg, leg),
		)
		kit.box(MeshKit.volume(leg_rect, 0.0, top_at), leg_colour)
	return kit.build()
