extends RefCounted
## Objects domain, the 3D mesh of the netrunner den's hardware (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and `tech_painter.gd`'s
## proportions, by `kind`. `monitor_wall` is a desk along the wall with a backboard, a row of
## screens standing on it (the outer two angled in, their faces glowing, every third one dimmer),
## a keyboard, a mug and papers on the ledge in front; `server_rack` is a tall steel cabinet with
## vent slots up its front and a row of LEDs along the top, most lit. The screens and the LEDs are
## glow nodes of the piece's rig, in its neon or the cheap screens' green (and the rack's red and
## green): no real light, which the Lighting domain gives.

const Decay = preload("res://scenes/objects/art/decay.gd")
const OPTIONS := ["kind", "neon", "height"]
## How far a feature stands proud of a face it is laid on.
const PROUD := 0.6
## The yaw of the two outer screens, turned in toward the middle.
const ANGLE := 0.2
## The odds a rack LED is lit.
const LIT := 0.7


## The node a tech `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"tech", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	if _rack(spec):
		for i in 3:
			var glow := FurnitureMesh.fetch_glow(
				"tech_led%d" % i, spec, tuning, func() -> Mesh: return _leds(spec, i)
			)
			rig.add_glow(glow, _led_colours(spec)[i], ObjectMeshStateConfig.led_strength)
	else:
		for dim in [false, true]:
			var glow := FurnitureMesh.fetch_glow(
				"tech_screen_%s" % dim, spec, tuning, func() -> Mesh: return _faces(spec, dim)
			)
			var colour := Decay.screen_color(spec.opts)
			colour = colour.darkened(0.25) if dim else colour
			rig.add_glow(glow, colour, ObjectMeshStateConfig.screen_strength)
	return rig


## Whether the piece is the server rack (`art_opts.kind`), else the monitor wall.
static func _rack(spec: FurnitureSpec) -> bool:
	return String(spec.opts.get("kind", "monitor_wall")) == "server_rack"


## How tall the rack stands: its `art_opts.height`, else the holder's.
static func rack_height(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	return float(own) if own is float or own is int else ObjectMeshTechConfig.rack_height


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS),
		"rack": rack_height(spec),
		"desk": ObjectMeshTechConfig.desk_height,
		"screen": ObjectMeshTechConfig.screen_height,
		"rail": ObjectMeshTechConfig.rail_height,
		"dark": ObjectArtTechConfig.tech_dark_color,
		"ledge": ObjectArtTechConfig.tech_ledge_color,
		"leds": ObjectArtTechConfig.tech_led_colors,
		"screen_colour": Decay.screen_color(spec.opts),
		"props": [
			ObjectArtDecorConfig.prop_colors["plastic_dark"],
			ObjectArtDecorConfig.prop_colors["ceramic"],
			ObjectArtDecorConfig.prop_colors["paper"],
		],
	}


## The screens of a monitor wall of `spec`: their rectangles (px, from the back-left corner), the
## depth of one and whether each is an outer one, from the painter's rules.
static func screens(spec: FurnitureSpec) -> Array[Dictionary]:
	var count := maxi(3, int(spec.size.x / 30.0))
	var width := int((spec.size.x - 4.0) / float(count)) - 2
	var depth := maxi(6, int(spec.size.y * 0.2))
	var out: Array[Dictionary] = []
	for i in count:
		var edge := i == 0 or i == count - 1
		out.append({
			"rect": Rect2(3 + i * (width + 2), 5 + (2 if edge else 0), width, depth),
			"turn": ANGLE if i == 0 else (-ANGLE if i == count - 1 else 0.0),
			"dim": i % 3 == 1,
		})
	return out


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	if _rack(spec):
		_rack_body(spec, kit)
	else:
		_wall(spec, kit)
	return kit.build()


## The desk, its backboard and the screens on it.
static func _wall(spec: FurnitureSpec, kit: MeshKit) -> void:
	var desk := ObjectMeshTechConfig.desk_height
	var rows := screens(spec)
	var first: Rect2 = rows[0]["rect"]
	var dark := ObjectArtTechConfig.tech_dark_color
	var rail := spec.area(0, 0, spec.size.x, 4)
	kit.box(MeshKit.volume(rail, 0.0, ObjectMeshTechConfig.rail_height), dark)
	var shelf := spec.area(0, 4, spec.size.x, first.end.y - 1.0)
	kit.box(MeshKit.volume(shelf, 0.0, desk), dark)
	for row in rows:
		var rect: Rect2 = row["rect"]
		_posed(spec, kit, rect, row["turn"])
		kit.box(
			MeshKit.volume(_around(rect), desk, ObjectMeshTechConfig.screen_height),
			spec.color,
			MeshKit.tone(spec.color, &"light"),
		)
	spec.level(kit)
	_ledge(spec, kit, first.size.y)


