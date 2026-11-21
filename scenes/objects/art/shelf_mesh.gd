extends RefCounted
## Objects domain, the 3D mesh of an open shelf (the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): at the piece's own footprint, a side at each end, a back, and boards in
## levels, in the piece's colour, with what the shelf holds standing on each board: book spines,
## cardboard boxes or pairs of shoes (`shelf_painter.gd`: `contents`,
## `ObjectArtStorageConfig.shelf_*` and `ObjectArtDecorConfig.prop_colors`), unless the shelf is
## `loose` (`art_opts.loose`, decision D21): then it is bare boards, and what it held is loose items
## standing on them (`shelf_loose.gd`, `PieceCarries`). The contents are picked by a generator
## seeded from the look, so every shelf of one look is the same mesh. How tall it stands is the
## piece's own `art_opts.height`, else a rule of its footprint and contents (`height_of`).

const OPTIONS := ["contents", "height", "loose"]
## How thick (px) an emptied shelf's side and back are as bodies, thicker than they are drawn: a
## car's step is 8 px a frame, and a body pushed against a 2 px plate is shoved along without the
## blow that lays a real shelf over. The mesh draws them as thick as the body, and the things on its
## boards keep inside them (`ShelfLoose`).
const HULL := 4.0


## The node a shelf `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var mesh := FurnitureMesh.fetch(
		"shelf", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	)
	return FurnitureMesh.show(piece, mesh)


## What the shelf holds: `art_opts.contents`, else the painter's default.
static func contents_of(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("contents", ObjectArtStorageConfig.shelf_contents))


## How tall a shelf of `spec` stands: its `art_opts.height`, else a shoe rack's, else a short
## shelf's for a small footprint, else the standard.
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	if contents_of(spec) == "shoes":
		return ObjectMeshStorageConfig.shelf_shoe_height
	if spec.size.x * spec.size.y <= ObjectMeshStorageConfig.shelf_short_area \
			and contents_of(spec) != "books":
		return ObjectMeshStorageConfig.shelf_short_height
	return ObjectMeshStorageConfig.shelf_height


## Whether the shelf is emptied: its contents are loose items, not part of its mesh.
static func is_loose(spec: FurnitureSpec) -> bool:
	return bool(spec.opts.get("loose", false))


## The shelf's solids as parts of the piece (`PieceHeights`): the two sides and the back at the
## full height and each board as a slab but the top one (an emptied shelf is open on top: what it
## holds is seen from above), so the compartments between the boards are open to what stands in
## them. Boards and sides as `{ base, top, rect }` with `rect` in the footprint's unit
## square.
static func hollow_parts(spec: FurnitureSpec) -> Array[Dictionary]:
	var h := height_of(spec)
	var side := HULL
	var board := ObjectMeshStorageConfig.shelf_board
	var size := Vector2(maxf(spec.size.x, 1.0), maxf(spec.size.y, 1.0))
	var out: Array[Dictionary] = []
	var areas := [
		Rect2(0, 0, side, spec.size.y),
		Rect2(spec.size.x - side, 0, side, spec.size.y),
		Rect2(side, 0, spec.size.x - 2.0 * side, HULL),
	]
	for area: Rect2 in areas:
		out.append({ "base": 0.0, "top": h, "rect": Rect2(area.position / size, area.size / size) })
	var levels := levels_of(h)
	var gap := (h - board) / (levels - 1)
	var slab := Rect2(side, HULL, spec.size.x - 2.0 * side, spec.size.y - HULL)
	for k in levels - 1:
		out.append({
			"base": gap * k,
			"top": gap * k + board,
			"rect": Rect2(slab.position / size, slab.size / size),
		})
	return out


## How many boards the shelf has, the floor and the top included.
static func levels_of(height: float) -> int:
	return maxi(2, roundi(height / ObjectMeshStorageConfig.shelf_level))


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"contents": contents_of(spec),
		"loose": is_loose(spec),
		"height": height_of(spec),
		"board": ObjectMeshStorageConfig.shelf_board,
		"side": ObjectMeshStorageConfig.shelf_side,
		"level": ObjectMeshStorageConfig.shelf_level,
		"box": ObjectArtStorageConfig.shelf_box_color,
		"props": ObjectArtDecorConfig.prop_colors,
	}


