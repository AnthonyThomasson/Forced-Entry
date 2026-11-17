extends RefCounted
## Objects domain, the 3D mesh of the tower stockroom's pieces (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and `stock_painter.gd`'s
## proportions, by `kind`. `crates` are two wooden crates stacked, the top one offset toward the
## back as the painter draws it, slats across each face and a plate on the top; `pallet` a wooden
## pallet of slats on stringers with four shrink-wrapped boxes on it, a label on each; `safe` a
## steel body with a lighter top, its door's edge toward the front with a dial and a handle.

const OPTIONS := ["kind", "wood_color", "cardboard_color", "label_color", "height"]
## How far a feature stands proud of the face it is laid on.
const PROUD := 0.5


## The node a stockroom `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	return FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"stock", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	))


## The kind the piece is: its `art_opts.kind`, else the painter's.
static func _kind(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("kind", "crates"))


## The painter's colour option `name` of the piece, else its holder default.
static func _colour(spec: FurnitureSpec, name: String) -> Color:
	var defaults := {
		"wood_color": ObjectArtShopConfig.stock_wood_color,
		"cardboard_color": ObjectArtShopConfig.stock_cardboard_color,
		"label_color": ObjectArtShopConfig.stock_label_color,
	}
	return spec.opts.get(name, defaults[name])


## How tall the piece stands: its `art_opts.height`, else its kind's (a stack of two crates; a
## pallet with its boxes).
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	match _kind(spec):
		"pallet":
			return ObjectMeshShopConfig.pallet_height + ObjectMeshShopConfig.pallet_box_height
		"safe":
			return ObjectMeshShopConfig.safe_height
	return ObjectMeshShopConfig.crate_height * 2.0


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS),
		"height": height_of(spec),
		"crate": ObjectMeshShopConfig.crate_height,
		"pallet": [ObjectMeshShopConfig.pallet_height, ObjectMeshShopConfig.pallet_box_height],
		"wood": _colour(spec, "wood_color"),
		"cardboard": _colour(spec, "cardboard_color"),
		"label": _colour(spec, "label_color"),
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	match _kind(spec):
		"pallet":
			_pallet(spec, kit)
		"safe":
			_safe(spec, kit)
		_:
			_crates(spec, kit)
	return kit.build()


## One crate in `rect` (art px from the back-left corner) from `base` up `height`: its body, a
## slat across each of two faces and a plate on top.
static func _crate(
	spec: FurnitureSpec, kit: MeshKit, rect: Rect2, base: float, height: float
) -> void:
	var wood := _colour(spec, "wood_color")
	kit.box(MeshKit.volume(spec.within(rect), base, height), wood, wood.lightened(0.05))
	var plate := Rect2(
		rect.position + Vector2(6, rect.size.y / 2.0 - 4.0),
		rect.size - Vector2(12, 0),
	)
	plate.size.y = 9.0
	kit.box(MeshKit.volume(spec.within(plate), base + height, 0.6), wood.lightened(0.18))
	var slat := Rect2(rect.position.x + 2.0, rect.end.y - PROUD, rect.size.x - 4.0, PROUD)
	for z in range(int(base) + 4, int(base + height) - 3, 6):
		kit.box(MeshKit.volume(spec.within(slat), float(z), 1.0), wood.darkened(0.3))


## Two crates, the top one offset, a stencilled label on the top plate's face.
static func _crates(spec: FurnitureSpec, kit: MeshKit) -> void:
	var crate := ObjectMeshShopConfig.crate_height
	var label := _colour(spec, "label_color").darkened(0.3)
	_crate(spec, kit, Rect2(0, 8, 38, 38), 0.0, crate)
	_crate(spec, kit, Rect2(8, 0, 38, 38), crate, crate)
	kit.box(MeshKit.volume(spec.area(17, 16, 20, 5), crate * 2.0 + 0.6, 0.3), label)


## The pallet: stringers, slats across them and four wrapped boxes with their labels.
static func _pallet(spec: FurnitureSpec, kit: MeshKit) -> void:
	var wood := _colour(spec, "wood_color")
	var deck := ObjectMeshShopConfig.pallet_height
	var box_h := ObjectMeshShopConfig.pallet_box_height
	for x: float in [0.0, spec.size.x * 0.5 - 4.0, spec.size.x - 8.0]:
		kit.box(
			MeshKit.volume(spec.area(x, 0, 8, spec.size.y), 0.0, deck - 1.5),
			MeshKit.tone(wood, &"dark"),
		)
	for y in range(0, int(spec.size.y), 12):
		kit.box(
			MeshKit.volume(
				spec.area(0, y, spec.size.x, minf(9.0, spec.size.y - y)),
				deck - 1.5,
				1.5,
			),
			wood,
		)
	var corners := [
		Vector2(2, 2), Vector2(spec.size.x - 30.0, 2), Vector2(2, spec.size.y - 24.0),
		Vector2(spec.size.x - 30.0, spec.size.y - 24.0),
	]
	var card := _colour(spec, "cardboard_color")
	for pos: Vector2 in corners:
		kit.box(
			MeshKit.volume(spec.area(pos.x, pos.y, 28, 22), deck, box_h),
			card,
			card.lightened(0.06),
		)
		kit.box(
			MeshKit.volume(spec.area(pos.x + 9.0, pos.y + 8.0, 10, 6), deck + box_h, 0.4),
			Color(0.92, 0.9, 0.84),
		)


## The safe: a steel body, a lighter top, the door's edge with a dial and a handle on its front.
static func _safe(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	var steel := spec.color
	kit.box(MeshKit.volume(spec.area(0, 0, w, d - PROUD), 0.0, height), steel, steel.lightened(0.1))
	kit.box(
		MeshKit.volume(spec.area(3, d - PROUD, w - 6.0, PROUD * 0.5), 3.0, height - 8.0),
		steel.lightened(0.05),
	)
	kit.box(
		MeshKit.volume(spec.area(8, d - PROUD, 4, PROUD), height * 0.5, 4.0),
		Color(0.85, 0.85, 0.8),
	)
	kit.box(
		MeshKit.volume(spec.area(w - 12.0, d - PROUD, 7, PROUD), height * 0.5, 3.0),
		Color(0.06, 0.06, 0.08),
	)
