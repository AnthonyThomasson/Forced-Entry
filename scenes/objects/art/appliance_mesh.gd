extends RefCounted
## Objects domain, the 3D mesh of an appliance (the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): at the piece's own footprint, a box in the piece's colour whose top and
## front show what it is, by `panel` (`appliance_painter.gd`): a stove's four burners and knobs, a
## fridge's two doors and handles, a microwave's window and display, a washer's or dryer's round
## door, or a TV, an old CRT: a housing with a tapered back and a screen on its front. Each stands
## as tall as its panel (`ObjectMeshKitchenConfig.appliance_heights`; a small fridge is a mini
## fridge). The parts that give light (a TV's screen, a microwave's or washer's display) are a glow
## node of the piece's rig, in the cheap screens' green or the piece's neon.

const Decay = preload("res://scenes/objects/art/decay.gd")
const OPTIONS := ["panel", "neon", "height"]


## The node an appliance `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"appliance", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	if _glows(spec):
		var glow := FurnitureMesh.fetch_glow(
			"appliance", spec, tuning, func() -> Mesh: return _glow(spec)
		)
		rig.add_glow(glow, Decay.screen_color(spec.opts), ObjectMeshStateConfig.screen_strength)
	return rig


## The panel the piece wears: its `art_opts.panel`, else the painter's.
static func panel_of(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("panel", ObjectArtKitchenBathConfig.appliance_panel))


## Whether the panel has a part that gives light.
static func _glows(spec: FurnitureSpec) -> bool:
	return ["tv", "microwave", "washer", "dryer"].has(panel_of(spec))


## How tall an appliance of `spec` stands: its `art_opts.height`, else its panel's, a small fridge a
## mini fridge.
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	var panel := panel_of(spec)
	if panel == "fridge" and spec.size.x * spec.size.y <= ObjectMeshKitchenConfig.fridge_mini_area:
		return ObjectMeshKitchenConfig.fridge_mini_height
	return float(ObjectMeshKitchenConfig.appliance_heights.get(panel, 38.0))


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"panel": panel_of(spec),
		"neon": String(spec.opts.get("neon", "")),
		"height": height_of(spec),
		"proud": ObjectMeshKitchenConfig.appliance_proud,
		"metal": ObjectArtKitchenBathConfig.appliance_metal_color,
		"glass": ObjectArtKitchenBathConfig.appliance_glass_color,
		"crt": ObjectArtKitchenBathConfig.appliance_crt_color,
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	match panel_of(spec):
		"tv":
			_crt(spec, kit)
		"burners":
			_stove(spec, kit)
		"fridge":
			_fridge(spec, kit)
		"microwave":
			_boxed(spec, kit, ObjectMeshKitchenConfig.appliance_proud)
			_window(spec, kit)
		"washer", "dryer":
			_boxed(spec, kit, ObjectMeshKitchenConfig.appliance_proud)
			_drum(spec, kit)
		_:
			_boxed(spec, kit, 0.0)
	return kit.build()


## The body: the footprint less `proud` at the front, the piece's colour, a lighter top.
static func _boxed(spec: FurnitureSpec, kit: MeshKit, proud: float) -> void:
	var base := spec.color
	kit.box(
		MeshKit.volume(spec.area(0, 0, spec.size.x, spec.size.y - proud), 0.0, height_of(spec)),
		base,
		MeshKit.tone(base, &"light"),
	)


## A cooker: the boxed body with its burners on top.
static func _stove(spec: FurnitureSpec, kit: MeshKit) -> void:
	var proud := ObjectMeshKitchenConfig.appliance_proud
	_boxed(spec, kit, proud)
	var w := spec.size.x
	var d := spec.size.y
	var h := height_of(spec)
	var metal := ObjectArtKitchenBathConfig.appliance_metal_color
	var strip := maxf(4.0, roundf(d * 0.16))
	for i in 4:
		var kx := roundf((i + 0.5) * w / 4.0)
		kit.box(MeshKit.volume(spec.area(kx - 1.5, d - proud, 3, proud), h - 6.0, 3.0), metal)
	var area := Rect2(3, 3, w - 6, d - strip - 6)
	var radius := maxf(3.0, floorf(minf(area.size.x, area.size.y) / 4.0) - 1.0)
	for gy in 2:
		for gx in 2:
			var o := area.position + Vector2(
				(gx + 0.5) * area.size.x / 2.0,
				(gy + 0.5) * area.size.y / 2.0,
			)
			kit.cylinder(
				Vector3(o.x - w * 0.5, h, o.y - d * 0.5),
				radius,
				1.2,
				metal.darkened(0.45),
			)


