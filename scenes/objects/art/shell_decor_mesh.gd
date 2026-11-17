extends RefCounted
## Objects domain, the 3D mesh of a shell's loose things (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): walk-over decor lying on the floor of a roofless
## district shell, at the piece's own footprint and `shell_decor_painter.gd`'s layout, by `kind`.
## `rebar` is two layers of steel rods tied in two places; `rubble` a heap of broken concrete,
## thickest in the middle; `scaffold` boards across three tubes, braced by diagonals; `cement` a
## stack of paper bags each with a red label; `stain` damp running down the wall at the back of its
## footprint, streaks of the damp colour that fade out down the wall (it hangs on the wall: the
## painter's top edge is the wall, the streaks start `stain_top` up it). Painted colours are as
## drawn: the painter's own holder (`ObjectArtShellDecorConfig`), or the piece's `art_opts`.
## Non-solid: no collider.

const OPTIONS := ["kind", "steel", "concrete", "tube", "board", "bag", "damp"]
## The section of a scaffold's diagonal brace.
const BRACE := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
## How many steps a streak fades in.
const FADE := 4


## The node a shell-decor `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"shell_decor", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	))
	rig.hangs_on_wall = _kind(spec) == "stain"
	return rig


## The kind the piece is: its `art_opts.kind`, else the painter's.
static func _kind(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("kind", "rubble"))


## The painter's colour option `name` of the piece, else its holder default.
static func _colour(spec: FurnitureSpec, name: String) -> Color:
	var defaults := {
		"steel": ObjectArtShellDecorConfig.shell_steel,
		"concrete": ObjectArtShellDecorConfig.shell_concrete,
		"tube": ObjectArtShellDecorConfig.shell_tube,
		"board": ObjectArtShellDecorConfig.shell_board,
		"bag": ObjectArtShellDecorConfig.shell_bag,
		"damp": ObjectArtShellDecorConfig.shell_damp,
	}
	return spec.opts.get(name, defaults[name])


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	var out := {
		"opts": spec.read(OPTIONS),
		"heights": [
			ObjectMeshShellConfig.rod, ObjectMeshShellConfig.rubble_low,
			ObjectMeshShellConfig.rubble_high, ObjectMeshShellConfig.tube,
			ObjectMeshShellConfig.board, ObjectMeshShellConfig.bag,
		],
		"stain": [ObjectMeshShellConfig.stain_top, ObjectMeshShellConfig.stain_lift],
	}
	for name in ["steel", "concrete", "tube", "board", "bag", "damp"]:
		out[name] = _colour(spec, name)
	return out


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	match _kind(spec):
		"rebar":
			_rebar(spec, kit)
		"scaffold":
			_scaffold(spec, kit)
		"cement":
			_cement(spec, kit)
		"stain":
			_stain(spec, kit)
		_:
			_rubble(spec, kit)
	return kit.build()


## Rods lying along the piece's length, two layers of them, tied at two places.
static func _rebar(spec: FurnitureSpec, kit: MeshKit) -> void:
	var rng := spec.rng("rebar", OPTIONS)
	var steel := _colour(spec, "steel")
	var rod := ObjectMeshShellConfig.rod
	for y in range(1, int(spec.size.y) - 2, 4):
		var shade := steel.lightened(rng.randf_range(-0.1, 0.1))
		var start := float(rng.randi_range(0, 3))
		var run := maxf(4.0, spec.size.x - float(rng.randi_range(0, 6)) - 3.0 - start)
		var layer := int(y / 4.0) % 2
		kit.box(
			MeshKit.volume(spec.area(start, y, run, 2), float(layer) * rod, rod),
			shade,
			shade.lightened(0.35),
		)
	for x: float in [floorf(spec.size.x * 0.3), floorf(spec.size.x * 0.72)]:
		kit.box(
			MeshKit.volume(spec.area(x, 0, 2, spec.size.y), 0.0, rod * 2.0 + 0.6),
			Color(0.1, 0.1, 0.12),
		)


