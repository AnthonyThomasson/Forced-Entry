extends GameTest
## MarkLayer's cap is one global oldest-first FIFO. Evicting a mark drops that exact mark, flags it
## dead and leaves every newer mark in order; the lists `items` returns are the caller's own, and
## the FIFO's head advances instead of the array being erased from the front.

const LayerScript = preload("res://scenes/physics/mark_layer.gd")
const CAP := 5
const MARKS := 9


func describe() -> Dictionary:
	return {
		"name": "Mark layer evicts the oldest mark",
		"description": "The capped layer retains the newest marks in order, flags the evicted "
			+ "ones dead, and advances a constant-time FIFO cursor.",
		"tags": ["decals", "cap", "eviction"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 300, 200))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var layer: Node = LayerScript.new()
	t.world.add_child(layer)
	var all: Array = []
	for i in MARKS:
		var mark := { "id": i }
		all.append(mark)
		layer.call(&"_add", mark, CAP)
	t.check(_ids(layer) == [4, 5, 6, 7, 8], "only the newest marks remain, oldest first")
	t.check(layer.count() == CAP, "the mark count equals the cap")
	for i in 4:
		t.check(all[i].get("dead", false), "mark %d, one of the oldest, was flagged dead" % i)
	t.check(not all[4].get("dead", false), "the oldest kept mark is not flagged dead")
	var queue: Variant = layer.get(&"_marks")
	var head: Variant = queue.get(&"_oldest") if queue is Object else null
	t.check(head != null and head >= 4, "the FIFO cursor advanced")
	_lists_are_the_callers(t, layer)


## The list `items` returns is the caller's: emptying it leaves the layer whole, and a list read
## before a change keeps what it held (a snapshot, never a live view).
func _lists_are_the_callers(t: TestContext, layer: Node) -> void:
	var all: Array = layer.items()
	all.clear()
	t.check(_ids(layer) == [4, 5, 6, 7, 8], "emptying a returned list left the layer's marks")
	var held: Array = layer.items()
	layer.call(&"_add", { "id": 9 }, CAP)
	t.check(held.size() == CAP and held[CAP - 1]["id"] == 8, "a list read earlier kept its marks")
	t.check(_ids(layer) == [5, 6, 7, 8, 9], "the next read has the new mark and not the evicted")


func _ids(layer: Node) -> Array:
	var ids: Array = []
	for mark in layer.items():
		ids.append(mark["id"])
	return ids
