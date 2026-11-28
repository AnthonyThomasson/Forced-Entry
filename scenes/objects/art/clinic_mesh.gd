extends RefCounted
## Objects domain, the 3D mesh of the ripperdoc's steel (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and `clinic_painter.gd`'s
## proportions, by `kind`. `tool_cart` is a steel cart on four legs with a lower shelf and a rimmed
## tray (its instruments, syringe and diagnostic screen are items: `docs/stacked-items.md` SI16);
## `cyberware_shelf` is an open steel shelf
## of tiers, bare (`CyberwareShelf`: the arms, eyes, chips and jars it held are items).

const Decay = preload("res://scenes/objects/art/decay.gd")
const OPTIONS := ["kind", "neon", "height"]
## The legs of the cart and how thick a shelf board is.
const LEG := 3.0
const BOARD := 1.5


## The node a clinic `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"clinic", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
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
		"tray": ObjectArtClinicConfig.clinic_tray_color,
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


## The tray on the cart: its floor and the rim round it.
static func _tray(spec: FurnitureSpec, kit: MeshKit, floor_at: float) -> void:
	var tray := Rect2(3, 3, spec.size.x - 6.0, spec.size.y - 6.0)
	var steel := spec.color
	var inner := spec.area(tray.position.x, tray.position.y, tray.size.x, tray.size.y)
	kit.box(MeshKit.volume(inner, floor_at, 0.2), ObjectArtClinicConfig.clinic_tray_color)
	for strip in FurnitureSpec.ring(Rect2(0, 0, spec.size.x, spec.size.y), tray):
		var rect := spec.area(strip.position.x, strip.position.y, strip.size.x, strip.size.y)
		var rim := ObjectMeshTechConfig.cart_rim
		kit.box(MeshKit.volume(rect, floor_at, rim), steel, MeshKit.tone(steel, &"light"))


## The shelf: a box per part (`CyberwareShelf`), steel with the lighter top: four posts and the
## boards, the cyberware on them is items.
static func _cyberware(spec: FurnitureSpec, kit: MeshKit) -> void:
	var steel := spec.color
	var size := Vector2(maxf(spec.size.x, 1.0), maxf(spec.size.y, 1.0))
	for part: Dictionary in CyberwareShelf.parts(spec):
		var rect: Rect2 = part["rect"]
		var area := spec.area(
			rect.position.x * size.x, rect.position.y * size.y, rect.size.x * size.x,
			rect.size.y * size.y,
		)
		var post := rect.size.x * size.x < CyberwareShelf.POST + 0.01 and rect.size.y * size.y \
				< CyberwareShelf.POST + 0.01
		kit.box(
			MeshKit.volume(area, part["base"], part["top"] - part["base"]),
			MeshKit.tone(steel, &"dark") if post else steel,
			steel if post else MeshKit.tone(steel, &"light"),
		)
