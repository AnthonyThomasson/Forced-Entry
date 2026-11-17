extends RefCounted
## Objects domain, the 3D mesh of a wall fixture (the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`), by `art_opts.kind` (`fixture_painter.gd`): a `mirror` is a framed glass
## panel standing against the wall (the back of the footprint) at the height of a bathroom mirror,
## in `ObjectArtDecorConfig.fixture_frame_color` round glass of the piece's tint; a `towels` rack is
## a bar on two brackets with up to three towels hanging from it, in the piece's metal. A mirror's
## neon trim (`art_opts.neon`) is a glow node of the piece's rig.

const Decay = preload("res://scenes/objects/art/decay.gd")
const OPTIONS := ["kind", "neon"]


## The node a fixture `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"fixture", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	rig.hangs_on_wall = true
	var neon := Decay.neon(spec.opts)
	if _is_mirror(spec) and neon.a > 0.0:
		rig.add_glow(FurnitureMesh.fetch_glow(
			"fixture", spec, tuning, func() -> Mesh: return _trim(spec)
		), neon)
	return rig


## Whether the fixture is a mirror (`art_opts.kind`), else a towel bar.
static func _is_mirror(spec: FurnitureSpec) -> bool:
	return String(spec.opts.get("kind", "mirror")) != "towels"


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"kind": "mirror" if _is_mirror(spec) else "towels",
		"neon": String(spec.opts.get("neon", "")),
		"thick": ObjectMeshDecorConfig.fixture_thickness,
		"base": ObjectMeshDecorConfig.fixture_mirror_base,
		"height": ObjectMeshDecorConfig.fixture_mirror_height,
		"bar": ObjectMeshDecorConfig.fixture_bar_height,
		"frame": ObjectArtDecorConfig.fixture_frame_color,
		"props": ObjectArtDecorConfig.prop_colors,
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	if _is_mirror(spec):
		_mirror(spec, kit)
	else:
		_towels(spec, kit)
	return kit.build()


## The frame against the wall and the glass proud of it.
static func _mirror(spec: FurnitureSpec, kit: MeshKit) -> void:
	var thick := ObjectMeshDecorConfig.fixture_thickness
	var base := ObjectMeshDecorConfig.fixture_mirror_base
	var height := ObjectMeshDecorConfig.fixture_mirror_height
	kit.box(
		MeshKit.volume(spec.area(0, 0, spec.size.x, thick), base, height),
		ObjectArtDecorConfig.fixture_frame_color,
	)
	kit.box(
		MeshKit.volume(spec.area(2, thick, spec.size.x - 4, 0.6), base + 2.0, height - 4.0),
		spec.color,
	)


## The neon trim: four thin strips round the frame's front.
static func _trim(spec: FurnitureSpec) -> Mesh:
	var thick := ObjectMeshDecorConfig.fixture_thickness
	var base := ObjectMeshDecorConfig.fixture_mirror_base
	var height := ObjectMeshDecorConfig.fixture_mirror_height
	var w := spec.size.x
	var kit := spec.kit()
	var neon := Decay.neon(spec.opts)
	kit.box(MeshKit.volume(spec.area(0, thick, w, 0.4), base, 1.0), neon)
	kit.box(MeshKit.volume(spec.area(0, thick, w, 0.4), base + height - 1.0, 1.0), neon)
	kit.box(MeshKit.volume(spec.area(0, thick, 1.0, 0.4), base + 1.0, height - 2.0), neon)
	kit.box(MeshKit.volume(spec.area(w - 1.0, thick, 1.0, 0.4), base + 1.0, height - 2.0), neon)
	return kit.build()


## A bar on two brackets with towels hanging over it.
static func _towels(spec: FurnitureSpec, kit: MeshKit) -> void:
	var metal := spec.color
	var w := spec.size.x
	var bar := ObjectMeshDecorConfig.fixture_bar_height
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["towels", spec.size])
	kit.box(MeshKit.volume(spec.area(1, 2, w - 2, 1.6), bar, 1.6), metal)
	for x: float in [2.0, w - 4.0]:
		kit.box(
			MeshKit.volume(spec.area(x, 0, 2, 3.6), bar - 3.0, 4.6),
			MeshKit.tone(metal, &"dark"),
		)
	var list: Array = ObjectArtDecorConfig.prop_colors["towels"]
	var n := clampi(int(w / 18.0), 1, 3)
	var tw := floorf((w - 10.0) / float(n)) - 2.0
	for i in n:
		var colour: Color = list[rng.randi_range(0, list.size() - 1)]
		kit.box(
			MeshKit.volume(spec.area(5.0 + i * (tw + 2.0), 1.0, tw, 3.6), bar - 22.0, 24.0), colour
		)
