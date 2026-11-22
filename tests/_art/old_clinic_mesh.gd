extends RefCounted
## (An oracle: `clinic_mesh.gd` of commit 08f43a10, the old look #194 unbake-c keeps.
## Only tests read it (`old_shop_pieces.gd`); nothing in scenes/ does.)
## Objects domain, the 3D mesh of the ripperdoc's steel (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and `clinic_painter.gd`'s
## proportions, by `kind`. `tool_cart` is a steel cart on four legs with a lower shelf and a rimmed
## tray of scalpels, clamps and a syringe, and a small diagnostic screen on it (a glow node of the
## rig, in the piece's neon or the cheap screens' green); `cyberware_shelf` is an open steel shelf
## of tiers, each laid with the cyberware the painter strews along it (arms with a joint, eyes,
## chips with their pins and jars), in a fixed order per look.

const Decay = preload("res://scenes/objects/art/decay.gd")
const OPTIONS := ["kind", "neon", "height"]
## The legs of the cart, how thick a shelf board is and a tray tool lies.
const LEG := 3.0
const BOARD := 1.5
const TOOL := 0.8


## The node a clinic `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"clinic", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	if not _shelf(spec):
		var glow := FurnitureMesh.fetch_glow(
			"clinic", spec, tuning, func() -> Mesh: return _screen(spec)
		)
		rig.add_glow(glow, Decay.screen_color(spec.opts), ObjectMeshStateConfig.screen_strength)
	return rig


## Whether the piece is the cyberware shelf (`art_opts.kind`), else the tool cart.
static func _shelf(spec: FurnitureSpec) -> bool:
	return String(spec.opts.get("kind", "tool_cart")) == "cyberware_shelf"


## How tall the piece stands: its `art_opts.height`, else its kind's.
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	return ObjectMeshTechConfig.cyber_height if _shelf(spec) else ObjectMeshTechConfig.cart_height


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS),
		"height": height_of(spec),
		"rim": ObjectMeshTechConfig.cart_rim,
		"tiers": ObjectMeshTechConfig.cyber_tiers,
		"dark": ObjectArtTechConfig.tech_dark_color,
		"screen_colour": Decay.screen_color(spec.opts),
		"colours": [
			ObjectArtClinicConfig.clinic_tray_color,
			ObjectArtClinicConfig.clinic_chrome_color,
			ObjectArtClinicConfig.clinic_joint_color,
			ObjectArtClinicConfig.clinic_eye_color,
			ObjectArtClinicConfig.clinic_chip_color,
			ObjectArtClinicConfig.clinic_pin_color,
			ObjectArtClinicConfig.clinic_jar_color,
		],
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	if _shelf(spec):
		_cyberware(spec, kit)
	else:
		_cart(spec, kit)
	return kit.build()


