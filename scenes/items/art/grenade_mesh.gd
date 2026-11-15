class_name GrenadeMesh
extends RefCounted
## Items domain, a grenade's 3D mesh and its art (#193, `domain-art/meshes.md`): the 2D grenade,
## stood up. The body is the painter's flat render turned about its length (a radius per picture row
## from the pixels it drew: the egg, the cylinder, the narrower cap), the lever held down a strip
## along its top where the render with the lever differs from the one without, and the flat art is
## projected straight down onto it (`MeshNodes.textured`, rect from `rect`), so from above it is the
## 2D grenade at the 2D size. One mesh and texture per kind and look (`MeshCache`, `PixelArt`'s
## cache); the character's body places it (`GrenadeArt.held_mesh`).
##
## The frame is the gun's (`GunMesh`): the origin is the weapon hand, the front leads along +z, the
## middle of the grenade `ItemMeshConfig.grenade_ahead` ahead of the hand as the 2D art draws it,
## its axis at the hand's height.


## The mesh of grenade `kind` (a `GrenadeConfig` row id) drawn in `look` (`GrenadeConfig.look`,
## `handle` its `PixelArt.handle`), with the lever held down when `lever` (a grenade thrown has let
## it go). Null for an unknown kind.
static func of(kind: StringName, look: Dictionary, handle: int, lever := true) -> Mesh:
	var row := GrenadeConfig.row(kind)
	if row.is_empty() or look.is_empty():
		return null
	var colours := {}
	for name: String in look:
		if look[name] is Color:
			colours[name] = (look[name] as Color).to_html()
	var key := MeshCache.key("held_grenade", row["art_size"], look["shell"], {
		"painter": (look["painter"] as Script).resource_path, "colours": colours,
		"ahead": ItemMeshConfig.grenade_ahead, "sides": ItemMeshConfig.grenade_sides,
		"lever": ItemMeshConfig.lever_height if lever else 0.0,
	})
	return MeshCache.fetch(key, _make.bind(kind, look, handle, lever))


## The flat art of grenade `kind` (the painter's unlit render, the fuze toward +y), with the lever
## held down when `lever`.
static func texture(kind: StringName, look: Dictionary, handle: int, lever := true) -> Texture2D:
	var row := GrenadeConfig.row(kind)
	if row.is_empty() or look.is_empty():
		return null
	return PixelArt.render_flat(
		look["painter"], row["art_size"], look["shell"],
		{ "kind": kind, "look": handle, "spoon": lever, "material": look["finish"] },
	)


## Where the art lies in the mesh's frame (px): its footprint, its middle `grenade_ahead` ahead of
## the hand; the `rect` `MeshNodes.textured` is given.
static func rect(kind: StringName) -> Rect2:
	var art: Vector2 = GrenadeConfig.row(kind).get("art_size", Vector2.ZERO)
	return Rect2(Vector2(-art.x * 0.5, ItemMeshConfig.grenade_ahead - art.y * 0.5), art)


## The body turned from its silhouette, and the lever's strip.
static func _make(kind: StringName, look: Dictionary, handle: int, lever: bool) -> Mesh:
	var kit := MeshKit.new()
	kit.sides = ItemMeshConfig.grenade_sides
	var bare := texture(kind, look, handle, false).get_image()
	var body := ItemSolid.of(bare, rect(kind))
	_body(kit, body)
	if lever:
		var held := texture(kind, look, handle, true).get_image()
		_lever(kit, body.added(held, bare), body)
	return kit.build()


## The body: a solid turned about the grenade's length (laid along z, its axis at the hand's
## height), a radius per picture row from the pixels drawn there, its ends flat.
static func _body(kit: MeshKit, solid: ItemSolid) -> void:
	var runs := solid.runs
	var cell := solid.cell
	var profile := PackedVector2Array()
	var first := true
	for y in runs.size():
		var pairs: PackedInt32Array = runs[y]
		if pairs.is_empty():
			continue
		var radius := float(pairs[pairs.size() - 1] - pairs[0]) * cell * 0.5
		if first:
			profile.append(Vector2(0.0, y * cell))
			profile.append(Vector2(radius, y * cell))
			first = false
		profile.append(Vector2(radius, (y + 0.5) * cell))
		if y == runs.size() - 1 or (runs[y + 1] as PackedInt32Array).is_empty():
			profile.append(Vector2(radius, (y + 1) * cell))
			profile.append(Vector2(0.0, (y + 1) * cell))
	kit.pose(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, solid.origin.y)))
	kit.revolve(profile, Vector3.ZERO, Color.WHITE)
	kit.pose(Transform3D.IDENTITY)


## The lever: a strip over each stretch of pixels the lever's render adds (`added`), laid on the
## `body` where it curves under it (a radius per row).
static func _lever(kit: MeshKit, added: ItemSolid, body: ItemSolid) -> void:
	var cell := body.cell
	var axis := 0.0
	for y in added.runs.size():
		var pairs: PackedInt32Array = added.runs[y]
		var under: PackedInt32Array = body.runs[y]
		if pairs.is_empty() or under.is_empty():
			continue
		var radius := float(under[under.size() - 1] - under[0]) * cell * 0.5
		axis = body.origin.x + float(under[0] + under[under.size() - 1]) * cell * 0.5
		for k in range(0, pairs.size(), 2):
			_strip(kit, body, Vector3(pairs[k], pairs[k + 1], y), radius, axis)


## One strip of the lever from picture pixel `x.x` to `x.y` on row `x.z`, over the body's surface
## (`radius`, turned about `axis`) at the strip's inner edge, where it is highest under it, so the
## strip stands off the body.
static func _strip(kit: MeshKit, body: ItemSolid, x: Vector3, radius: float, axis: float) -> void:
	var left := body.origin.x + x.x * body.cell
	var right := body.origin.x + x.y * body.cell
	var edge := 0.0 if left <= axis and right >= axis else minf(
		absf(left - axis),
		absf(right - axis),
	)
	var under := sqrt(maxf(radius * radius - edge * edge, 0.0))
	kit.box(
		AABB(
			Vector3(left, under - body.cell * 0.5, body.origin.y + x.z * body.cell),
			Vector3(right - left, body.cell * 0.5 + ItemMeshConfig.lever_height, body.cell),
		),
		Color.WHITE,
	)
