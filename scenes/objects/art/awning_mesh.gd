extends RefCounted
## Objects domain, the 3D mesh of what hangs over a tower's front door (#193 phase 2; the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): the piece itself is bare (`awning_painter.gd` draws
## only its overhang), so the mesh is the overhang's, hung on the wall at the back of it. `awning`
## is striped cloth sloping down from a board along the top of the wall (a wall is 96 tall) to a
## front edge `awning_front` over the ground, a valance of scallops along it and a neon line under
## that (a glow node of the piece's rig, no real light). `hanging` is a glyph sign: a blade standing
## out from the wall on a bracket rod, the width the 2D art draws it as its height, a frame of amber
## tube and its two characters in brush strokes, each a glow node of its own colour on both faces.

const OPTIONS := [
	"kind", "stripes", "stripe_px", "scallop_px", "scallop_drop", "board_color", "edge_color",
	"ink_colors", "characters", "frame_color",
]
## How far the tube and the strokes stand proud of the blade's face, and how thick a stroke is.
const PROUD := 0.5
const STROKE := 1.6


## The node an awning `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	if not spec.overhang.has_area():
		return null
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"awning", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	if _hanging(spec):
		var inks := _inks(spec)
		var frame: Color = _opt(spec, "frame_color", ObjectArtAwningConfig.hanging_frame_color)
		var glow := FurnitureMesh.fetch_glow(
			"awning_frame", spec, tuning, func() -> Mesh: return _frame(spec)
		)
		rig.add_glow(glow, frame, ObjectMeshStateConfig.neon_strength)
		for i in _characters(spec).size():
			var ink := FurnitureMesh.fetch_glow(
				"awning_ink%d" % i, spec, tuning, func() -> Mesh: return _ink(spec, i)
			)
			rig.add_glow(ink, inks[i % inks.size()], ObjectMeshStateConfig.neon_strength)
	else:
		var glow := FurnitureMesh.fetch_glow(
			"awning", spec, tuning, func() -> Mesh: return _edge(spec)
		)
		var colour: Color = _opt(spec, "edge_color", ObjectArtAwningConfig.awning_edge_color)
		rig.add_glow(glow, colour, ObjectMeshStateConfig.neon_strength)
	return rig


## Whether the piece is the glyph sign (`art_opts.kind`), else the striped awning.
static func _hanging(spec: FurnitureSpec) -> bool:
	return String(spec.opts.get("kind", "awning")) == "hanging"


## The painter's option `name` of the piece, else `fallback`.
static func _opt(spec: FurnitureSpec, name: String, fallback: Variant) -> Variant:
	return spec.opts.get(name, fallback)


## The two stripe colours of the cloth.
static func _stripes(spec: FurnitureSpec) -> Array:
	return _opt(spec, "stripes", ObjectArtAwningConfig.awning_stripes)


## The sign's characters and the ink of each.
static func _characters(spec: FurnitureSpec) -> Array:
	return _opt(spec, "characters", ObjectArtAwningConfig.hanging_characters)


## The ink of each character of the sign.
static func _inks(spec: FurnitureSpec) -> Array:
	return _opt(spec, "ink_colors", ObjectArtAwningConfig.hanging_ink_colors)


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS),
		"stripes": _stripes(spec),
		"stripe_px": int(_opt(spec, "stripe_px", ObjectArtAwningConfig.awning_stripe_px)),
		"scallop": int(_opt(spec, "scallop_px", ObjectArtAwningConfig.awning_scallop_px)),
		"drop": int(_opt(spec, "scallop_drop", ObjectArtAwningConfig.awning_scallop_drop)),
		"board": _opt(spec, "board_color", ObjectArtAwningConfig.awning_board_color),
		"hanging_board": _opt(spec, "board_color", ObjectArtAwningConfig.hanging_board_color),
		"frame": _opt(spec, "frame_color", ObjectArtAwningConfig.hanging_frame_color),
		"edge": _opt(spec, "edge_color", ObjectArtAwningConfig.awning_edge_color),
		"inks": _inks(spec),
		"characters": _characters(spec),
		"sizes": [
			ObjectMeshOverheadConfig.awning_front, ObjectMeshOverheadConfig.awning_rise,
			ObjectMeshOverheadConfig.awning_board, ObjectMeshOverheadConfig.awning_valance,
			ObjectMeshOverheadConfig.hanging_blade, ObjectMeshOverheadConfig.hanging_depth,
			ObjectMeshOverheadConfig.hanging_rod,
		],
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	if _hanging(spec):
		_blade(spec, kit)
	else:
		_cloth(spec, kit)
	return kit.build()


## The row below the cloth's last pixel at column `x` (px along the front): the scallop's depth
## under the front edge, the painter's half ellipse (the valance's own height).
static func _scallop(spec: FurnitureSpec, x: float) -> float:
	var scallop := maxf(
		1.0,
		float(_opt(spec, "scallop_px", ObjectArtAwningConfig.awning_scallop_px)),
	)
	var d := ((fmod(x, scallop)) + 0.5 - scallop * 0.5) / (scallop * 0.5)
	return ObjectMeshOverheadConfig.awning_valance * sqrt(maxf(0.0, 1.0 - d * d))


