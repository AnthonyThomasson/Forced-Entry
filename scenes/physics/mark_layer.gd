extends Node
## Physics System: the shared base of the mark layers (`DebrisLayer`, `ScorchDecals`,
## `BloodDecals`): one node under a world node holding every mark that came to rest as plain data,
## so a floor full of them costs no node each. It draws nothing: the 3D render shows what lies from
## the marks' own tells (`PhysicsFxHook`); the layer is the record, a capped FIFO (the oldest is
## dropped, and flagged `dead`, past a layer's cap). A layer supplies its marks' recipe and its cap.

## Every live mark in a global oldest-first FIFO.
var _marks := MarkQueue.new()


## The layer named `node_name` under `parent`, made from `script` on first use. Each parent has its
## own layer, freed with it.
static func _get_or_make(parent: Node, node_name: String, script: GDScript) -> Node:
	var found := parent.get_node_or_null(node_name)
	if found != null:
		return found
	var made: Node = script.new()
	made.name = node_name
	parent.add_child(made)
	return made


## Number of marks held.
func count() -> int:
	return _marks.size()


## Every mark still held (oldest first), as a list of the caller's own, for tests and tools.
func items() -> Array[Dictionary]:
	return _marks.items()


## File `mark` as the newest and drop the oldest past `cap`.
func _add(mark: Dictionary, cap: int) -> void:
	_marks.append(mark)
	while _marks.size() > cap:
		_marks.pop()["dead"] = true


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