## The cart: four legs, a lower shelf and the top board the tray is laid in.
static func _cart(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var floor_at := height_of(spec) - ObjectMeshTechConfig.cart_rim
	var steel := spec.color
	for x: float in [0.0, w - LEG]:
		for y: float in [0.0, d - LEG]:
			var leg := spec.area(x, y, LEG, LEG)
			kit.box(MeshKit.volume(leg, 0.0, floor_at), MeshKit.tone(steel, &"dark"))
	kit.box(MeshKit.volume(spec.area(0, 0, w, d), 7.0, BOARD), steel)
	kit.box(MeshKit.volume(spec.area(0, 0, w, d), floor_at - BOARD, BOARD), steel)
	_tray(spec, kit, floor_at)


## The tray on the cart: its floor, the rim round it, the scalpels and clamps in a row, the
## syringe and the screen's body.
static func _tray(spec: FurnitureSpec, kit: MeshKit, floor_at: float) -> void:
	var tray := Rect2(3, 3, spec.size.x - 6.0, spec.size.y - 6.0)
	var steel := spec.color
	var chrome := ObjectArtClinicConfig.clinic_chrome_color
	var inner := spec.area(tray.position.x, tray.position.y, tray.size.x, tray.size.y)
	kit.box(MeshKit.volume(inner, floor_at, 0.2), ObjectArtClinicConfig.clinic_tray_color)
	for strip in FurnitureSpec.ring(Rect2(0, 0, spec.size.x, spec.size.y), tray):
		var rect := spec.area(strip.position.x, strip.position.y, strip.size.x, strip.size.y)
		var rim := ObjectMeshTechConfig.cart_rim
		kit.box(MeshKit.volume(rect, floor_at, rim), steel, MeshKit.tone(steel, &"light"))
	for i in 4:
		var x := tray.position.x + 3.0 + i * 4.0
		var tool := spec.area(x, tray.position.y + 2.0, 1.2, minf(7.0, tray.size.y - 5.0))
		kit.box(MeshKit.volume(tool, floor_at, TOOL), chrome)
	var syringe := spec.area(tray.position.x + 2.0, tray.end.y - 3.0, 10, 1.2)
	kit.box(MeshKit.volume(syringe, floor_at, TOOL), chrome.lightened(0.3))
	var screen := spec.area(tray.end.x - 12.0, tray.position.y + 2.0, 9, 6)
	kit.box(MeshKit.volume(screen, floor_at, 3.0), ObjectArtTechConfig.tech_dark_color)


## The cart's screen: a plate on top of its body.
static func _screen(spec: FurnitureSpec) -> Mesh:
	var tray := Rect2(3, 3, spec.size.x - 6.0, spec.size.y - 6.0)
	var top := height_of(spec) - ObjectMeshTechConfig.cart_rim + 3.0
	var kit := spec.kit()
	kit.box(
		MeshKit.volume(
			spec.area(tray.end.x - 11.0, tray.position.y + 3.0, 7, 4), top, 0.3
		),
		Decay.screen_color(spec.opts),
	)
	return kit.build()


## The shelf: four posts, the boards of every tier and the cyberware laid along them.
static func _cyberware(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	var steel := spec.color
	var tiers := maxi(1, ObjectMeshTechConfig.cyber_tiers)
	for x: float in [0.0, w - 3.0]:
		for y: float in [0.0, d - 3.0]:
			kit.box(
				MeshKit.volume(spec.area(x, y, 3, 3), 0.0, height),
				MeshKit.tone(steel, &"dark"),
				steel,
			)
	var rng := spec.rng("shelf", OPTIONS)
	for tier in tiers:
		var at := 2.0 + float(tier) * (height - 2.0 - BOARD * 2.0) / float(tiers)
		kit.box(
			MeshKit.volume(spec.area(0, 0, w, d), at, BOARD),
			steel,
			MeshKit.tone(steel, &"light"),
		)
		_row(spec, kit, rng, at + BOARD)
	kit.box(
		MeshKit.volume(spec.area(0, 0, w, d), height - BOARD, BOARD),
		steel,
		MeshKit.tone(steel, &"light"),
	)


## One tier's cyberware, laid left to right on the board at height `at`: the painter's pick of an
## arm, an eye, a chip or a jar, each as wide as it is.
static func _row(spec: FurnitureSpec, kit: MeshKit, rng: RandomNumberGenerator, at: float) -> void:
	var well := Rect2(3, 3, spec.size.x - 6.0, spec.size.y - 6.0)
	var x := well.position.x + 2.0
	while x < well.end.x - 6.0:
		var pick := rng.randi_range(0, 3)
		match pick:
			0:
				_arm(spec, kit, x, well, at)
			1:
				_eye(spec, kit, Vector2(x + 3.0, well.position.y + _drop(rng, well, 4.0, 5.0)), at)
			2:
				_chip(spec, kit, Vector2(x, well.position.y + _drop(rng, well, 2.0, 8.0)), at)
			_:
				_jar(spec, kit, Vector2(x + 3.0, well.position.y + 5.0), at)
		x += 5.0 if pick == 0 else 8.0


## How far down the well a piece the painter places by a random pick lies: between `low` and the
## well's depth less `back`.
static func _drop(rng: RandomNumberGenerator, well: Rect2, low: float, back: float) -> float:
	return rng.randf_range(low, maxf(low, well.size.y - back))


## An arm along the shelf's depth at column `x`: a chrome bar with its joint half way.
static func _arm(spec: FurnitureSpec, kit: MeshKit, x: float, well: Rect2, at: float) -> void:
	var bar := spec.area(x, well.position.y + 1.0, 1.6, well.size.y - 4.0)
	kit.box(MeshKit.volume(bar, at, 3.0), ObjectArtClinicConfig.clinic_chrome_color)
	var mid := well.position.y + well.size.y / 2.0
	var joint := spec.area(x - 0.5, mid - 1.5, 2.6, 3)
	kit.box(MeshKit.volume(joint, at, 4.0), ObjectArtClinicConfig.clinic_joint_color)


## An eye: a pale ball with its dark pupil toward the front, centred at `from` (art px).
static func _eye(spec: FurnitureSpec, kit: MeshKit, from: Vector2, at: float) -> void:
	var centre := from - spec.half()
	var ball := Vector3(centre.x, at + 3.0, centre.y)
	kit.sphere(ball, 3.0, ObjectArtClinicConfig.clinic_eye_color)
	kit.sphere(ball + Vector3(0.0, 0.0, 2.2), 1.2, ObjectArtClinicConfig.clinic_joint_color)


## A chip with its pins, its corner at `from` (art px).
static func _chip(spec: FurnitureSpec, kit: MeshKit, from: Vector2, at: float) -> void:
	var body := spec.area(from.x, from.y, 6, 5)
	kit.box(MeshKit.volume(body, at, 1.2), ObjectArtClinicConfig.clinic_chip_color)
	for k in range(0, 6, 2):
		for y: float in [from.y - 1.0, from.y + 5.0]:
			var pin := spec.area(from.x + k, y, 1, 1)
			kit.box(MeshKit.volume(pin, at, 0.6), ObjectArtClinicConfig.clinic_pin_color)


## A jar centred at `from` (art px).
static func _jar(spec: FurnitureSpec, kit: MeshKit, from: Vector2, at: float) -> void:
	var centre := from - spec.half()
	kit.cylinder(Vector3(centre.x, at, centre.y), 3.0, 6.0, ObjectArtClinicConfig.clinic_jar_color)