## A fridge: a tall body with a door seam and a handle down its front.
static func _fridge(spec: FurnitureSpec, kit: MeshKit) -> void:
	var proud := ObjectMeshKitchenConfig.appliance_proud
	var w := spec.size.x
	var d := spec.size.y
	var h := height_of(spec)
	var base := spec.color
	_boxed(spec, kit, 2.0 * proud)
	var split := h * 0.7
	kit.box(MeshKit.volume(spec.area(1, d - 2.0 * proud, w - 2, proud), 1.0, split - 2.0), base)
	kit.box(
		MeshKit.volume(spec.area(1, d - 2.0 * proud, w - 2, proud), split + 1.0, h - split - 2.0),
		base,
	)
	var metal := ObjectArtKitchenBathConfig.appliance_metal_color
	kit.box(
		MeshKit.volume(spec.area(w * 0.8, d - proud, 2, proud), split - h * 0.4, h * 0.3),
		metal,
	)
	kit.box(MeshKit.volume(spec.area(w * 0.8, d - proud, 2, proud), split + 3.0, h * 0.14), metal)


## A microwave's dark window and keypad on its front.
static func _window(spec: FurnitureSpec, kit: MeshKit) -> void:
	var proud := ObjectMeshKitchenConfig.appliance_proud
	var w := spec.size.x
	var d := spec.size.y
	var h := height_of(spec)
	kit.box(
		MeshKit.volume(spec.area(w * 0.08, d - proud, w * 0.56, proud), h * 0.15, h * 0.7),
		ObjectArtKitchenBathConfig.appliance_glass_color,
	)
	kit.box(
		MeshKit.volume(spec.area(w * 0.7, d - proud, w * 0.22, proud), h * 0.15, h * 0.35),
		MeshKit.tone(spec.color, &"shadow"),
	)


## A washer's or dryer's round door on its front: glass for a washer, a solid dark door for a dryer.
static func _drum(spec: FurnitureSpec, kit: MeshKit) -> void:
	var proud := ObjectMeshKitchenConfig.appliance_proud
	var w := spec.size.x
	var d := spec.size.y
	var h := height_of(spec)
	var glass := ObjectArtKitchenBathConfig.appliance_glass_color
	var door := glass if panel_of(spec) == "washer" else MeshKit.tone(spec.color, &"dark")
	spec.level(
		kit,
		Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, h * 0.42, d * 0.5 - 2.0 * proud)),
	)
	kit.cylinder(Vector3.ZERO, minf(w, h) * 0.3, proud, MeshKit.tone(spec.color, &"shadow"), door)
	spec.level(kit)


## The glowing parts: a TV's screen, or the display of a microwave, a washer or a dryer.
static func _glow(spec: FurnitureSpec) -> Mesh:
	var proud := ObjectMeshKitchenConfig.appliance_proud
	var w := spec.size.x
	var d := spec.size.y
	var h := height_of(spec)
	var glass := ObjectArtKitchenBathConfig.appliance_glass_color
	var kit := spec.kit()
	match panel_of(spec):
		"tv":
			kit.box(
				MeshKit.volume(spec.area(w * 0.25, d - 0.8, w * 0.5, 0.8), h * 0.15, h * 0.7),
				glass,
			)
		"microwave":
			kit.box(
				MeshKit.volume(
					spec.area(w * 0.74, d - 2.0 * proud, w * 0.14, proud),
					h * 0.55,
					h * 0.1,
				),
				glass,
			)
		_:
			kit.box(
				MeshKit.volume(
					spec.area(w * 0.6, d - 2.0 * proud, w * 0.25, proud),
					h * 0.84,
					h * 0.08,
				),
				glass,
			)
	return kit.build()


## The CRT: a housing set back from the front edge, a tapered back and its screen on the front.
static func _crt(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var h := height_of(spec)
	var case_colour := ObjectArtKitchenBathConfig.appliance_crt_color
	kit.box(
		MeshKit.volume(spec.area(w * 0.18, d * 0.35, w * 0.64, d * 0.65 - 0.8), 0.0, h),
		case_colour,
		MeshKit.tone(case_colour, &"light"),
	)
	kit.box(
		MeshKit.volume(spec.area(w * 0.3, 1, w * 0.4, d * 0.35), 0.0, h * 0.7),
		MeshKit.tone(case_colour, &"dark"),
	)
