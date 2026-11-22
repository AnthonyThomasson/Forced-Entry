extends RefCounted
## Objects domain, the 3D mesh of the tower shop's pieces (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and `shop_painter.gd`'s
## proportions, in grimy steel, by `kind`. `counter` is a steel counter with a rust-orange lip
## (its till, jar and packs are items: `ShopItemsCatalog`); `aisle` is two shelf runs back to back,
## boards in tiers, a steel lip along each outer edge; `fridge` is a tall drinks fridge and `snack`
## a snack machine with a keypad, both with a bay behind a glass front: the three are hollow
## (`ShopHollow`: a box per part, the glass a collider and not drawn) and their stock is free items
## on the boards (`ShopStock`). What is lit (a fridge's front pane, a machine's back wall) is a glow
## node of the piece's rig, no real light (the Lighting domain's).

const OPTIONS := ["kind", "top_color", "accent_color", "glass_color", "fridge_glow", "height"]
## How far a feature stands proud of the face it is laid on.
const PROUD := 0.6


## The node a shop `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"shop", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	if kind_of(spec) in ["fridge", "snack"]:
		var glow := FurnitureMesh.fetch_glow(
			"shop", spec, tuning, func() -> Mesh: return _glass(spec)
		)
		rig.add_glow(glow, _glow_colour(spec), ObjectMeshStateConfig.window_strength)
	return rig


## The kind the piece is: its `art_opts.kind`, else the painter's.
static func kind_of(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("kind", "counter"))


## How tall the piece stands: its `art_opts.height`, else its kind's.
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	match kind_of(spec):
		"aisle":
			return ObjectMeshShopConfig.aisle_height
		"fridge":
			return ObjectMeshShopConfig.fridge_height
		"snack":
			return ObjectMeshShopConfig.snack_height
	return ObjectMeshShopConfig.counter_height


## The painter's option `name` (a colour) of the piece, else its holder default.
static func _colour(spec: FurnitureSpec, name: String) -> Color:
	var defaults := {
		"top_color": ObjectArtShopConfig.shop_top_color,
		"accent_color": ObjectArtShopConfig.shop_accent_color,
		"glass_color": ObjectArtShopConfig.shop_glass_color,
		"fridge_glow": ObjectArtShopConfig.shop_fridge_glow,
	}
	return spec.opts.get(name, defaults[name])


## The colour the glowing part glows in: the snack machine's glass, the fridge's.
static func _glow_colour(spec: FurnitureSpec) -> Color:
	return _colour(spec, "fridge_glow" if kind_of(spec) == "fridge" else "glass_color")


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS),
		"top": _colour(spec, "top_color"),
		"accent": _colour(spec, "accent_color"),
		"glass": _colour(spec, "glass_color"),
		"glow": _colour(spec, "fridge_glow"),
		"height": height_of(spec),
		"tiers": ObjectMeshShopConfig.aisle_tiers,
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	if ShopHollow.has(spec):
		_hollow(spec, kit)
	else:
		_counter(spec, kit)
	return kit.build()


## The counter: the steel body and top and the rust lip.
static func _counter(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	var top := _colour(spec, "top_color")
	kit.box(MeshKit.volume(spec.area(0, 0, w, d), 0.0, height), spec.color, top)
	kit.box(
		MeshKit.volume(
			spec.area(3, d - 7.0, w - 6.0, 2),
			height,
			1.0,
		), _colour(spec, "accent_color")
	)


## What glows: a fridge's lit pale-blue pane, a thin panel standing just behind the glass front
## (the old front pane: a lit surface facing the room reads bright where one at the back of the bay
## sits in the shade of its own roof; the stock stands behind it), and a snack machine's bay's back
## wall, so its stock stands against a glow (the glass front is a collider, not drawn).
static func _glass(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	var bay: Dictionary = ShopHollow.bays(spec)[0]
	var area: Rect2 = bay["area"]
	var tops: Array[float] = bay["tops"]
	if kind_of(spec) == "fridge":
		var low := ShopHollow.KICK
		kit.box(
			MeshKit.volume(
				spec.area(area.position.x, area.end.y - PROUD, area.size.x, PROUD),
				low,
				height_of(spec) - ShopHollow.FRAME - low,
			),
			_colour(spec, "fridge_glow"),
		)
		return kit.build()
	var high: float = tops[-1] + float(bay["room"]) - tops[0]
	kit.box(
		MeshKit.volume(
			spec.area(area.position.x, ShopHollow.WALL, area.size.x, PROUD), tops[0], high
		),
		_colour(spec, "glass_color"),
	)
	return kit.build()


## The hollow pieces (`ShopHollow`): a box per part but the glass, steel with the lighter top, and
## on a fridge the vents on its roof and the frame of its glass, on a snack machine the keypad.
static func _hollow(spec: FurnitureSpec, kit: MeshKit) -> void:
	var size := Vector2(maxf(spec.size.x, 1.0), maxf(spec.size.y, 1.0))
	var top := _colour(spec, "top_color")
	var h := height_of(spec)
	for part: Dictionary in ShopHollow.parts(spec):
		if part.get("material", "") == "glass":
			continue
		var rect: Rect2 = part["rect"]
		var area := spec.area(
			rect.position.x * size.x, rect.position.y * size.y, rect.size.x * size.x,
			rect.size.y * size.y,
		)
		var lid: bool = float(part["top"]) >= h - 0.01
		kit.box(
			MeshKit.volume(area, part["base"], part["top"] - part["base"]), spec.color,
			top if lid else spec.color,
		)
	_details(spec, kit)


## What a fridge has on it besides its parts: the vents on its roof and the frame of its glass;
## a snack machine the keypad.
static func _details(spec: FurnitureSpec, kit: MeshKit) -> void:
	match kind_of(spec):
		"fridge":
			_trim(spec, kit)
		"snack":
			_keypad(spec, kit)


## A snack machine's keypad: a dark plate on its keypad column with six keys.
static func _keypad(spec: FurnitureSpec, kit: MeshKit) -> void:
	var pad := spec.size.x - ShopHollow.KEYPAD
	var d := spec.size.y
	var base := ShopHollow.SNACK_SILL + 12.0
	kit.box(
		MeshKit.volume(spec.area(pad + 2.0, d - PROUD, 7, PROUD), base, 10.0),
		Color(0.1, 0.1, 0.12),
	)
	for k in 6:
		kit.box(
			MeshKit.volume(
				spec.area(pad + 3.0 + (k % 2) * 3.0, d - PROUD, 2, PROUD),
				base + 1.0 + int(k / 2.0) * 3.5, 2.0,
			),
			Color(0.8, 0.8, 0.76),
		)


## A fridge's trim: the vents on its roof and the frame above and below its glass.
static func _trim(spec: FurnitureSpec, kit: MeshKit) -> void:
	var h := height_of(spec)
	var w := spec.size.x
	for k in range(6, int(w) - 6, 4):
		kit.box(MeshKit.volume(spec.area(k, 5, 2, 5), h, 0.4), spec.color.darkened(0.35))
	var front := spec.area(ShopHollow.WALL, spec.size.y - PROUD, w - 8.0, PROUD)
	for z: float in [ShopHollow.KICK, h - ShopHollow.FRAME - 0.8]:
		kit.box(MeshKit.volume(front, z, 0.8), spec.color.darkened(0.55))
