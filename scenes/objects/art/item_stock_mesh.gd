extends RefCounted
## Objects domain, the 3D meshes of the items the shelves and the stockroom give up
## (`item_mesh.gd` hands the kinds named here to it; `docs/stacked-items.md` SI13): a pallet
## (stringers and
## slats), a shrink-wrapped box with its label, a standing book, a pair of shoes, a paint tin, the
## hotplate's plate with its hot ring, a pan with its handle and a pot with its two. Every one
## stands on its own origin (y 0), like every item.

## How far (px) a pan's handle reaches past its disc.
const PAN_HANDLE := 5.0
## How thick each step of a brimming pot's top is (px): its rim, its ring, its broth.
const POT_STEP := 0.7
const KINDS := [
	"pallet",
	"wrapped_box",
	"book_stood",
	"shoes",
	"paint_tin",
	"hob",
	"pan",
	"pot",
	"sandbag",
	"hat",
]
## The options the kinds here read (`item_mesh.gd` adds them to its own).
const OPTIONS := ["spines"]


## How tall the kind `kind` stands (`ObjectMeshStockItemConfig`).
static func height_of(kind: String) -> float:
	var heights := {
		"pallet": ObjectMeshStockItemConfig.pallet_height,
		"wrapped_box": ObjectMeshStockItemConfig.wrapped_box_height,
		"book_stood": ObjectMeshStockItemConfig.book_stood_height,
		"shoes": ObjectMeshStockItemConfig.shoes_height,
		"paint_tin": ObjectMeshStockItemConfig.paint_tin_height,
		"hob": ObjectMeshKitchenConfig.hotplate_plate_height,
		"pan": ObjectMeshKitchenConfig.hotplate_pan_height,
		"pot": ObjectMeshStockItemConfig.pot_height,
		"sandbag": ObjectMeshStockItemConfig.sandbag_height,
		"hat": (
			ObjectMeshStockItemConfig.hat_brim_height + ObjectMeshStockItemConfig.hat_crown_height
		),
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
		"paint_tin":
			_tin(kit, foot, high, colour)
		"hob":
			kit.box(MeshKit.volume(foot, 0.0, high), colour, colour.lightened(0.1))
		"pan":
			_pan(kit, foot, high, colour)
		"sandbag":
			_sandbag(kit, foot, high, colour)
		"hat":
			_hat(kit, foot, colour)
		_:
			_pot(kit, foot, high, colour, spec.opts.get("well"))


## The hot ring of the `hob`: a glowing disc on the left of its plate.
static func glow(spec: FurnitureSpec, foot: Rect2, high: float) -> Mesh:
	var kit := spec.kit()
	var radius := maxf(3.0, floorf(foot.size.y * 0.5) - 2.0)
	var at := foot.position + Vector2(radius + 2.0, foot.size.y * 0.5)
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


## A pair of shoes, toes toward the front: each a narrow heel with its dark opening, a vamp the
## sole's width and a rounded toe, so the toe reads wider than the heel (the painter's shoes).
static func _shoes(kit: MeshKit, foot: Rect2, high: float, colour: Color) -> void:
	var sole := (foot.size.x - 1.0) * 0.5
	var heel_depth := foot.size.y * 0.42
	var radius := minf(sole * 0.5, foot.size.y * 0.25)
	for i in 2:
		var at := foot.position + Vector2(i * (sole + 1.0), 0.0)
		var heel := Rect2(at + Vector2(sole * 0.15, 0.0), Vector2(sole * 0.7, heel_depth))
		kit.box(MeshKit.volume(heel, 0.0, high), colour, colour.lightened(0.08))
		var mouth := Rect2(heel.position + Vector2(0.6, 0.6), heel.size - Vector2(1.2, 1.2))
		kit.box(MeshKit.volume(mouth, high, 0.2), colour.darkened(0.55))
		var vamp := Rect2(
			at + Vector2(0.0, heel_depth * 0.9),
			Vector2(sole, foot.size.y - heel_depth * 0.9 - radius),
		)
		kit.box(MeshKit.volume(vamp, 0.0, high * 0.8), colour, colour.lightened(0.14))
		var toe := at + Vector2(sole * 0.5, foot.size.y - radius)
		kit.cylinder(
			Vector3(toe.x, 0.0, toe.y), radius, high * 0.8, colour, colour.lightened(0.14)
		)


## A pan: a round dish and its handle reaching out to the right, both inside the footprint.
static func _pan(kit: MeshKit, foot: Rect2, high: float, colour: Color) -> void:
	var radius := foot.size.y * 0.5
	var mid := foot.position + Vector2(radius, radius)
	kit.cylinder(Vector3(mid.x, 0.0, mid.y), radius, high, colour, colour.lightened(0.15))
	var grip := Rect2(mid + Vector2(radius, -1.0), Vector2(PAN_HANDLE, 2.0))
	kit.box(MeshKit.volume(grip, high - 1.5, 1.5), colour)


## A sandbag: a filled sack, its sides a shade darker than its top.
static func _sandbag(kit: MeshKit, foot: Rect2, high: float, colour: Color) -> void:
	kit.box(MeshKit.volume(foot, 0.0, high), MeshKit.tone(colour, &"dark"), colour)


## A hat: a brim disc a shade darker than its crown, the crown a smaller disc on it (the coat
## rack's old hat: a brim of the footprint's radius, a crown of 0.64 of it).
static func _hat(kit: MeshKit, foot: Rect2, colour: Color) -> void:
	var radius := minf(foot.size.x, foot.size.y) * 0.5
	var mid := foot.get_center()
	var brim := ObjectMeshStockItemConfig.hat_brim_height
	kit.cylinder(Vector3(mid.x, 0.0, mid.y), radius, brim, colour.darkened(0.2))
	kit.cylinder(
		Vector3(mid.x, brim, mid.y),
		maxf(1.0, radius * 0.64),
		ObjectMeshStockItemConfig.hat_crown_height,
		colour,
	)


## A paint tin: a round can with its lid on, a darker band round the middle for the label.
static func _tin(kit: MeshKit, foot: Rect2, high: float, colour: Color) -> void:
	var radius := minf(foot.size.x, foot.size.y) * 0.5
	var mid := foot.get_center()
	kit.cylinder(Vector3(mid.x, 0.0, mid.y), radius, high, colour, colour.lightened(0.12))
	kit.cylinder(
		Vector3(mid.x, high * 0.3, mid.y), radius + 0.2, high * 0.4, colour.darkened(0.3)
	)


## A pot: a tall round body and two handles; one with a `well` (the noodle bar's) shows what it
## holds as it was drawn: a dark rim, a ring of its steel and the broth inside.
static func _pot(
	kit: MeshKit,
	foot: Rect2,
	high: float,
	colour: Color,
	well: Variant = null,
) -> void:
	var radius := minf(foot.size.x, foot.size.y) * 0.5
	var mid := foot.get_center()
	if well is Color:
		var step := POT_STEP
		kit.cylinder(Vector3(mid.x, 0.0, mid.y), radius, high - 3.0 * step, colour)
		var at := Vector3(mid.x, high - 3.0 * step, mid.y)
		kit.cylinder(at, radius, step, colour.darkened(0.4))
		kit.cylinder(at + Vector3(0.0, step, 0.0), radius * 0.75, step, colour.lightened(0.12))
		kit.cylinder(
			at + Vector3(0.0, 2.0 * step, 0.0), radius * 0.5, step, (well as Color).darkened(0.2),
		)
	else:
		kit.cylinder(Vector3(mid.x, 0.0, mid.y), radius, high, colour, colour.lightened(0.12))
	for side: float in [-1.0, 1.0]:
		var grip := Rect2(mid + Vector2(side * radius - 0.8, -1.0), Vector2(1.6, 2.0))
		kit.box(MeshKit.volume(grip, high * 0.7, 1.5), colour.darkened(0.2))
