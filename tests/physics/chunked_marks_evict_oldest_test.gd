extends GameTest
## ChunkedLayer's cap is one global oldest-first FIFO, shared across spatial chunks. Evicting a mark
## removes that exact mark from its own chunk, marks it dead and leaves every newer mark in order.
## Cursor observables prove both the global and per-chunk removals advance instead of array-erasing.

const LayerScript = preload("res://scenes/physics/chunked_layer.gd")
const CAP := 5
const MARKS := 9


func describe() -> Dictionary:
	return {
		"name": "Chunked marks evict oldest across chunks",
		"description": "The capped layer retains the newest marks in global order, removes evicted "
			+ "marks from their draw chunks, and advances constant-time FIFO cursors.",
		"tags": ["decals", "cap", "eviction"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 300, 200))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var layer: Node = ProbeLayer.new()
	t.world.add_child(layer)
	for i in MARKS:
		var cell := Vector2i(i % 3, 0)
		layer.call(&"_add", { "chunk": cell, "id": i }, CAP)
	var ids: Array = []
	for mark in layer.items():
		ids.append(mark["id"])
	t.check(ids == [4, 5, 6, 7, 8], "only the newest marks remain, oldest first")
	t.check(layer.count() == CAP, "the global mark count equals the cap")
	t.check(_ids(layer, Vector2i(1, 0)) == [4, 7], "the first chunk lost its older marks")
	t.check(_ids(layer, Vector2i(2, 0)) == [5, 8], "the second chunk lost its older marks")
	t.check(_ids(layer, Vector2i(0, 0)) == [6], "the third chunk kept only its newest mark")
	t.check(layer.dropped.size() == 4, "four oldest marks were dropped")
	var dropped := true
	for i in 4:
		t.check(layer.dropped[i]["id"] == i, "drop %d was the next-oldest mark" % i)
		dropped = dropped and layer.dropped[i].get("dead", false)
	t.check(dropped, "every evicted mark was flagged dead")
	var queue: Variant = layer.get(&"_marks")
	var global_head: Variant = queue.get(&"_oldest") if queue is Object else null
	t.check(global_head != null and global_head >= 4, "the global FIFO cursor advanced")
	var chunks: Dictionary = layer.get(&"_by_chunk")
	var chunk: Variant = chunks[Vector2i(1, 0)]
	var chunk_head: Variant = chunk.get(&"_oldest") if chunk is Object else null
	t.check(chunk_head != null and chunk_head >= 1, "the chunk FIFO cursor advanced")
	_lists_are_the_callers(t, layer)


## The lists `items` and `marks_in` return are the caller's: emptying one leaves the layer whole,
## and a list read before a change keeps what it held (it is a snapshot, never a live view).
func _lists_are_the_callers(t: TestContext, layer: Node) -> void:
	var all: Array = layer.items()
	var chunk_list: Array = layer.marks_in(Vector2i(1, 0))
	all.clear()
	chunk_list.clear()
	t.check(_all_ids(layer) == [4, 5, 6, 7, 8], "emptying a returned list left the layer's marks")
	t.check(_ids(layer, Vector2i(1, 0)) == [4, 7], "emptying a chunk's list left its marks")
	var held: Array = layer.items()
	layer.call(&"_add", { "chunk": Vector2i(1, 0), "id": 9 }, CAP)
	t.check(held.size() == CAP and held[CAP - 1]["id"] == 8, "a list read earlier kept its marks")
	t.check(
		_all_ids(layer) == [5, 6, 7, 8, 9],
		"the next read has the new mark and not the evicted",
	)
	t.check(_ids(layer, Vector2i(1, 0)) == [7, 9], "and so has the chunk's list")


func _all_ids(layer: Node) -> Array:
	var ids: Array = []
	for mark in layer.items():
		ids.append(mark["id"])
	return ids


func _ids(layer: Node, cell: Vector2i) -> Array:
	var ids: Array = []
	for mark in layer.marks_in(cell):
		ids.append(mark["id"])
	return ids


## Observes the existing eviction callback without changing how marks are filed or drawn.
class ProbeLayer extends LayerScript:
	var dropped: Array[Dictionary] = []

	func _mark_dropped(cell: Vector2i, mark: Dictionary) -> void:
		super(cell, mark)
		dropped.append(mark)