## The ledge in front of the screens (`depth` px deep ones) and the keyboard, mug and papers on it.
static func _ledge(spec: FurnitureSpec, kit: MeshKit, depth: float) -> void:
	var desk := ObjectMeshTechConfig.desk_height
	var w := spec.size.x
	var ledge := Rect2(2, 8.0 + depth, w - 4.0, maxf(4.0, spec.size.y - 10.0 - depth))
	var wood := ObjectArtTechConfig.tech_ledge_color
	var top := spec.area(ledge.position.x, ledge.position.y, ledge.size.x, ledge.size.y)
	kit.box(MeshKit.volume(top, 0.0, desk), MeshKit.tone(wood, &"dark"), wood)
	var mid := ledge.position.y + floorf(ledge.size.y / 2.0)
	var props: Dictionary = ObjectArtDecorConfig.prop_colors
	var keys := spec.area(w / 2.0 - 8.0, mid - 3.0, 16, 6)
	kit.box(MeshKit.volume(keys, desk, 1.2), props["plastic_dark"])
	var mug := Vector2(w - 14.0, mid) - spec.half()
	kit.cylinder(Vector3(mug.x, desk, mug.y), 2.5, 4.0, props["ceramic"])
	kit.box(MeshKit.volume(spec.area(10, mid - 5.0, 8, 10), desk, 0.6), props["paper"])


## `rect` of a screen centred on its own origin (what `_posed` placed it by).
static func _around(rect: Rect2) -> Rect2:
	return Rect2(-rect.size * 0.5, rect.size)


## Pose the kit at the centre of the screen `rect` (px from the back-left corner), turned `yaw`.
static func _posed(spec: FurnitureSpec, kit: MeshKit, rect: Rect2, yaw: float) -> void:
	var at := rect.get_center() - spec.half()
	spec.level(kit, Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 0.0, at.y)))


## The glowing faces of the screens (the dimmer ones when `dim`), a thin plate standing proud of
## each one's front.
static func _faces(spec: FurnitureSpec, dim: bool) -> Mesh:
	var kit := spec.kit()
	var desk := ObjectMeshTechConfig.desk_height
	for row in screens(spec):
		if row["dim"] != dim:
			continue
		var rect: Rect2 = row["rect"]
		_posed(spec, kit, rect, row["turn"])
		var front := Rect2(
			Vector2(-rect.size.x * 0.5 + 1.0, rect.size.y * 0.5 - 0.01),
			Vector2(rect.size.x - 2.0, PROUD),
		)
		var screen := ObjectMeshTechConfig.screen_height
		kit.box(MeshKit.volume(front, desk + 3.0, screen - 6.0), Decay.screen_color(spec.opts))
	return kit.build()


## The rack: a cabinet with vent slots up its front, a cable bundle off the back and the dark LEDs
## (the lit ones are `_leds`).
static func _rack_body(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := rack_height(spec)
	var base := spec.color
	var dark := ObjectArtTechConfig.tech_dark_color
	kit.box(
		MeshKit.volume(spec.area(0, 0, w, d - PROUD), 0.0, height),
		base,
		MeshKit.tone(base, &"light"),
	)
	var slot := MeshKit.tone(base, &"shadow")
	for z in range(6, int(height) - 14, 6):
		kit.box(MeshKit.volume(spec.area(4, d - PROUD, w - 8.0, PROUD), float(z), 2.0), slot)
	kit.box(MeshKit.volume(spec.area(w / 2.0 - 3.0, 0, 6, 3), height, 3.0), dark)
	for led in _lit(spec, -1):
		var at: float = led["x"]
		kit.box(
			MeshKit.volume(spec.area(at, d - PROUD, 1.6, PROUD), height - 8.0, 1.6),
			MeshKit.tone(base, &"dark"),
		)


## The colours of the rack's LEDs: the screens' own, then the red and green of the holder.
static func _led_colours(spec: FurnitureSpec) -> Array[Color]:
	var tones := ObjectArtTechConfig.tech_led_colors
	return [Decay.screen_color(spec.opts), tones[0], tones[1]]


## The LEDs of the rack along its front edge, each `{ x, colour }`: the lit ones of colour index
## `pick` (0 to 2), or the dark ones for -1. A fixed stream, so a rack of one look is one mesh.
static func _lit(spec: FurnitureSpec, pick: int) -> Array[Dictionary]:
	var rng := spec.rng("leds", OPTIONS)
	var out: Array[Dictionary] = []
	for x in range(3, int(spec.size.x) - 3, 3):
		var on := rng.randf() < LIT
		var colour := rng.randi_range(0, 2)
		if (pick < 0 and not on) or (pick >= 0 and on and colour == pick):
			out.append({ "x": float(x) })
	return out


## The lit LEDs of colour index `pick`, a small block each on the rack's front near the top.
static func _leds(spec: FurnitureSpec, pick: int) -> Mesh:
	var kit := spec.kit()
	var top := rack_height(spec) - 8.0
	for led in _lit(spec, pick):
		var at: float = led["x"]
		kit.box(
			MeshKit.volume(spec.area(at, spec.size.y - PROUD, 1.6, PROUD), top, 1.6),
			_led_colours(spec)[pick],
		)
	return kit.build()
