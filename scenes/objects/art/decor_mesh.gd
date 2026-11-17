extends RefCounted
## Objects domain, the 3D mesh of a run-down house's walk-over clutter and the neon on its walls
## (the pattern is `table_mesh.gd`, `domain-art/meshes.md`): non-solid decor at the
## piece's own footprint, by `kind` (`decor_painter.gd`): `trash` is three black bags with knots
## and cans, papers and a bottle round them; `cables` loose runs of cable and `cable_nest` a tangle
## of them, each a thin square loft along a snaking path; `cardboard` a flattened box with its
## crease and a blanket heaped over half of it; `puddle` standing water, a flat dark pool of four
## lobes; `neon_tube` a tube on the floor, its end caps dark and the tube itself a glow node of the
## piece's rig in its `tone` (`cyan` or `magenta`), no real light. Scatter is a fixed stream seeded
## by the look (`art_opts.v` too), so a piece of one look is one mesh.

const Decay = preload("res://scenes/objects/art/decay.gd")
const OPTIONS := ["kind", "tone", "v"]
const COLOURS := {
	"bag": Color(0.1, 0.1, 0.11),
	"paper": Color(0.86, 0.84, 0.76),
	"bottle": Color(0.25, 0.45, 0.22),
	"card": Color(0.62, 0.48, 0.3),
	"blanket": Color(0.3, 0.32, 0.22),
	"water": Color(0.2, 0.26, 0.31),
	"end": Color(0.2, 0.2, 0.22),
}
const CANS: Array[Color] = [Color(0.75, 0.15, 0.15), Color(0.2, 0.5, 0.75), Color(0.8, 0.8, 0.82)]
const CABLES: Array[Color] = [
	Color(
		0.08,
		0.08,
		0.08,
	), Color(0.12, 0.12, 0.14), Color(0.55, 0.14, 0.12), Color(0.85, 0.65, 0.15),
]


## The node a decor `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"decor", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	if _kind(spec) == "neon_tube":
		var glow := FurnitureMesh.fetch_glow(
			"decor", spec, tuning, func() -> Mesh: return _tube(spec)
		)
		rig.add_glow(glow, _tone(spec), ObjectMeshStateConfig.neon_strength)
	return rig


## The kind the piece is: its `art_opts.kind` (a piece with none draws nothing).
static func _kind(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("kind", ""))


## The neon colour of a tube: its `tone`, else cyan.
static func _tone(spec: FurnitureSpec) -> Color:
	return Decay.neon({ "neon": spec.opts.get("tone", "cyan") })


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS),
		"heights": [
			ObjectMeshShellConfig.cable, ObjectMeshShellConfig.cardboard,
			ObjectMeshShellConfig.blanket, ObjectMeshShellConfig.puddle,
			ObjectMeshShellConfig.neon_tube,
		],
		"tone": _tone(spec),
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	var rng := spec.rng("decor", OPTIONS)
	match _kind(spec):
		"trash":
			_trash(spec, kit, rng)
		"cables":
			_cables(spec, kit, rng, 3, false)
		"cable_nest":
			_cables(spec, kit, rng, 7, true)
		"cardboard":
			_cardboard(spec, kit)
		"puddle":
			_puddle(spec, kit, rng)
		"neon_tube":
			_ends(spec, kit)
	return kit.build()


## Three black bags with their knots, and six cans, papers and bottles scattered round them.
static func _trash(spec: FurnitureSpec, kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var w := int(spec.size.x)
	var h := int(spec.size.y)
	for _i in 3:
		var r := rng.randi_range(4, 7)
		var at := Vector2(
			rng.randi_range(r, maxi(r, w - r - 1)), rng.randi_range(r, maxi(r, h - r - 1))
		) - spec.half()
		spec.level(
			kit,
			Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.0)), Vector3(at.x, 0.0, at.y)),
		)
		kit.sphere(Vector3(0.0, float(r), 0.0), float(r), COLOURS["bag"])
		spec.level(kit)
		kit.box(
			MeshKit.volume(Rect2(at - Vector2(0.7, 0.7), Vector2(1.4, 1.4)), float(r) * 1.6, 1.2),
			(COLOURS["bag"] as Color).lightened(0.2),
		)
	for _i in 6:
		var p := Vector2(rng.randi_range(1, maxi(1, w - 4)), rng.randi_range(1, maxi(1, h - 3)))
		match rng.randi_range(0, 2):
			0:
				kit.box(
					MeshKit.volume(spec.area(p.x, p.y, 3, 2), 0.0, 2.0),
					CANS[rng.randi_range(0, 2)],
				)
			1:
				kit.box(MeshKit.volume(spec.area(p.x, p.y, 3, 3), 0.0, 0.6), COLOURS["paper"])
			_:
				kit.box(MeshKit.volume(spec.area(p.x, p.y, 4, 1.4), 0.0, 1.4), COLOURS["bottle"])