## The awning: the board along the wall, the stripes of cloth sloping down from it and the valance.
static func _cloth(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.overhang.size.x
	var d := spec.overhang.size.y
	var front := ObjectMeshOverheadConfig.awning_front
	var rise := ObjectMeshOverheadConfig.awning_rise
	var board := ObjectMeshOverheadConfig.awning_board
	var stripes := _stripes(spec)
	var stripe := maxi(1, int(_opt(spec, "stripe_px", ObjectArtAwningConfig.awning_stripe_px)))
	for k in range(0, int(w), stripe):
		var colour: Color = stripes[int(k / float(stripe)) % 2]
		var run := minf(float(stripe), w - k)
		kit.wedge(
			MeshKit.volume(spec.over_area(k, 3, run, d - 3.0), front, rise),
			Vector2.UP,
			colour.darkened(0.15),
			colour,
		)
		for x in range(k, k + int(run), 2):
			var height := _scallop(spec, float(x))
			if height > 0.2:
				kit.box(
					MeshKit.volume(spec.over_area(x, d - 1.0, 2, 1), front - height, height),
					colour.darkened(0.12),
				)
	kit.box(
		MeshKit.volume(spec.over_area(0, 0, w, 3), front + rise - board + 2.0, board),
		_opt(spec, "board_color", ObjectArtAwningConfig.awning_board_color),
	)


## The neon line along the front edge, under the valance.
static func _edge(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	kit.box(
		MeshKit.volume(
			spec.over_area(0, spec.overhang.size.y - 0.6, spec.overhang.size.x, 0.6),
			ObjectMeshOverheadConfig.awning_front - ObjectMeshOverheadConfig.awning_valance - 0.6,
			0.6,
		),
		_opt(spec, "edge_color", ObjectArtAwningConfig.awning_edge_color),
	)
	return kit.build()


## The blade's frame in the overhang: where it stands (across x), how long it is (along y) and the
## bottom of it (height).
static func _blade_rect(spec: FurnitureSpec) -> Rect2:
	var depth := ObjectMeshOverheadConfig.hanging_depth
	var middle := spec.overhang.size.x / 2.0
	return spec.over_area(middle - depth * 0.5, 5, depth, spec.overhang.size.y - 6.0)


## The glyph sign: a rod from the wall and the blade hung from it, dark.
static func _blade(spec: FurnitureSpec, kit: MeshKit) -> void:
	var rod := ObjectMeshOverheadConfig.hanging_rod
	var blade := _blade_rect(spec)
	var middle := spec.overhang.size.x / 2.0
	kit.box(
		MeshKit.volume(
			spec.over_area(middle - 1.0, 0, 2, blade.end.y - spec.overhang.position.y),
			rod,
			2.0,
		),
		Color(0.3, 0.3, 0.33),
	)
	var board: Color = _opt(spec, "board_color", ObjectArtAwningConfig.hanging_board_color)
	kit.box(
		MeshKit.volume(
			blade,
			rod - ObjectMeshOverheadConfig.hanging_blade,
			ObjectMeshOverheadConfig.hanging_blade,
		),
		board,
		MeshKit.tone(board, &"light"),
	)


## The amber frame round both faces of the blade.
static func _frame(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	var blade := _blade_rect(spec)
	var base := ObjectMeshOverheadConfig.hanging_rod - ObjectMeshOverheadConfig.hanging_blade
	var high := ObjectMeshOverheadConfig.hanging_blade
	var bars := [
		Rect2(0, 2.0, blade.size.y, 1.2),
		Rect2(0, high - 3.2, blade.size.y, 1.2),
		Rect2(2.0, 2.0, 1.2, high - 4.0),
		Rect2(blade.size.y - 3.2, 2.0, 1.2, high - 4.0),
	]
	for face in _faces(blade):
		for bar: Rect2 in bars:
			kit.box(
				MeshKit.volume(
					Rect2(face, blade.position.y + bar.position.x, PROUD, bar.size.x),
					base + bar.position.y,
					bar.size.y,
				),
				_opt(spec, "frame_color", ObjectArtAwningConfig.hanging_frame_color),
			)
	return kit.build()


## The x of each of the blade's two faces (the strip standing proud of it, a rectangle's origin).
static func _faces(blade: Rect2) -> Array[float]:
	return [blade.end.x, blade.position.x - PROUD]


## The brush strokes of character `i` on both faces, laid along the blade at the painter's spacing.
static func _ink(spec: FurnitureSpec, i: int) -> Mesh:
	var kit := spec.kit()
	var blade := _blade_rect(spec)
	var colour: Color = _inks(spec)[i % _inks(spec).size()]
	var along := spec.overhang.position.y + 10.0 + float(i) * 30.0
	var top := ObjectMeshOverheadConfig.hanging_rod - 4.0
	for at in FurnitureGlyphs.strokes(_characters(spec)[i], 18.0, STROKE):
		for face in _faces(blade):
			kit.box(
				MeshKit.volume(
					Rect2(face, along + at.x, PROUD, STROKE),
					top - at.y - STROKE * 0.5,
					STROKE,
				),
				colour,
			)
	return kit.build()
