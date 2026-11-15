extends RefCounted
## Objects domain, the 3D mesh of the security vestibule's steel (#193 phase 2; the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and
## `security_painter.gd`'s proportions, by `kind`. `barricade` is a heavy slab across the room, its
## back edge hazard-striped, propped by a stack of sandbags at both ends; `scanner` is one post of
## the scanner arch, tall, with a dark lens on top and the emitter strip down the face toward the
## other post glowing red (a glow node of the rig); `lockers` is a row of tall steel lockers, every
## other one a shade darker, each with vent slots and a number plate on its front.

const OPTIONS := ["kind", "height"]
## How far a feature stands proud of the face it is laid on.
const PROUD := 0.6


## The node a security `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"security", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	if _kind(spec) == "scanner":
		var glow := FurnitureMesh.fetch_glow(
			"security", spec, tuning, func() -> Mesh: return _emitter(spec)
		)
		rig.add_glow(
			glow,
			ObjectArtTechConfig.security_beam_color,
			ObjectMeshStateConfig.led_strength,
		)
	return rig


## The kind the piece is: its `art_opts.kind`, else the painter's.
static func _kind(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("kind", "barricade"))


## How tall the piece stands: its `art_opts.height`, else its kind's.
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	match _kind(spec):
		"scanner":
			return ObjectMeshTechConfig.scanner_height
		"lockers":
			return ObjectMeshTechConfig.locker_height
	return ObjectMeshTechConfig.barricade_height


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS),
		"height": height_of(spec),
		"bag": ObjectMeshTechConfig.bag_height,
		"dark": ObjectArtTechConfig.tech_dark_color,
		"hazard": ObjectArtTechConfig.security_hazard_color,
		"sandbag": ObjectArtTechConfig.security_sandbag_color,
		"number": ObjectArtTechConfig.security_number_color,
		"beam": ObjectArtTechConfig.security_beam_color,
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	match _kind(spec):
		"scanner":
			_scanner(spec, kit)
		"lockers":
			_lockers(spec, kit)
		_:
			_barricade(spec, kit)
	return kit.build()


## The slab with its hazard stripe along the back and a stack of sandbags at each end.
static func _barricade(spec: FurnitureSpec, kit: MeshKit) -> void:
	var edge := floorf(spec.size.x * 0.12)
	var slab := Rect2(edge, 2, spec.size.x - edge * 2.0, spec.size.y - 4.0)
	var height := height_of(spec)
	kit.box(
		MeshKit.volume(spec.within(slab), 0.0, height),
		spec.color,
		MeshKit.tone(spec.color, &"light"),
	)
	var x := slab.position.x + 2.0
	var k := 0
	while x < slab.end.x - 2.0:
		var stripe := Rect2(x, slab.position.y + 2.0, minf(4.0, slab.end.x - 2.0 - x), 3)
		var colour := ObjectArtTechConfig.security_hazard_color
		kit.box(
			MeshKit.volume(spec.within(stripe), height, 0.3),
			colour if k % 2 == 0 else ObjectArtTechConfig.tech_dark_color,
		)
		x += 4.0
		k += 1
	_bags(spec, kit)


## A stack of three sandbags at each end of the slab, the middle one with a smaller bag on it.
static func _bags(spec: FurnitureSpec, kit: MeshKit) -> void:
	var bag_d := floorf((spec.size.y - 2.0) / 3.0)
	var whole := Rect2(Vector2.ZERO, spec.size)
	var bag := ObjectArtTechConfig.security_sandbag_color
	var stack := ObjectMeshTechConfig.bag_height
	for at: float in [0.0, spec.size.x - floorf(spec.size.x * 0.14)]:
		for n in 3:
			var rect := Rect2(
				at + (n % 2) * 3.0,
				1.0 + n * bag_d,
				floorf(spec.size.x * 0.13),
				bag_d,
			)
			rect = rect.intersection(whole)
			kit.box(MeshKit.volume(spec.within(rect), 0.0, stack), MeshKit.tone(bag, &"dark"), bag)
			if n == 1:
				kit.box(
					MeshKit.volume(spec.within(rect.grow(-2.0)), stack, stack * 0.6),
					bag,
					bag.lightened(0.08),
				)


## A post: a rounded body, the dark lens on its top.
static func _scanner(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	var body := Rect2(Vector2(0, 0) - spec.half(), Vector2(w, d - PROUD))
	kit.extrude(
		FurnitureSpec.rounded(body, 3.0),
		0.0,
		height,
		spec.color,
		MeshKit.tone(spec.color, &"light"),
	)
	var lens := Vector2(w / 2.0, d / 2.0 - 2.0) - spec.half()
	kit.cylinder(Vector3(lens.x, height, lens.y), 2.0, 0.4, ObjectArtTechConfig.tech_dark_color)


## The emitter strip down the front face.
static func _emitter(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	var height := height_of(spec)
	kit.box(
		MeshKit.volume(
			spec.area(3, spec.size.y - PROUD, spec.size.x - 6.0, PROUD), height * 0.1, height * 0.8
		),
		ObjectArtTechConfig.security_beam_color,
	)
	return kit.build()


## The lockers side by side, each with its vents and number plate.
static func _lockers(spec: FurnitureSpec, kit: MeshKit) -> void:
	var count := maxi(2, int(spec.size.x / 24.0))
	var width := floorf(spec.size.x / float(count))
	var height := height_of(spec)
	var d := spec.size.y
	for i in count:
		var steel := spec.color if i % 2 == 0 else spec.color.darkened(0.12)
		kit.box(
			MeshKit.volume(spec.area(i * width, 0, width - 1.0, d - PROUD), 0.0, height),
			steel,
			MeshKit.tone(steel, &"light"),
		)
		for z in [height - 16.0, height - 20.0]:
			kit.box(
				MeshKit.volume(spec.area(i * width + 3.0, d - PROUD, width - 7.0, PROUD), z, 1.4),
				steel.darkened(0.4),
			)
		kit.box(
			MeshKit.volume(
				spec.area(i * width + floorf(width / 2.0) - 1.5, d - PROUD, 3, PROUD),
				height - 8.0,
				2.0,
			),
			ObjectArtTechConfig.security_number_color,
		)
