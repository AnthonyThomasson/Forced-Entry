extends RefCounted
## Objects domain, the 3D shapes of the small items the shops and special rooms give up
## (`item_mesh.gd` hands a kind it does not know here; `docs/stacked-items.md` SI16): a till (a
## body, four keys and a lit screen that is a glow node of its rig), a jar, a pack, a row of
## instruments (four blades) and a syringe (a barrel). Each at the footprint and the painter's
## proportions of `item_shop_painter.gd`, standing on its own origin (y 0).

const ItemShopPainter = preload("res://scenes/objects/art/item_shop_painter.gd")
const Decay = preload("res://scenes/objects/art/decay.gd")
const KINDS := [
	"till", "screen", "jar", "pack", "instruments", "syringe", "bottles", "snacks", "cyber_arm",
	"cyber_eye", "cyber_chip", "cyber_jar",
]


## How tall `kind` stands (`ObjectMeshShopItemConfig`), 0 for a kind not here.
static func height_of(kind: String) -> float:
	var heights := {
		"till": ObjectMeshShopItemConfig.till_height,
		"screen": ObjectMeshShopItemConfig.screen_height,
		"jar": ObjectMeshShopItemConfig.jar_height,
		"pack": ObjectMeshShopItemConfig.pack_height,
		"instruments": ObjectMeshShopItemConfig.instruments_height,
		"syringe": ObjectMeshShopItemConfig.syringe_height,
		"bottles": ObjectMeshShopItemConfig.bottles_height,
		"snacks": ObjectMeshShopItemConfig.snacks_height,
		"cyber_arm": ObjectMeshShopItemConfig.cyber_arm_height,
		"cyber_eye": ObjectMeshShopItemConfig.cyber_eye_height,
		"cyber_chip": ObjectMeshShopItemConfig.cyber_chip_height,
		"cyber_jar": ObjectMeshShopItemConfig.cyber_jar_height,
	}
	return float(heights.get(kind, 0.0))


## Build `kind` into `kit` over the footprint `foot` (the painter's frame), `high` tall.
static func shape(
	kit: MeshKit,
	spec: FurnitureSpec,
	kind: String,
	foot: Rect2,
	high: float,
) -> void:
	var chrome := ObjectArtClinicConfig.clinic_chrome_color
	match kind:
		"till":
			kit.box(MeshKit.volume(foot, 0.0, high - 0.8), spec.color)
			for k in 4:
				var key := Rect2(foot.position + Vector2(4.0 + k * 5.0, 10.0), Vector2(3.0, 3.0))
				kit.box(MeshKit.volume(key, high - 0.8, 0.8), Color(0.78, 0.78, 0.74))
		"screen":
			kit.box(MeshKit.volume(foot, 0.0, high), spec.color)
		"jar", "pack":
			kit.box(MeshKit.volume(foot, 0.0, high), spec.color, spec.color.lightened(0.05))
		"bottles", "snacks":
			_run(kit, spec, kind, foot, high)
		"cyber_arm", "cyber_eye", "cyber_chip", "cyber_jar":
			_cyberware(kit, spec, kind, foot, high)
		"instruments":
			for i in 4:
				var blade := Rect2(foot.position + Vector2(i * 4.0, 0.0), Vector2(1.2, 7.0))
				kit.box(MeshKit.volume(blade, 0.0, high), chrome)
		"syringe":
			var barrel := Rect2(
				foot.position + Vector2(0.0, foot.size.y * 0.5 - 0.6),
				Vector2(foot.size.x, 1.2),
			)
			kit.box(MeshKit.volume(barrel, 0.0, high), chrome.lightened(0.3))


