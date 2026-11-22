extends RefCounted
## Objects domain, the 3D mesh of the tower shop's pieces (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and `shop_painter.gd`'s
## proportions, in grimy steel, by `kind`. `counter` is a steel counter with a rust-orange lip
## (its till, jar and packs are items: `ShopItemsCatalog`); `aisle` is two shelf runs back to back,
## boards in tiers, a steel lip along each outer edge; `fridge` is a tall drinks fridge and `snack`
## a snack machine with a keypad, both with a bay behind a glass front: the three are hollow
## (`ShopHollow`: a box per part, the glass a collider and not drawn) and their stock is free items
## on the boards (`ShopStock`). What is lit (the lit front of a fridge or a machine, with a window
## cut for each bottle or pack) is a glow node of the piece's rig, no real light (the Lighting
## domain's).

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
	if kind_of(spec) == "snack":
		for colour in _pack_colours(spec):
			var faces := FurnitureMesh.fetch_glow(
				"shop_pack_%s" % colour.to_html(), spec, tuning,
				func() -> Mesh: return _pack_faces(spec, colour)
			)
			rig.add_glow(faces, colour, ObjectMeshStateConfig.window_strength)
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
		"windows": ShopStock.windows(spec),
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


## What glows: the lit front of a fridge (pale blue) or a snack machine (its glass colour), a thin
## panel just inside the glass with a window cut for each bottle or pack (`ShopStock.windows`), so
## the free stock stands behind it and shows against the glow round it, as the old front's bottles
## stood against its pane. Nothing is drawn where the glass is: a clear pane has no mesh.
static func _glass(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	var area: Rect2 = ShopHollow.bays(spec)[0]["area"]
	var low := ShopHollow.KICK
	var high := height_of(spec) - ShopHollow.FRAME
	if kind_of(spec) == "snack":
		low = ShopHollow.SNACK_SILL
		high = low + ShopHollow.SNACK_WINDOW
	var front := _pane_y(spec, area)
	var windows := ShopStock.windows(spec)
	var xs: Array[float] = [area.position.x, area.end.x]
	for window in windows:
		xs.append_array([window.position.x, window.end.x])
	xs.sort()
	for k in xs.size() - 1:
		var from := clampf(xs[k], area.position.x, area.end.x)
		var to := clampf(xs[k + 1], area.position.x, area.end.x)
		if to - from < 0.01:
			continue
		for span in _free_spans(windows, from, to, low, high):
			kit.box(
				MeshKit.volume(
					spec.area(from, front, to - from, PROUD), span.x, span.y - span.x
				),
				_glow_colour(spec),
			)
	return kit.build()


## The colours of the packs a snack machine holds, each once.
static func _pack_colours(spec: FurnitureSpec) -> Array[Color]:
	var out: Array[Color] = []
	for face: Dictionary in ShopStock.faces(spec):
		if not out.has(face["color"]):
			out.append(face["color"])
	return out


## The packs of one `colour` as they show in the machine's lit window: each pack's face a glow tile
## of its own colour in its window (the packs themselves stand dark in the shade of the roof, so
## without it the window would show them black against the pane).
static func _pack_faces(spec: FurnitureSpec, colour: Color) -> Mesh:
	var kit := spec.kit()
	var y := _pane_y(spec, ShopHollow.bays(spec)[0]["area"])
	for face: Dictionary in ShopStock.faces(spec):
		if face["color"] == colour:
			var window: Rect2 = face["window"]
			kit.box(
				MeshKit.volume(
					spec.area(window.position.x, y, window.size.x, PROUD), window.position.y,
					window.size.y
				),
				colour,
			)
	return kit.build()


## Where the lit pane of `spec` stands (px from the back, in the bay `area`'s frame): a fridge's
## just inside its glass, a snack machine's flush with its face, in the light of the room as the old
## strip was, not in the shade of the band above.
static func _pane_y(spec: FurnitureSpec, area: Rect2) -> float:
	if kind_of(spec) == "snack":
		return area.end.y + ShopHollow.GLASS - PROUD
	return area.end.y - PROUD


## The heights, `Vector2(from, to)`, between `low` and `high` that no window covers across the
## width `from` to `to`.
static func _free_spans(
	windows: Array[Rect2], from: float, to: float, low: float, high: float
) -> Array[Vector2]:
	var blocked: Array[Vector2] = []
	for window in windows:
		if window.position.x <= from + 0.01 and window.end.x >= to - 0.01:
			blocked.append(Vector2(window.position.y, window.end.y))
	blocked.sort()
	var out: Array[Vector2] = []
	var at := low
	for span in blocked:
		if span.x > at:
			out.append(Vector2(at, minf(span.x, high)))
		at = maxf(at, span.y)
	if at < high:
		out.append(Vector2(at, high))
	return out


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
