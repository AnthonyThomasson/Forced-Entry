extends RefCounted
## Objects domain, the 3D mesh of the small items (the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`; `docs/stacked-items.md`): at the piece's own footprint and
## `item_painter.gd`'s proportions, by `kind`: a plate, a cup with a handle, a bowl (a rim ring
## round a dark well), a book with its spine and page edge, a desk lamp (a base and a tin shade), a
## monitor (a screen on a stand), a box with a tape strip, a crate with slats. Every item stands on
## its own origin (y 0), so the free body that carries it puts it on the floor or on a top.

const ItemStockMesh = preload("res://scenes/objects/art/item_stock_mesh.gd")
const ItemHomeMesh = preload("res://scenes/objects/art/item_home_mesh.gd")
const OPTIONS := ["kind", "height"]


## The node an item `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"item", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	))
	if _kind(spec) == "hob":  # Its left ring glows hot: the hotplate's old look.
		var foot := spec.within(Rect2(Vector2.ZERO, spec.size))
		rig.add_glow(
			FurnitureMesh.fetch_glow("item", spec, _tuning(spec), func() -> Mesh:
				return ItemStockMesh.glow(spec, foot, height_of(spec))),
			ObjectArtKitchenBathConfig.hotplate_ring_color,
		)
	return rig


## The kind the piece is: its `art_opts.kind`.
static func _kind(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("kind", "box"))


## How tall the piece stands: its `art_opts.height`, else its kind's.
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	if _kind(spec) in ItemStockMesh.KINDS:
		return ItemStockMesh.height_of(_kind(spec))
	var kinds := {
		"plate": ObjectMeshItemConfig.plate_height,
		"cup": ObjectMeshItemConfig.cup_height,
		"bowl": ObjectMeshItemConfig.bowl_height,
		"book": ObjectMeshItemConfig.book_height,
		"desk_lamp": ObjectMeshItemConfig.desk_lamp_height,
		"monitor": ObjectMeshItemConfig.monitor_height,
		"crate": ObjectMeshItemConfig.crate_height,
	}
	if ItemHomeMesh.has(_kind(spec)):
		return ItemHomeMesh.height_of(_kind(spec))
	return kinds.get(_kind(spec), ObjectMeshItemConfig.box_height)


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS + ItemStockMesh.OPTIONS),
		"height": height_of(spec),
		"colour": spec.color,
	}


## The radius of a round item: inscribed in its footprint.
static func _radius(spec: FurnitureSpec) -> float:
	return minf(spec.size.x, spec.size.y) * 0.5


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	var high := height_of(spec)
	var radius := _radius(spec)
	var foot := spec.within(Rect2(Vector2.ZERO, spec.size))
	match _kind(spec):
		"plate":
			kit.cylinder(Vector3.ZERO, radius, high, spec.color)
		"cup":
			_cup(kit, spec, radius, high)
		"bowl":
			kit.cylinder(Vector3.ZERO, radius * 0.6, high * 0.4, spec.color)
			kit.cylinder(Vector3(0.0, high * 0.4, 0.0), radius, high * 0.6, spec.color)
		"book":
			_book(kit, spec, foot, high)
		"desk_lamp":
			_desk_lamp(kit, spec, radius, high)
		"monitor":
			_monitor(kit, spec, foot, high)
		"crate":
			_crate(kit, spec, foot, high)
		_:
			if _kind(spec) in ItemStockMesh.KINDS:
				ItemStockMesh.build(kit, spec, _kind(spec), foot, high)
			elif ItemHomeMesh.has(_kind(spec)):
				ItemHomeMesh.shape(kit, spec, _kind(spec), foot, high)
			else:
				_box(kit, spec, foot, high)
	return kit.build()


## A cup: the body and the handle nub on its right.
static func _cup(kit: MeshKit, spec: FurnitureSpec, radius: float, high: float) -> void:
	kit.cylinder(Vector3(-0.5, 0.0, 0.0), radius - 0.5, high, spec.color)
	var nub := Rect2(radius - 1.0, -0.5, 1.5, 1.0)
	kit.box(MeshKit.volume(nub, high * 0.3, high * 0.4), spec.color.darkened(0.2))


## A book: the cover and a darker spine along the left.
static func _book(kit: MeshKit, spec: FurnitureSpec, foot: Rect2, high: float) -> void:
	kit.box(MeshKit.volume(foot, 0.0, high), spec.color, spec.color.lightened(0.1))
	var spine := Rect2(foot.position, Vector2(1.5, foot.size.y))
	kit.box(MeshKit.volume(spine, 0.0, high), spec.color.darkened(0.3))


## A desk lamp: a flat base, a thin neck and a shade.
static func _desk_lamp(kit: MeshKit, spec: FurnitureSpec, radius: float, high: float) -> void:
	var dark := spec.color.darkened(0.3)
	kit.cylinder(Vector3.ZERO, radius * 0.7, 1.0, dark)
	kit.cylinder(Vector3(0.0, 1.0, 0.0), 0.6, high - 6.0, dark)
	kit.cylinder(Vector3(0.0, high - 6.0, 0.0), radius * 0.9, 6.0, spec.color)


## A monitor: a foot, and the screen on it, thin front to back.
static func _monitor(kit: MeshKit, spec: FurnitureSpec, foot: Rect2, high: float) -> void:
	var stand := Rect2(foot.position + Vector2(foot.size.x * 0.4, 0.0),
			Vector2(foot.size.x * 0.2, foot.size.y))
	kit.box(MeshKit.volume(stand, 0.0, 3.0), spec.color.darkened(0.3))
	var screen := Rect2(foot.position, Vector2(foot.size.x, foot.size.y * 0.3))
	kit.box(MeshKit.volume(screen, 3.0, high - 3.0), spec.color, spec.color.lightened(0.2))


## A crate: the body and a slat across its front.
static func _crate(kit: MeshKit, spec: FurnitureSpec, foot: Rect2, high: float) -> void:
	kit.box(MeshKit.volume(foot, 0.0, high), spec.color, spec.color.lightened(0.08))
	var slat := Rect2(foot.position.x + 1.0, foot.end.y - 0.4, foot.size.x - 2.0, 0.4)
	kit.box(MeshKit.volume(slat, 2.0, high - 4.0), spec.color.darkened(0.3))


## A box: the body and a tape strip across its lid.
static func _box(kit: MeshKit, spec: FurnitureSpec, foot: Rect2, high: float) -> void:
	kit.box(MeshKit.volume(foot, 0.0, high), spec.color, spec.color.lightened(0.05))
	var tape := Rect2(foot.get_center().x - 1.0, foot.position.y, 2.0, foot.size.y)
	kit.box(MeshKit.volume(tape, high, 0.2), spec.color.lightened(0.28))