## The solids of the piece, built once per cache key: two sides, the back, a board per level and
## what stands on each.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var h := height_of(spec)
	var board := ObjectMeshStorageConfig.shelf_board
	var levels := levels_of(h)
	var kit := spec.kit()
	_carcass(spec, kit, h)
	# An emptied shelf has no top board: its contents are loose items, seen from above.
	var boards := levels - 1 if is_loose(spec) else levels
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([spec.size, contents_of(spec), levels])
	var gap := (h - board) / (levels - 1)
	var side := _side(spec)
	var back := _back(spec)
	for k in boards:
		kit.box(
			MeshKit.volume(
				spec.area(side, back, spec.size.x - 2.0 * side, spec.size.y - back),
				gap * k,
				board,
			),
			MeshKit.tone(spec.color, &"dark"),
			spec.color,
		)
		if k < levels - 1 and not is_loose(spec):
			_contents(spec, kit, rng, gap * k + board, gap - board)
	return kit.build()


## The two sides and the back panel.
static func _carcass(spec: FurnitureSpec, kit: MeshKit, h: float) -> void:
	var wood := spec.color
	var side := _side(spec)
	var dark := MeshKit.tone(wood, &"dark")
	kit.box(MeshKit.volume(spec.area(0, 0, side, spec.size.y), 0.0, h), dark, wood)
	kit.box(
		MeshKit.volume(spec.area(spec.size.x - side, 0, side, spec.size.y), 0.0, h), dark, wood
	)
	kit.box(
		MeshKit.volume(spec.area(side, 0, spec.size.x - 2.0 * side, _back(spec)), 0.0, h),
		MeshKit.tone(wood, &"shadow"),
	)


## How thick the shelf's sides are drawn: `HULL`, as the body has them, when it is emptied.
static func _side(spec: FurnitureSpec) -> float:
	return HULL if is_loose(spec) else ObjectMeshStorageConfig.shelf_side


## How thick the shelf's back is drawn (`HULL` when it is emptied).
static func _back(spec: FurnitureSpec) -> float:
	return HULL if is_loose(spec) else 1.5


## What stands on the board whose top is `at`, `room` px below the next board.
static func _contents(
	spec: FurnitureSpec, kit: MeshKit, rng: RandomNumberGenerator, at: float, room: float
) -> void:
	var side := ObjectMeshStorageConfig.shelf_side
	var x := side + 0.5
	var end := spec.size.x - side - 0.5
	var kind := contents_of(spec)
	while x < end - 1.0:
		match kind:
			"books":
				x = _book(spec, kit, rng, Vector3(x, at, room), end)
			"boxes":
				x = _box(spec, kit, rng, Vector3(x, at, room), end)
			_:
				x = _shoe(spec, kit, rng, Vector3(x, at, room), end)


## A book at `at.x` on the board `at.y` high with `at.z` px of room above it; the x past it.
static func _book(
	spec: FurnitureSpec, kit: MeshKit, rng: RandomNumberGenerator, at: Vector3, end: float
) -> float:
	var bw := minf(rng.randf_range(2.0, 4.0), end - at.x)
	if rng.randf() < 0.1:
		return at.x + rng.randf_range(1.0, 3.0)
	kit.box(
		MeshKit.volume(
			spec.area(at.x, 2.0, bw, spec.size.y * 0.6), at.y, at.z * rng.randf_range(0.6, 0.95)
		),
		_pick(rng, "books"),
		ObjectArtDecorConfig.prop_colors["paper"],
	)
	return at.x + bw


## A cardboard box (placed like `_book`); the x past it.
static func _box(
	spec: FurnitureSpec, kit: MeshKit, rng: RandomNumberGenerator, at: Vector3, end: float
) -> float:
	var bw := minf(rng.randf_range(0.22, 0.34) * spec.size.x, end - at.x)
	kit.box(
		MeshKit.volume(
			spec.area(at.x, 2.0, bw, spec.size.y - 4.0), at.y, at.z * rng.randf_range(0.5, 0.8)
		),
		ObjectArtStorageConfig.shelf_box_color,
	)
	return at.x + bw + 1.0


## A shoe (placed like `_book`); the x past it.
static func _shoe(
	spec: FurnitureSpec, kit: MeshKit, rng: RandomNumberGenerator, at: Vector3, end: float
) -> float:
	var pw := minf(5.0, end - at.x)
	kit.box(
		MeshKit.volume(
			spec.area(at.x, spec.size.y * 0.25, pw, spec.size.y * 0.55), at.y, minf(at.z * 0.4, 6.0)
		),
		_pick(rng, "shoes"),
	)
	return at.x + pw + rng.randf_range(1.0, 3.0)


## A colour of `list` of `ObjectArtDecorConfig.prop_colors`, picked by `rng`.
static func _pick(rng: RandomNumberGenerator, list: String) -> Color:
	var colours: Array = ObjectArtDecorConfig.prop_colors[list]
	return colours[rng.randi_range(0, colours.size() - 1)]