## `count` cables snaking along the piece (or, for a nest, looping round on themselves): a square
## loft along each path.
static func _cables(
	spec: FurnitureSpec, kit: MeshKit, rng: RandomNumberGenerator, count: int, nest: bool
) -> void:
	var thick := ObjectMeshShellConfig.cable
	var square := PackedVector2Array(
		[
			Vector2(-1, 0) * thick * 0.5,
			Vector2(1, 0) * thick * 0.5,
			Vector2(1, 1) * thick,
			Vector2(-1, 1) * thick,
		]
	)
	var bound := Rect2(2, 2, spec.size.x - 4.0, spec.size.y - 4.0)
	for i in count:
		var p := (
			Vector2(0.0, rng.randf_range(2.0, spec.size.y - 3.0))
			if not nest
			else Vector2(
				rng.randf_range(4.0, spec.size.x - 5.0),
				rng.randf_range(4.0, spec.size.y - 5.0),
			)
		)
		var heading := 0.0 if not nest else rng.randf() * TAU
		var path := PackedVector3Array()
		var steps := int(spec.size.x * 2.0) if not nest else int(spec.size.x * 3.0)
		for k in steps:
			heading += rng.randf_range(-0.35, 0.35) if not nest else rng.randf_range(-0.15, 0.6)
			if not nest:
				heading = clampf(heading, -0.6, 0.6)
			p += Vector2(cos(heading), sin(heading)) * 0.6
			if nest:
				p = p.clamp(bound.position, bound.end)
			else:
				p.y = clampf(p.y, bound.position.y, bound.end.y)  # a run stays on its piece
			if k % 6 == 0 and bound.has_point(p):
				var at := p - spec.half()
				path.append(Vector3(at.x, float(i % 2) * 0.2, at.y))
		kit.loft(path, square, CABLES[i % CABLES.size()])


## A flattened box with its crease and the blanket heaped on half of it.
static func _cardboard(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var h := spec.size.y
	var card: Color = COLOURS["card"]
	kit.box(
		MeshKit.volume(spec.area(0, 0, w, h), 0.0, ObjectMeshShellConfig.cardboard),
		card.darkened(0.1),
		card,
	)
	kit.box(
		MeshKit.volume(spec.area(0, floorf(h / 2.0), w, 1), ObjectMeshShellConfig.cardboard, 0.2),
		card.darkened(0.3),
	)
	var blanket: Color = COLOURS["blanket"]
	kit.wedge(
		MeshKit.volume(
			spec.area(floorf(w * 0.4), 2, floorf(w * 0.55), h - 4.0),
			ObjectMeshShellConfig.cardboard,
			ObjectMeshShellConfig.blanket,
		),
		Vector2.LEFT,
		blanket.darkened(0.2),
		blanket,
	)


## Standing water: four overlapping flat lobes, one dark.
static func _puddle(spec: FurnitureSpec, kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var size := spec.size
	for _i in 4:
		var offset := Vector2(
			rng.randf_range(-0.3, 0.3) * size.x,
			rng.randf_range(-0.25, 0.25) * size.y,
		)
		var radius := size * rng.randf_range(0.3, 0.5)
		var lobe := Rect2(offset - radius, radius * 2.0).intersection(Rect2(-size / 2.0, size))
		kit.extrude(
			FurnitureSpec.ellipse(lobe, 12),
			0.0,
			ObjectMeshShellConfig.puddle,
			COLOURS["water"],
		)


## The dark caps at the two ends of a neon tube.
static func _ends(spec: FurnitureSpec, kit: MeshKit) -> void:
	var mid := floorf(spec.size.y / 2.0)
	for x: float in [0.0, spec.size.x - 1.0]:
		kit.box(
			MeshKit.volume(spec.area(x, mid - 1.0, 1, 3), 0.0, ObjectMeshShellConfig.neon_tube),
			COLOURS["end"],
		)


## The tube itself, a bar along the piece's length at the height of the holder.
static func _tube(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	var mid := floorf(spec.size.y / 2.0)
	kit.box(
		MeshKit.volume(
			spec.area(1, mid - 1.0, spec.size.x - 2.0, 3),
			0.0,
			ObjectMeshShellConfig.neon_tube,
		),
		_tone(spec),
	)
	return kit.build()
