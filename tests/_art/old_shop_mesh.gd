extends RefCounted
## (An oracle: `shop_mesh.gd` of commit 08f43a10, the old look #194 unbake-c keeps.
## Only tests read it (`old_shop_pieces.gd`); nothing in scenes/ does.)
## Objects domain, the 3D mesh of the tower shop's pieces (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and `shop_painter.gd`'s
## proportions, in grimy steel, by `kind`. `counter` is a steel counter with a rust-orange lip, a
## till (its screen glowing), a jar and a few packs; `aisle` is two shelf runs back to back, tiers
## of packs on each, a steel lip along each outer edge; `fridge` is a tall drinks fridge with a lit
## glass of drinks along its front; `snack` is a snack machine with a keypad and a lit window of
## packs. What is lit (the till's screen, the fridge's and the machine's glass) is a glow node of
## the piece's rig, no real light (the Lighting domain's); the drinks and packs stand proud in front
## of the glass.

const OPTIONS := ["kind", "top_color", "accent_color", "glass_color", "fridge_glow", "height"]
## How far a feature stands proud of the face it is laid on.
const PROUD := 0.6
## The old till's height (`ObjectMeshShopConfig.till_height`, gone with the till item).
const TILL_HEIGHT := 12.0


## The node a shop `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"shop", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	if _kind(spec) != "aisle":
		var glow := FurnitureMesh.fetch_glow(
			"shop", spec, tuning, func() -> Mesh: return _glass(spec)
		)
		var strength := (
			ObjectMeshStateConfig.screen_strength
			if _kind(spec) == "counter"
			else ObjectMeshStateConfig.window_strength
		)
		rig.add_glow(glow, _glow_colour(spec), strength)
	return rig


## The kind the piece is: its `art_opts.kind`, else the painter's.
static func _kind(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("kind", "counter"))


## How tall the piece stands: its `art_opts.height`, else its kind's.
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	match _kind(spec):
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


## The colour the glowing part glows in: the till's and the snack machine's glass, the fridge's.
static func _glow_colour(spec: FurnitureSpec) -> Color:
	return _colour(spec, "fridge_glow" if _kind(spec) == "fridge" else "glass_color")


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS),
		"top": _colour(spec, "top_color"),
		"accent": _colour(spec, "accent_color"),
		"glass": _colour(spec, "glass_color"),
		"glow": _colour(spec, "fridge_glow"),
		"height": height_of(spec),
		"till": TILL_HEIGHT,
		"tiers": ObjectMeshShopConfig.aisle_tiers,
		"packs": ObjectArtShopConfig.shop_packs,
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	match _kind(spec):
		"aisle":
			_aisle(spec, kit)
		"fridge":
			_fridge(spec, kit)
		"snack":
			_snack(spec, kit)
		_:
			_counter(spec, kit)
	return kit.build()


