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


## A tool roll: a hammer, a wrench and a screwdriver side by side, each a slim bar.
static func _tools(kit: MeshKit, spec: FurnitureSpec, foot: Rect2, high: float) -> void:
	var lane := foot.size.y / 3.0
	var rows := [spec.color.darkened(0.3), spec.color, Color(0.9, 0.75, 0.2)]
	for k in 3:
		var bar := Rect2(
			foot.position + Vector2(0.0, lane * k + lane * 0.2), Vector2(foot.size.x, lane * 0.6)
		)
		kit.box(MeshKit.volume(bar, 0.0, high), rows[k])


## A vise: a jaw block, a pair of jaws and a screw handle out of its front.
static func _vise(kit: MeshKit, spec: FurnitureSpec, foot: Rect2, high: float) -> void:
	var body := Rect2(foot.position, Vector2(foot.size.x, foot.size.y * 0.7))
	kit.box(MeshKit.volume(body, 0.0, high * 0.6), spec.color)
	var jaw := Rect2(body.position + Vector2(1.0, 0.0), Vector2(body.size.x - 2.0, 2.0))
	kit.box(MeshKit.volume(jaw, high * 0.6, high * 0.4), spec.color.lightened(0.15))
	var screw := Rect2(
		Vector2(foot.get_center().x - 0.5, body.end.y), Vector2(1.0, foot.size.y * 0.3)
	)
	kit.box(MeshKit.volume(screw, high * 0.2, high * 0.2), spec.color.lightened(0.3))
