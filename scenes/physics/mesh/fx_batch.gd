class_name FxBatch
extends RefCounted
## Physics domain, a batch of one mesh whose parts are pieces (`FxPiece`) with a colour each: the
## places of one `MeshNodes.batch` in a `MeshPool` (Art), so a chip or a bit takes a place and
## gives it back and no node, mesh or piece is made while the game runs. A part that leaves is
## replaced by the last one, which brings its frame (the pool keeps it) and its colour (kept here).
## The pieces in use are the first `count()` places, all drawn.

## The batch: the owner adds it to the 3D world.
var node: MultiMeshInstance3D
## How many times a frame was written (a test reads it: a thing at rest writes nothing).
var writes := 0
var _pool: MeshPool
var _free: Array[FxPiece] = []


## A batch of `places` parts of `mesh`, lit as the toon material lights, or (`glow` with a
## strength above 0) glowing that colour whatever the light.
func _init(mesh: Mesh, places: int, glow := Color.BLACK, strength := 0.0) -> void:
	node = MeshNodes.batch(mesh, places, Color.WHITE, false, true)
	if strength > 0.0:
		MeshNodes.glow(node, glow, strength)
	_pool = MeshPool.new(node)
	_free.resize(places)
	for i in places:
		_free[i] = FxPiece.new()


## How many parts are shown, and how many the batch holds at most.
func count() -> int:
	return _pool.count


## How many parts the batch holds at most.
func capacity() -> int:
	return _pool.capacity()


## A piece in a place of its own, in `color`, or null when the batch is full.
func take(color: Color) -> FxPiece:
	if _free.is_empty():
		return null
	var piece: FxPiece = _free.pop_back()
	var slot := _pool.add(piece)
	piece.batch = self
	piece.color = color
	MeshNodes.batch_color(node, slot, color)
	return piece


## `piece`'s place is free again, and the piece is ready to be taken (the piece of a batch it is
## not in, or one already given back, is ignored).
func give(piece: FxPiece) -> void:
	if piece.batch != self:
		return
	var slot := _pool.slot_of(piece)
	_pool.remove(piece)
	if slot < _pool.count:
		var moved := _pool.owner_at(slot) as FxPiece
		MeshNodes.batch_color(node, slot, moved.color)
	piece.batch = null
	_free.append(piece)


## Put `piece` at `frame` (3D units).
func place(piece: FxPiece, frame: Transform3D) -> void:
	writes += 1
	_pool.place(_pool.slot_of(piece), frame)


## The frame (3D units) of `piece`.
func frame_of(piece: FxPiece) -> Transform3D:
	return _pool.frame_at(_pool.slot_of(piece))


## The piece in `slot`.
func piece_at(slot: int) -> FxPiece:
	return _pool.owner_at(slot) as FxPiece