## A heap of chunks, thickest in the middle: each as high as the painter's random pick between the
## holder's low and high, stacked nearer the middle.
static func _rubble(spec: FurnitureSpec, kit: MeshKit) -> void:
	var rng := spec.rng("rubble", OPTIONS)
	var concrete := _colour(spec, "concrete")
	var middle := spec.size * 0.5
	var whole := Rect2(1, 1, spec.size.x - 2.0, spec.size.y - 2.0)
	for _i in int(spec.size.x * spec.size.y / 90.0):
		var at := Vector2(
			middle.x + rng.randfn(0.0, spec.size.x * 0.2),
			middle.y + rng.randfn(0.0, spec.size.y * 0.2),
		).floor()
		var chunk := Rect2(at, Vector2(rng.randi_range(4, 11), rng.randi_range(3, 8)))
		var tone := concrete.lightened(rng.randf_range(-0.3, 0.25))
		var height := lerpf(
			ObjectMeshShellConfig.rubble_low, ObjectMeshShellConfig.rubble_high, rng.randf()
		)
		if whole.encloses(chunk):
			kit.box(
				MeshKit.volume(
					spec.area(chunk.position.x, chunk.position.y, chunk.size.x, chunk.size.y),
					0.0,
					height,
				),
				tone,
				tone.lightened(0.1),
			)


## Three tubes along the piece's depth, boards across them, a diagonal brace between each two
## boards' ends.
static func _scaffold(spec: FurnitureSpec, kit: MeshKit) -> void:
	var rng := spec.rng("scaffold", OPTIONS)
	var tube := _colour(spec, "tube")
	var board := _colour(spec, "board")
	var tube_h := ObjectMeshShellConfig.tube
	var board_h := ObjectMeshShellConfig.board
	for x: float in [1.0, floorf(spec.size.x / 2.0), spec.size.x - 4.0]:
		kit.box(
			MeshKit.volume(spec.area(x, 0, 3, spec.size.y), 0.0, tube_h),
			tube,
			tube.lightened(0.3),
		)
	for y in range(3, int(spec.size.y) - 3, 12):
		kit.box(
			MeshKit.volume(
				spec.area(0, y, spec.size.x, minf(9.0, spec.size.y - 3.0 - y)),
				tube_h,
				board_h,
			),
			board.darkened(rng.randf_range(0.0, 0.2)),
		)
	for x in range(0, int(spec.size.x) - 20, 40):
		var from := spec.area(x + 1.0, 1.0, 0, 0).position
		var to := spec.area(x + 21.0, spec.size.y - 2.0, 0, 0).position
		kit.loft(
			PackedVector3Array([Vector3(from.x, 2.0, from.y), Vector3(to.x, 2.0, to.y)]),
			BRACE,
			tube.darkened(0.2),
		)


## A scatter of paper bags, each with its label, the way the painter strews them.
static func _cement(spec: FurnitureSpec, kit: MeshKit) -> void:
	var rng := spec.rng("cement", OPTIONS)
	var bag := _colour(spec, "bag")
	for i in 2 + int(spec.size.x / 40.0):
		var at := Vector2(
			rng.randi_range(0, maxi(0, int(spec.size.x) - 26)),
			rng.randi_range(0, maxi(0, int(spec.size.y) - 16)),
		)
		var tone := bag.darkened(rng.randf_range(0.0, 0.18))
		var height := ObjectMeshShellConfig.bag + float(i % 3)
		kit.box(
			MeshKit.volume(spec.area(at.x, at.y, 24, 15), 0.0, height),
			MeshKit.tone(tone, &"dark"),
			tone.lightened(0.05),
		)
		kit.box(
			MeshKit.volume(spec.area(at.x + 7.0, at.y + 8.0, 9, 3), height, 0.3),
			Color(0.7, 0.2, 0.16),
		)


## The streaks of damp down the wall at the footprint's back edge: columns every three px, each as
## long as the painter's falloff gives, a few fading steps a column, thinnest at its foot.
static func _stain(spec: FurnitureSpec, kit: MeshKit) -> void:
	var rng := spec.rng("stain", OPTIONS)
	var damp := _colour(spec, "damp")
	var ground := _colour(spec, "concrete")
	var lift := ObjectMeshShellConfig.stain_lift
	var top := ObjectMeshShellConfig.stain_top
	for x in range(2, int(spec.size.x) - 2, 3):
		var length := spec.size.y * rng.randf_range(
			0.25,
			1.0,
		) * (1.0 - absf(x - spec.size.x * 0.5) / spec.size.x)
		var span := length / float(FADE)
		for step in FADE:
			var fade := 1.0 - (float(step) + 0.5) / float(FADE)
			var tone := ground.lerp(damp, 0.8 * fade)
			var rect := spec.area(x, 0, 2, 0).position
			kit.box(
				AABB(
					Vector3(rect.x, top - float(step + 1) * span, rect.y),
					Vector3(2.0, span, lift),
				),
				tone,
			)
