extends RefCounted
## Objects domain, the 3D mesh of a rug or mat (#193 phase 2; the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): walk-over decor a fraction of a px thick (`ObjectMeshDecorConfig`), so
## it lies on the floor like the 2D art and a character stands on it. A woven rug has a darker
## border round a field of the piece's colour (`rug_painter.gd`: its border and fringe rules) and
## by `pattern` a stepped diamond medallion (three nested diamonds) or darker stripes; a `plush`
## mat is rounded with a darker rim. Shared by every rug of one look.

const OPTIONS := ["pattern"]


## The node a rug `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var mesh := FurnitureMesh.fetch(
		"rug", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	)
	return FurnitureMesh.show(piece, mesh)


## The rug's pattern: the piece's `art_opts.pattern`, else the painter's.
static func pattern_of(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("pattern", ObjectArtFabricConfig.rug_pattern))


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"pattern": pattern_of(spec),
		"thick": ObjectMeshDecorConfig.rug_height,
		"lift": ObjectMeshDecorConfig.rug_field_lift,
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var pattern := pattern_of(spec)
	if pattern == "plush":
		return _plush(spec)
	var base := spec.color
	var thick := ObjectMeshDecorConfig.rug_height
	var kit := spec.kit()
	var along_x := spec.size.x >= spec.size.y
	var fringe := clampf(roundf(maxf(spec.size.x, spec.size.y) * 0.025), 2.0, 5.0)
	var body := (
		Rect2(fringe, 0.0, spec.size.x - fringe * 2.0, spec.size.y)
		if along_x
		else Rect2(0.0, fringe, spec.size.x, spec.size.y - fringe * 2.0)
	)
	var border_colour := base.darkened(0.38)
	var field := body.grow(-clampf(roundf(minf(body.size.x, body.size.y) * 0.1), 3.0, 10.0))
	kit.box(
		MeshKit.volume(
			spec.area(body.position.x, body.position.y, body.size.x, body.size.y), 0.0, thick
		),
		border_colour,
	)
	if pattern == "stripes":
		kit.box(
			MeshKit.volume(
				spec.area(field.position.x, field.position.y, field.size.x, field.size.y),
				thick,
				ObjectMeshDecorConfig.rug_field_lift,
			),
			base,
		)
		_stripes(spec, kit, field, along_x)
	else:
		_medallion(spec, kit, field, border_colour)
	return kit.build()


## A rounded mat: a darker rim under a lighter rounded top.
static func _plush(spec: FurnitureSpec) -> Mesh:
	var thick := ObjectMeshDecorConfig.rug_height
	var kit := spec.kit()
	var whole := Rect2(-spec.half(), spec.size)
	var corner := minf(6.0, minf(spec.size.x, spec.size.y) / 3.0)
	kit.extrude(_rounded(whole, corner), 0.0, thick, spec.color.darkened(0.35))
	kit.extrude(
		_rounded(whole.grow(-1.5), corner * 0.7),
		thick,
		ObjectMeshDecorConfig.rug_field_lift,
		spec.color,
	)
	return kit.build()


## Every other band of an eighth of the field, darker, across the rug's length.
static func _stripes(spec: FurnitureSpec, kit: MeshKit, field: Rect2, along_x: bool) -> void:
	var span := field.size.y if along_x else field.size.x
	var band := maxf(3.0, floorf(span / 8.0))
	var top := ObjectMeshDecorConfig.rug_height + ObjectMeshDecorConfig.rug_field_lift
	var a := band
	while a < span:
		var rect := (
			Rect2(field.position.x, field.position.y + a, field.size.x, minf(band, span - a))
			if along_x
			else Rect2(field.position.x + a, field.position.y, minf(band, span - a), field.size.y)
		)
		var band_rect := spec.area(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
		kit.box(
			MeshKit.volume(band_rect, top, ObjectMeshDecorConfig.rug_field_lift),
			spec.color.darkened(0.12),
		)
		a += band * 2.0


## The field with three nested diamonds in the middle (the outer ring in a darker tone of the field,
## the middle in the border's, the centre pale), laid as one flat piece at one height: the field
## around the diamonds is eight triangles and each ring four trapezoids, none over another, so
## there is no stepped edge for the outline pass to break into dashes.
static func _medallion(
	spec: FurnitureSpec,
	kit: MeshKit,
	field: Rect2,
	border_colour: Color,
) -> void:
	_field_around(spec, kit, field)
	var base := spec.color
	var rows := [
		[1.0, 0.55, base.darkened(0.12)],
		[0.55, 0.3, border_colour],
		[0.3, 0.0, base.lightened(0.28)],
	]
	for row: Array in rows:
		_ring(spec, kit, field, row)


## The field's four side triangles and four corner triangles round the outer diamond.
static func _field_around(spec: FurnitureSpec, kit: MeshKit, field: Rect2) -> void:
	var thick := ObjectMeshDecorConfig.rug_height
	var lift := ObjectMeshDecorConfig.rug_field_lift
	var outer := _diamond(field, spec, 1.0)
	var corners := PackedVector2Array([
		field.position - spec.half(),
		Vector2(field.end.x, field.position.y) - spec.half(),
		field.end - spec.half(),
		Vector2(field.position.x, field.end.y) - spec.half(),
	])
	# diamond points: 0 top, 1 right, 2 bottom, 3 left; corners: 0 top-left ... 3 bottom-left
	for i in 4:
		var next := (i + 1) % 4
		var side := PackedVector2Array([corners[i], corners[next], outer[i]])
		kit.extrude(side, thick, lift, spec.color)
		var corner := PackedVector2Array([corners[next], outer[next], outer[i]])
		kit.extrude(corner, thick, lift, spec.color)


## The ring of `row` (`[outer k, inner k, colour]`) between two diamonds: four trapezoids, or the
## whole diamond for an inner `k` of 0.
static func _ring(spec: FurnitureSpec, kit: MeshKit, field: Rect2, row: Array) -> void:
	var thick := ObjectMeshDecorConfig.rug_height
	var lift := ObjectMeshDecorConfig.rug_field_lift
	var out := _diamond(field, spec, row[0])
	if row[1] == 0.0:
		kit.extrude(out, thick, lift, row[2])
		return
	var inner := _diamond(field, spec, row[1])
	for i in 4:
		var j := (i + 1) % 4
		kit.extrude(PackedVector2Array([out[i], out[j], inner[j], inner[i]]), thick, lift, row[2])


## A diamond `k` of the way out to the medallion's corners (0.32 of the field each way).
static func _diamond(field: Rect2, spec: FurnitureSpec, k: float) -> PackedVector2Array:
	var o := field.get_center() - spec.half()
	var ax := field.size.x * 0.32 * k
	var ay := field.size.y * 0.32 * k
	return PackedVector2Array([
		o + Vector2(0, -ay), o + Vector2(ax, 0), o + Vector2(0, ay), o + Vector2(-ax, 0),
	])


## `rect` with its corners cut `corner` px (an octagon for a rounded rectangle).
static func _rounded(rect: Rect2, corner: float) -> PackedVector2Array:
	var lo := rect.position
	var hi := rect.end
	return PackedVector2Array([
		Vector2(lo.x + corner, lo.y), Vector2(hi.x - corner, lo.y), Vector2(hi.x, lo.y + corner),
		Vector2(hi.x, hi.y - corner), Vector2(hi.x - corner, hi.y), Vector2(lo.x + corner, hi.y),
		Vector2(lo.x, hi.y - corner), Vector2(lo.x, lo.y + corner),
	])
