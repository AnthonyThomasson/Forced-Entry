extends Node2D
## Physics System: the shared base of the batched decal layers (`DebrisLayer`, `ScorchDecals`,
## `BloodDecals`): one node under a world node holding every mark as plain data, drawn by a few
## chunk nodes instead of one node each. Marks are grouped in `CHUNK`-px squares and only the chunk
## that gained or lost one redraws; past a layer's cap the oldest is dropped (and flagged `dead`). A
## layer supplies its marks' recipe, its cap and its chunk node (`_make_chunk`), whose `_draw` reads
## `marks_in` its cell.

## Side (px) of a chunk.
const CHUNK := 128.0

## Every live mark in a global oldest-first FIFO.
var _marks := MarkQueue.new()
## chunk cell -> that chunk's oldest-first mark FIFO.
var _by_chunk: Dictionary = {}
## chunk cell -> its drawing node.
var _chunks: Dictionary = {}


## The layer named `node_name` under `parent`, made from `script` (at `z` z-index) on first use.
## Each parent has its own layer, freed with it.
static func _get_or_make(parent: Node, node_name: String, script: GDScript, z: int = 0) -> Node:
	var found := parent.get_node_or_null(node_name)
	if found != null:
		return found
	var made: Node2D = script.new()
	made.name = node_name
	made.z_index = z
	parent.add_child(made)
	return made


## Number of marks held.
func count() -> int:
	return _marks.size()


## Every mark still held (oldest first), as a list of the caller's own, for tests and tools.
func items() -> Array[Dictionary]:
	return _marks.items()


## The live marks chunk `cell` draws, oldest first, as a list of the caller's own.
func marks_in(cell: Vector2i) -> Array:
	return _by_chunk[cell].items() if _by_chunk.has(cell) else []


## File `mark` (its `chunk` cell already set) as the newest and drop the oldest past `cap`, telling
## the layer of each (`_mark_added`, `_mark_dropped`).
func _add(mark: Dictionary, cap: int) -> void:
	_marks.append(mark)
	var cell: Vector2i = mark["chunk"]
	if not _by_chunk.has(cell):
		_by_chunk[cell] = MarkQueue.new()
	(_by_chunk[cell] as MarkQueue).append(mark)
	_mark_added(cell, mark)
	while _marks.size() > cap:
		var old := _marks.pop()
		old["dead"] = true
		var old_cell: Vector2i = old["chunk"]
		(_by_chunk[old_cell] as MarkQueue).pop()
		_mark_dropped(old_cell, old)


## The chunk grid cell containing world `pos`.
func _chunk_cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CHUNK).floor())


## The draw chunk for `cell`, created on first use.
func _chunk_node(cell: Vector2i) -> Node2D:
	if not _chunks.has(cell):
		var node := _make_chunk(cell)
		add_child(node)
		_chunks[cell] = node
	return _chunks[cell]


## `mark` was filed in `cell`: its chunk redraws. A layer may repaint less.
func _mark_added(cell: Vector2i, _mark: Dictionary) -> void:
	_chunk_node(cell).queue_redraw()


## `mark`, the oldest of `cell` (marks go oldest first), was dropped: its chunk redraws. A layer may
## repaint less.
func _mark_dropped(cell: Vector2i, _mark: Dictionary) -> void:
	if _chunks.has(cell):
		(_chunks[cell] as Node).queue_redraw()


## A new, not yet added draw chunk for `_cell`; each layer returns its own.
func _make_chunk(_cell: Vector2i) -> Node2D:
	return Node2D.new()


## A FIFO with an advancing head instead of front-popping or erasing. The consumed prefix is folded
## away only occasionally, so append and eviction are amortized constant time and storage stays
## bounded under sustained mark churn.
class MarkQueue extends RefCounted:
	## Live marks and the consumed prefix.
	var _marks: Array[Dictionary] = []
	## First live slot.
	var _oldest := 0
	## Current slot while GDScript iterates the live marks directly.
	var _iter := 0


	## File a mark as newest.
	func append(mark: Dictionary) -> void:
		_marks.append(mark)


	## Remove and return the oldest mark.
	func pop() -> Dictionary:
		var mark := _marks[_oldest]
		_marks[_oldest] = {}
		_oldest += 1
		_compact()
		return mark


	## Number of live marks.
	func size() -> int:
		return _marks.size() - _oldest


	## A copy of the live marks, oldest first: the caller's own list, which later changes do not
	## touch and which changing does not touch the queue.
	func items() -> Array[Dictionary]:
		return _marks.slice(_oldest)


	## Begin direct GDScript iteration at the oldest live mark.
	func _iter_init(_arg: Variant) -> bool:
		_iter = _oldest
		return _iter < _marks.size()


	## Advance direct iteration to the next live mark.
	func _iter_next(_arg: Variant) -> bool:
		_iter += 1
		return _iter < _marks.size()


	## The current mark of direct iteration.
	func _iter_get(_arg: Variant) -> Variant:
		return _marks[_iter]


	## Fold away a substantial consumed prefix, retaining live order.
	func _compact() -> void:
		if _oldest < 64 or _oldest * 2 < _marks.size():
			return
		_marks = _marks.slice(_oldest)
		_oldest = 0