## A piece of cyberware over the footprint `foot`: an arm (a chrome bar with its joint half way), an
## eye (a pale ball with its dark pupil toward the front), a chip (a body with its pins) or a jar.
static func _cyberware(
	kit: MeshKit, spec: FurnitureSpec, kind: String, foot: Rect2, high: float
) -> void:
	var joint := ObjectArtClinicConfig.clinic_joint_color
	var middle := foot.get_center()
	match kind:
		"cyber_arm":
			var bar := Rect2(foot.position + Vector2(0.5, 0.0), Vector2(1.6, foot.size.y))
			kit.box(MeshKit.volume(bar, 0.0, high - 1.0), spec.color)
			var knuckle := Rect2(middle + Vector2(-1.3, -1.5), Vector2(2.6, 3.0))
			kit.box(MeshKit.volume(knuckle, 0.0, high), joint)
		"cyber_eye":
			var round_ := Vector3(middle.x, 0.0, middle.y)  # a disc seen from above, as drawn
			kit.cylinder(round_, foot.size.x * 0.5, high * 0.75, spec.color)
			kit.cylinder(round_ + Vector3(0.0, high * 0.75, 0.0), 1.2, high * 0.25, joint)
		"cyber_chip":
			var body := Rect2(foot.position + Vector2(0.0, 1.0), Vector2(foot.size.x, 5.0))
			kit.box(MeshKit.volume(body, 0.0, high), spec.color)
			_pins(kit, foot, high)
		_:
			kit.cylinder(
				Vector3(middle.x, 0.0, middle.y), minf(foot.size.x, foot.size.y) * 0.5, high,
				spec.color,
			)


## The pins of a chip over `foot`: one at every second pixel along its two long edges.
static func _pins(kit: MeshKit, foot: Rect2, high: float) -> void:
	for k in range(0, 6, 2):
		for y: float in [0.0, 6.0]:
			var pin := Rect2(foot.position + Vector2(k, y), Vector2(1.0, 1.0))
			kit.box(MeshKit.volume(pin, 0.0, high), ObjectArtClinicConfig.clinic_pin_color)


## A run of bottles or packs side by side: one each of `spines` (an option `item_stock_mesh.gd` has
## `item_mesh.gd` read) (`[[x from the left, width, height, colour]]`; one of the footprint
## without), a bottle a body and a narrower neck, a pack a block.
static func _run(
	kit: MeshKit, spec: FurnitureSpec, kind: String, foot: Rect2, high: float
) -> void:
	var spines: Array = spec.opts.get("spines", [])
	if spines.is_empty():
		spines = [[0.0, foot.size.x, high, spec.color]]
	for spine: Array in spines:
		var area := Rect2(foot.position + Vector2(spine[0], 0.0), Vector2(spine[1], foot.size.y))
		var colour: Color = spine[3]
		if kind == "snacks":
			kit.box(MeshKit.volume(area, 0.0, spine[2]), colour, colour.lightened(0.08))
			continue
		var body: float = spine[2] * 0.7
		kit.box(MeshKit.volume(area, 0.0, body), colour)
		kit.box(
			MeshKit.volume(area.grow_individual(-1.5, -1.5, -1.5, -1.5), body, spine[2] - body),
			colour.darkened(0.2),
		)


## Whether `kind` has a lit part (a till's or a cart's screen).
static func glows(kind: String) -> bool:
	return kind == "till" or kind == "screen"


## The colour `spec`'s lit part glows in: a till's glass, a cart's screen the neon or the green.
static func glow_colour(spec: FurnitureSpec) -> Color:
	if String(spec.opts.get("kind", "")) == "screen":
		return Decay.screen_color(spec.opts)
	return ObjectArtShopConfig.shop_glass_color


## The lit plate on a body's top, over the footprint `foot`, `high` tall: a till's screen, or the
## pane of a cart's.
static func glow(spec: FurnitureSpec, foot: Rect2, high: float) -> Mesh:
	var kit := spec.kit()
	var screen := Rect2(foot.position + Vector2(3.0, 2.0), Vector2(foot.size.x - 6.0, 5.0))
	if String(spec.opts.get("kind", "")) == "screen":
		screen = foot.grow(-1.0)
		kit.box(MeshKit.volume(screen, high, 0.3), glow_colour(spec))
		return kit.build()
	kit.box(MeshKit.volume(screen, high - 0.8, 0.4), glow_colour(spec))
	return kit.build()