## The counter: the steel body and top, the rust lip, the till with its keys, a jar and packs.
static func _counter(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	var top := _colour(spec, "top_color")
	var packs: Array[Color] = ObjectArtShopConfig.shop_packs
	kit.box(MeshKit.volume(spec.area(0, 0, w, d), 0.0, height), spec.color, top)
	kit.box(
		MeshKit.volume(
			spec.area(3, d - 7.0, w - 6.0, 2),
			height,
			1.0,
		), _colour(spec, "accent_color")
	)
	var till := Rect2(8, 7, 26, 17)
	var till_top := height + TILL_HEIGHT
	kit.box(
		MeshKit.volume(
			spec.area(till.position.x, till.position.y, till.size.x, till.size.y),
			height,
			TILL_HEIGHT,
		),
		spec.color.darkened(0.3),
	)
	for k in 4:
		kit.box(
			MeshKit.volume(
				spec.area(till.position.x + 4.0 + k * 5.0, till.position.y + 10.0, 3, 3),
				till_top,
				0.8,
			),
			Color(0.78, 0.78, 0.74),
		)
	kit.box(MeshKit.volume(spec.area(42, 9, 12, 10), height, 9.0), Color(0.8, 0.78, 0.7))
	for k in 5:
		kit.box(
			MeshKit.volume(spec.area(62.0 + k * 7.0, 8.0 + (k % 2) * 6.0, 5, 5), height, 9.0),
			packs[k % packs.size()],
		)


## The till's screen and the tablet of glass over its top.
static func _glass(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	match _kind(spec):
		"counter":
			kit.box(
				MeshKit.volume(
					spec.area(11, 9, 20, 5), height + TILL_HEIGHT, 0.4
				),
				_colour(spec, "glass_color"),
			)
		"fridge":
			kit.box(
				MeshKit.volume(spec.area(3, d - PROUD, w - 6.0, PROUD), 8.0, height - 18.0),
				_colour(spec, "fridge_glow"),
			)
		_:
			kit.box(
				MeshKit.volume(spec.area(3, d - PROUD, w - 6.0, PROUD), 10.0, height * 0.4),
				_colour(spec, "glass_color"),
			)
	return kit.build()


## The aisle: two runs back to back, each with its end posts, a back panel on the face where they
## touch, tiers of boards and packs open to the outside, and only the lip along its outer edge on
## top, so the packs show from the aisle's sides and from above.
static func _aisle(spec: FurnitureSpec, kit: MeshKit) -> void:
	var depth := floorf(spec.size.y / 2.0)
	var steel := spec.color
	var top := _colour(spec, "top_color")
	var height := height_of(spec)
	var tiers := maxi(1, ObjectMeshShopConfig.aisle_tiers)
	var packs: Array[Color] = ObjectArtShopConfig.shop_packs
	for run in 2:
		var y0 := 0.0 if run == 0 else spec.size.y - depth
		for x: float in [0.0, spec.size.x - 2.0]:
			kit.box(
				MeshKit.volume(spec.area(x, y0, 2, depth), 0.0, height),
				MeshKit.tone(steel, &"dark"),
			)
		kit.box(
			MeshKit.volume(
				spec.area(2, y0 + (depth - 1.0 if run == 0 else 0.0), spec.size.x - 4.0, 1),
				0.0,
				height - 2.0,
			),
			MeshKit.tone(steel, &"dark"),
		)
		for tier in tiers:
			var at := 1.0 + float(tier) * (height - 4.0) / float(tiers)
			kit.box(MeshKit.volume(spec.area(2, y0, spec.size.x - 4.0, depth), at, 1.5), steel)
			for x in range(3, int(spec.size.x) - 6, 6):
				var pack := packs[(int(x / 6.0) + tier + int(y0)) % packs.size()].darkened(0.1)
				kit.box(MeshKit.volume(spec.area(x, y0 + 3.0, 5, 6), at + 1.5, 6.0), pack)
		var outer := y0 if run == 0 else spec.size.y - 2.0
		kit.box(MeshKit.volume(spec.area(1, outer, spec.size.x - 2.0, 2), height - 2.0, 2.4), top)


## The fridge: a steel body and top with vents, the glass framed in dark and the drinks proud of it.
static func _fridge(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	var top := _colour(spec, "top_color")
	var packs: Array[Color] = ObjectArtShopConfig.shop_packs
	kit.box(MeshKit.volume(spec.area(0, 0, w, d - PROUD), 0.0, height), spec.color, top)
	for k in range(6, int(w) - 6, 4):
		kit.box(MeshKit.volume(spec.area(k, 5, 2, 5), height, 0.4), spec.color.darkened(0.35))
	var frame := spec.color.darkened(0.55)
	kit.box(
		MeshKit.volume(spec.area(2, d - PROUD, w - 4.0, PROUD * 0.5), 6.0, height - 14.0),
		frame,
	)
	for k in range(0, int(w) - 9, 5):
		kit.box(
			MeshKit.volume(spec.area(4 + k, d - PROUD, 3, PROUD), 10.0, height - 26.0),
			packs[int(k / 5.0) % packs.size()],
		)


## The snack machine: a steel body, the keypad, a framed window with packs proud of its glass.
static func _snack(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	var packs: Array[Color] = ObjectArtShopConfig.shop_packs
	kit.box(
		MeshKit.volume(spec.area(0, 0, w, d - PROUD), 0.0, height),
		spec.color,
		_colour(spec, "top_color"),
	)
	kit.box(
		MeshKit.volume(spec.area(w - 12.0, d - PROUD, 7, PROUD), height * 0.55, 10.0),
		Color(0.1, 0.1, 0.12),
	)
	for k in 6:
		kit.box(
			MeshKit.volume(
				spec.area(w - 11.0 + (k % 2) * 3.0, d - PROUD, 2, PROUD),
				height * 0.55 + 1.0 + int(k / 2.0) * 3.0,
				2.0,
			),
			Color(0.8, 0.8, 0.76),
		)
	kit.box(
		MeshKit.volume(spec.area(2, d - PROUD, w - 4.0, PROUD * 0.5), 8.0, height * 0.4 + 4.0),
		spec.color.darkened(0.5),
	)
	for row in 2:
		for k in range(0, int(w) - 9, 4):
			kit.box(
				MeshKit.volume(spec.area(4 + k, d - PROUD, 3, PROUD), 12.0 + row * 12.0, 8.0),
				packs[(int(k / 4.0) + row) % packs.size()],
			)
