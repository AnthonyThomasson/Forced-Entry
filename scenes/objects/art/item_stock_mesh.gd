extends RefCounted
## Objects domain, the 3D meshes of the items the shelves and the stockroom give up
## (`item_mesh.gd` hands the kinds named here to it; `docs/stacked-items.md` SI13): a pallet
## (stringers and
## slats), a shrink-wrapped box with its label, a standing book, a pair of shoes, the hotplate's
## plate with its hot ring, a pan with its handle and a pot with its two. Every one stands on its
## own origin (y 0), like every item.

const KINDS := ["pallet", "wrapped_box", "book_stood", "shoes", "hob", "pan", "pot"]
## The options the kinds here read (`item_mesh.gd` adds them to its own).
const OPTIONS := ["spines"]


## How tall the kind `kind` stands (`ObjectMeshStockItemConfig`).
static func height_of(kind: String) -> float:
	var heights := {
		"pallet": ObjectMeshStockItemConfig.pallet_height,
		"wrapped_box": ObjectMeshStockItemConfig.wrapped_box_height,
		"book_stood": ObjectMeshStockItemConfig.book_stood_height,
		"shoes": ObjectMeshStockItemConfig.shoes_height,
		"hob": ObjectMeshKitchenConfig.hotplate_plate_height,
		"pan": ObjectMeshKitchenConfig.hotplate_pan_height,
		"pot": ObjectMeshStockItemConfig.pot_height,
	}
	return heights[kind]


## The solids of the item `kind` of `spec` in `foot` (its footprint) `high` tall, in its colour.
static func build(
	kit: MeshKit,
	spec: FurnitureSpec,
	kind: String,
	foot: Rect2,
	high: float,
) -> void:
	var colour := spec.color
	match kind:
		"pallet":
			_pallet(kit, foot, high, colour)
		"wrapped_box":
			_wrapped_box(kit, foot, high, colour)
		"book_stood":
			_books(kit, spec, foot, high)
		"shoes":
			_shoes(kit, foot, high, colour)
		"hob":
			kit.box(MeshKit.volume(foot, 0.0, high), colour, colour.lightened(0.1))
		"pan":
			_pan(kit, foot, high, colour)
		_:
			_pot(kit, foot, high, colour)


## The hot ring of the `hob`: a glowing disc on the left of its plate (the hotplate's old look).
static func glow(spec: FurnitureSpec, foot: Rect2, high: float) -> Mesh:
	var kit := spec.kit()
	var radius := maxf(3.0, floorf(foot.size.y * 0.5) - 2.0)
	var at := foot.position + Vector2(radius + 2.0 - 3.0, foot.size.y * 0.5)
	kit.cylinder(
		Vector3(at.x, high, at.y), radius, 0.6, ObjectArtKitchenBathConfig.hotplate_ring_color
	)
	return kit.build()


## A run of standing books: a spine each (`spines`: `[[x from the left, width, height, colour]]`),
## or one book of the footprint; the page edge pale at the back of each.
static func _books(kit: MeshKit, spec: FurnitureSpec, foot: Rect2, high: float) -> void:
	var spines: Array = spec.opts.get("spines", [])
	if spines.is_empty():
		spines = [[0.0, foot.size.x, high, spec.color]]
	for spine: Array in spines:
		var area := Rect2(foot.position + Vector2(spine[0], 0.0), Vector2(spine[1], foot.size.y))
		var colour: Color = spine[3]
		var paper: Color = ObjectArtDecorConfig.prop_colors["paper"]
		kit.box(MeshKit.volume(area, 0.0, spine[2]), colour, paper)
		var edge := Rect2(area.end.x - 0.6, area.position.y, 0.6, area.size.y)
		kit.box(MeshKit.volume(edge, 0.0, spine[2]), Color(0.92, 0.9, 0.82))


## The stringers across the deck's depth and the slats over them.
static func _pallet(kit: MeshKit, foot: Rect2, high: float, colour: Color) -> void:
	for x: float in [0.0, foot.size.x * 0.5 - 4.0, foot.size.x - 8.0]:
		var stringer := Rect2(foot.position + Vector2(x, 0.0), Vector2(8.0, foot.size.y))
		kit.box(MeshKit.volume(stringer, 0.0, high - 1.5), MeshKit.tone(colour, &"dark"))
	for y in range(0, int(foot.size.y), 12):
		var slat := Rect2(
			foot.position + Vector2(0.0, y), Vector2(foot.size.x, minf(9.0, foot.size.y - y))
		)
		kit.box(MeshKit.volume(slat, high - 1.5, 1.5), colour)


## A cardboard box under shrink wrap with a label on its lid.
static func _wrapped_box(kit: MeshKit, foot: Rect2, high: float, colour: Color) -> void:
	kit.box(MeshKit.volume(foot, 0.0, high), colour, colour.lightened(0.06))
	var label := Rect2(foot.get_center() - Vector2(5.0, 3.0), Vector2(10.0, 6.0))
	kit.box(MeshKit.volume(label, high, 0.4), Color(0.92, 0.9, 0.84))


## A pair of soles, toes toward the front, a dark opening near each heel.
static func _shoes(kit: MeshKit, foot: Rect2, high: float, colour: Color) -> void:
	var sole := (foot.size.x - 1.0) * 0.5
	for i in 2:
		var at := Rect2(foot.position + Vector2(i * (sole + 1.0), 0.0), Vector2(sole, foot.size.y))
		kit.box(MeshKit.volume(at, 0.0, high), colour, colour.lightened(0.08))
		var mouth := Rect2(at.position + Vector2(1.0, 1.0), Vector2(maxf(1.0, sole - 2.0), 2.5))
		kit.box(MeshKit.volume(mouth, high, 0.2), colour.darkened(0.55))


## A pan: a round dish and its handle reaching out to the right, both inside the footprint.
static func _pan(kit: MeshKit, foot: Rect2, high: float, colour: Color) -> void:
	var radius := minf(foot.size.x, foot.size.y) * 0.5 - 2.0
	var mid := foot.get_center() - Vector2(2.0, 0.0)
	kit.cylinder(Vector3(mid.x, 0.0, mid.y), radius, high, colour, colour.lightened(0.15))
	var grip := Rect2(mid + Vector2(radius - 1.0, -1.0), Vector2(4.0, 2.0))
	kit.box(MeshKit.volume(grip, high - 1.5, 1.5), colour)


## A pot: a tall round body and two handles.
static func _pot(kit: MeshKit, foot: Rect2, high: float, colour: Color) -> void:
	var radius := minf(foot.size.x, foot.size.y) * 0.5
	var mid := foot.get_center()
	kit.cylinder(Vector3(mid.x, 0.0, mid.y), radius, high, colour, colour.lightened(0.12))
	for side: float in [-1.0, 1.0]:
		var grip := Rect2(mid + Vector2(side * radius - 0.8, -1.0), Vector2(1.6, 2.0))
		kit.box(MeshKit.volume(grip, high * 0.7, 1.5), colour.darkened(0.2))
