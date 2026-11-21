extends RefCounted
## Objects domain, the 3D shapes of the home's small items (`item_mesh.gd` hands a kind it does not
## know here; `docs/stacked-items.md` SI13): a keyboard (a slab with a key block), papers (two
## sheets), a clock (a case with its face), a vase (a body, a neck and flowers), a fruit bowl (a
## bowl heaped with fruit), a cutting board, a tool roll (a hammer, a wrench and a screwdriver laid
## together) and a bench vise (a jaw block with its screw). Each at the footprint and the painter's
## proportions of `item_home_painter.gd`, standing on its own origin (y 0).

const KINDS := [
	"keyboard", "papers", "clock", "vase", "fruit_bowl", "cutting_board", "tools", "vise",
]


## Whether `kind` is one of the home's items.
static func has(kind: String) -> bool:
	return kind in KINDS


## How tall `kind` stands (`ObjectMeshHomeItemConfig`), 0 for a kind not here.
static func height_of(kind: String) -> float:
	var heights := {
		"keyboard": ObjectMeshHomeItemConfig.keyboard_height,
		"papers": ObjectMeshHomeItemConfig.papers_height,
		"clock": ObjectMeshHomeItemConfig.clock_height,
		"vase": ObjectMeshHomeItemConfig.vase_height,
		"fruit_bowl": ObjectMeshHomeItemConfig.fruit_bowl_height,
		"cutting_board": ObjectMeshHomeItemConfig.cutting_board_height,
		"tools": ObjectMeshHomeItemConfig.tools_height,
		"vise": ObjectMeshHomeItemConfig.vise_height,
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
	var radius := minf(spec.size.x, spec.size.y) * 0.5
	match kind:
		"keyboard":
			_keyboard(kit, spec, foot, high)
		"papers":
			_papers(kit, spec, foot, high)
		"clock":
			_clock(kit, spec, radius, high)
		"vase":
			_vase(kit, spec, radius, high)
		"fruit_bowl":
			_fruit_bowl(kit, spec, radius, high)
		"cutting_board":
			kit.box(MeshKit.volume(foot, 0.0, high), spec.color, spec.color.lightened(0.06))
		"tools":
			_tools(kit, spec, foot, high)
		"vise":
			_vise(kit, spec, foot, high)


## A keyboard: a slab and a darker block of keys on it.
static func _keyboard(kit: MeshKit, spec: FurnitureSpec, foot: Rect2, high: float) -> void:
	kit.box(MeshKit.volume(foot, 0.0, high * 0.6), spec.color)
	kit.box(
		MeshKit.volume(foot.grow(-1.0), high * 0.6, high * 0.4),
		spec.color.darkened(0.22), spec.color.darkened(0.12),
	)


## Two sheets of paper, the top one nudged over the bottom.
static func _papers(kit: MeshKit, spec: FurnitureSpec, foot: Rect2, high: float) -> void:
	var low := Rect2(foot.position, foot.size - Vector2(2.0, 1.0))
	var over := Rect2(foot.position + Vector2(2.0, 1.0), foot.size - Vector2(2.0, 1.0))
	kit.box(MeshKit.volume(low, 0.0, high * 0.5), spec.color.darkened(0.06))
	kit.box(MeshKit.volume(over, high * 0.5, high * 0.5), spec.color, spec.color.lightened(0.05))


## A clock: a round case and a paler face on its top.
static func _clock(kit: MeshKit, spec: FurnitureSpec, radius: float, high: float) -> void:
	kit.cylinder(Vector3.ZERO, radius, high, spec.color)
	kit.cylinder(Vector3(0.0, high, 0.0), radius * 0.75, 0.1, Color(0.575, 0.533, 0.456))


## A vase: a round body, a neck and a few flowers over it.
static func _vase(kit: MeshKit, spec: FurnitureSpec, radius: float, high: float) -> void:
	kit.cylinder(Vector3.ZERO, radius * 0.75, high * 0.55, spec.color)
	kit.cylinder(
		Vector3(0.0, high * 0.55, 0.0),
		radius * 0.4,
		high * 0.2,
		spec.color.darkened(0.15),
	)
	var flowers: Array = ObjectArtDecorConfig.prop_colors["flowers"]
	for k in 3:
		var turn := TAU * float(k) / 3.0
		var bloom := radius * 0.3
		var at := Vector3(cos(turn) * radius * 0.4, high - bloom, sin(turn) * radius * 0.4)
		kit.sphere(at, bloom, flowers[k % flowers.size()])


## A bowl heaped with fruit.
static func _fruit_bowl(kit: MeshKit, spec: FurnitureSpec, radius: float, high: float) -> void:
	kit.cylinder(Vector3.ZERO, radius * 0.5, high * 0.3, spec.color)
	kit.cylinder(Vector3(0.0, high * 0.3, 0.0), radius, high * 0.4, spec.color)
	var fruit: Array = ObjectArtDecorConfig.prop_colors["fruit"]
	for k in 4:
		var turn := TAU * float(k) / 4.0
		var round_fruit := radius * 0.32
		var at := Vector3(cos(turn) * radius * 0.45, high - round_fruit, sin(turn) * radius * 0.45)
		kit.sphere(at, round_fruit, fruit[k % fruit.size()])


## The tools: a hammer, a wrench and a screwdriver laid apart, each slim, as the old prop drew
## them (`props.gd`): the hammer's wooden handle and iron head, the wrench's bar and ring, the
## screwdriver's yellow handle and bright shaft.
static func _tools(kit: MeshKit, _spec: FurnitureSpec, foot: Rect2, high: float) -> void:
	var palette: Dictionary = ObjectArtDecorConfig.prop_colors
	var metal: Color = palette["metal"]
	var o := foot.get_center()
	kit.box(
		MeshKit.volume(Rect2(o.x - 6.0, o.y - 2.5, 9.0, 1.0), 0.0, high * 0.4),
		palette["wood_light"],
	)
	kit.box(
		MeshKit.volume(Rect2(o.x + 2.0, o.y - 4.5, 2.0, 5.0), 0.0, high), metal.darkened(0.3)
	)
	kit.box(MeshKit.volume(Rect2(o.x - 5.0, o.y + 2.5, 8.0, 1.0), 0.0, high * 0.4), metal)
	kit.cylinder(Vector3(o.x + 4.0, 0.0, o.y + 3.0), 2.0, high * 0.5, metal)
	kit.box(MeshKit.volume(Rect2(o.x + 5.0, o.y - 5.0, 2.0, 4.0), 0.0, high), palette["accent"])
	kit.box(
		MeshKit.volume(Rect2(o.x + 5.5, o.y - 1.0, 1.0, 5.0), 0.0, high * 0.4),
		metal.lightened(0.1),
	)


## A bench vise as the old prop drew it: a small stand with a bright jaw across it, and its screw
## handle out of the front (a stem and a cross bar).
static func _vise(kit: MeshKit, spec: FurnitureSpec, foot: Rect2, high: float) -> void:
	var metal: Color = ObjectArtDecorConfig.prop_colors["metal"]
	var o := foot.get_center()
	var stand := Rect2(o.x - 5.0, o.y - 6.0, 10.0, 8.0)
	kit.box(MeshKit.volume(stand, 0.0, high * 0.6), spec.color, spec.color.lightened(0.05))
	var jaw := Rect2(o.x - 4.0, o.y - 2.5, 8.0, 1.0)
	kit.box(MeshKit.volume(jaw, high * 0.6, high * 0.4), metal.lightened(0.15))
	kit.box(MeshKit.volume(Rect2(o.x - 0.5, o.y + 2.0, 1.0, 3.0), 0.0, high * 0.3), metal)
	kit.box(MeshKit.volume(Rect2(o.x - 3.0, o.y + 4.5, 6.0, 1.0), 0.0, high * 0.3), metal)
