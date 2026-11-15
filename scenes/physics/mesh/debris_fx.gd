class_name DebrisFx
extends RefCounted
## Physics domain, the chips of the 3D render (#193 phase 2; `domain-physics/meshes.md`): a chip
## `DebrisSpawner` throws is one part of a batch (a rectangle, a triangle or a disc, as in 2D), in
## the colour and size of its 2D chip. It follows its 2D node while it flies (its place, its turn,
## and a height: it leaves the surface at the hit's height and falls to the floor along an arc over
## the chip's own `eject_time`), then lies where the 2D chip came to rest (`land`), written once and
## never again. A chip the `Despawner` frees on the wing is gone; what lies is kept up to the
## `Despawner`'s cap, as `DebrisLayer` keeps it, the oldest dropped first. The batches are made
## once, so nothing is allocated while chips fly: each holds that cap of chips lying and
## `PhysicsMeshConfig.flying_room` in the air (a chip past that room is shown from where it lands).

## The batches by chip shape (`"rect"`, `"tri"`, `"circle"`).
var _batches: Dictionary = {}
## The chips in the air, and those that lie (oldest first).
var _flying: Array[FxPiece] = []
var _lying := PieceQueue.new()
## How many chips the world keeps at most (the `Despawner`'s cap when the effects were built).
var _cap := 1
## The ground the chips lie on (the road a kerb lower).
var _world: FxWorld


## Batches under `parent` (the 3D world's frame), each as big as `cap`, the most chips shown, over
## the ground of `world`.
func _init(parent: Node3D, cap: int, world: FxWorld) -> void:
	_world = world
	_cap = maxi(cap, 1)
	for shape: String in ["rect", "tri", "circle"]:
		var batch := FxBatch.new(_mesh(shape), _cap + PhysicsMeshConfig.flying_room)
		batch.node.name = "Debris_" + shape
		parent.add_child(batch.node)
		_batches[shape] = batch


## How many chips are shown (in the air and lying), how many fly, and how many lie.
func shown() -> int:
	return _flying.size() + _lying.size()


## How many chips fly.
func flying() -> int:
	return _flying.size()


## How many chips lie.
func lying() -> int:
	return _lying.size()


## How many frames the batches wrote since the start (a chip that lies is never written again).
func writes() -> int:
	var total := 0
	for batch: FxBatch in _batches.values():
		total += batch.writes
	return total


## The shown chips: `[piece, frame]` for each, flying first.
func chips() -> Array:
	var out := []
	for piece: FxPiece in _flying + _lying.items():
		out.append([piece, piece.batch.frame_of(piece)])
	return out


## The batch a chip of `shape` is drawn in.
func batch_of(shape: String) -> FxBatch:
	return _batches[shape]


## A chip left the surface at `height` px (negative: the floor): it flies as its 2D node does.
func fly(chip: Node2D, height: float) -> void:
	if _flying.size() >= PhysicsMeshConfig.flying_room:
		return
	var piece := _take(chip)
	if piece == null:
		return
	piece.start_height = maxf(height, 0.0) * PhysicsMeshConfig.height_scale
	_follow(piece, chip)
	_flying.append(piece)
	_write(piece)


## The 2D `chip` came to rest: its piece lies where the chip does, from now on written no more. The
## oldest chip that lies goes past the cap, as in `DebrisLayer`.
func land(chip: Node2D) -> void:
	var piece := _flying_piece(chip)
	while _lying.size() >= _cap:
		_forget(_lying.pop())
	if piece == null:
		piece = _take(chip)
	if piece == null:
		return
	_follow(piece, chip)
	piece.age = piece.life
	_write(piece)
	_lying.append(piece)


## Move the chips in the air on (`delta` s): a chip whose node is gone (the `Despawner` took it)
## is gone too. True while any is still in the air.
func process(delta: float) -> bool:
	var i := _flying.size() - 1
	while i >= 0:
		var piece := _flying[i]
		var node: Variant = instance_from_id(piece.node_id)
		if not is_instance_valid(node):
			_flying[i] = _flying[_flying.size() - 1]
			_flying.pop_back()
			_forget(piece)
		else:
			piece.age += delta
			_follow(piece, node)
			_write(piece)
		i -= 1
	return not _flying.is_empty()


## The piece in the air that follows `chip`, taken out of the air (null when it has none).
func _flying_piece(chip: Node2D) -> FxPiece:
	var id := chip.get_instance_id()
	for i in _flying.size():
		if _flying[i].node_id == id:
			var piece := _flying[i]
			_flying.remove_at(i)
			return piece
	return null


## A piece of the batch of `chip`'s shape, set to its colour, size and life (null when the batch
## has no place: the one that lies and the one in the air are all it holds).
func _take(chip: Node2D) -> FxPiece:
	var batch: FxBatch = _batches.get(chip.chip_shape, _batches["circle"])
	var piece := batch.take(chip.color)
	if piece == null:
		return null
	piece.node_id = chip.get_instance_id()
	piece.size = chip.chip_size
	piece.life = maxf(chip.eject_time, 0.001)
	piece.age = 0.0
	piece.start_height = 0.0
	return piece


## The piece's place and turn are its 2D node's.
func _follow(piece: FxPiece, node: Node2D) -> void:
	piece.at = node.global_position
	piece.turn = node.global_rotation


## Give a piece's place back.
func _forget(piece: FxPiece) -> void:
	piece.batch.give(piece)


## Write the piece's frame: the node's place, its height along the arc, its turn, its size.
func _write(piece: FxPiece) -> void:
	var u := clampf(piece.age / piece.life, 0.0, 1.0)
	var arc := PhysicsMeshConfig.chip_arc * 4.0 * u * (1.0 - u)
	var lift := piece.start_height * (1.0 - u * u) + arc
	var base := PhysicsMeshConfig.rest_height + lift + _world.ground_at(piece.at)
	var scale := Vector3(piece.size.x, PhysicsMeshConfig.chip_thickness, piece.size.y)
	var basis := Basis(Vector3.UP, -piece.turn) * Basis.from_scale(scale)
	var origin := Vector3(piece.at.x, base, piece.at.y) * RenderConfig.unit
	piece.batch.place(piece, Transform3D(basis, origin))


## The mesh of a chip of `shape`, one px across and one tall (a chip scales it): a box, a prism on
## a triangle pointing up the 2D screen, or a disc of the kit's sides.
func _mesh(shape: String) -> Mesh:
	var key := MeshCache.key("chip", Vector2.ONE, Color.WHITE, { "shape": shape })
	return MeshCache.fetch(key, func() -> Mesh: return _solid(shape).build())


## The kit holding a chip of `shape`.
func _solid(shape: String) -> MeshKit:
	var kit := MeshKit.new()
	if shape == "rect":
		return kit.box(AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE), Color.WHITE)
	if shape == "tri":
		var corners := PackedVector2Array([
			Vector2(0.0, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5),
		])
		return kit.extrude(corners, 0.0, 1.0, Color.WHITE)
	return kit.cylinder(Vector3.ZERO, 0.5, 1.0, Color.WHITE)
