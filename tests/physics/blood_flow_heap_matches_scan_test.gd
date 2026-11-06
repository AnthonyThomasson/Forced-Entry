extends GameTest
## BloodFlow claims its frontier cheapest-first. The heap must preserve the linear scan's exact
## (cell, cost) claim sequence, including dictionary insertion order for ties and lazy entries left
## by a lower-cost update. Real seeded flows run beside the scan; a small frontier fixture forces
## ties and a decrease-key. The blocked-cell query parameters are retained across steps.

const FLOWS := 10
const BATCHES := 36


func describe() -> Dictionary:
	return {
		"name": "The blood-flow heap matches the linear frontier scan",
		"description": "Seeded pool claims equal the scan in order and cost; explicit ties and a "
			+ "cost decrease preserve insertion ordering, and blocked-cell query storage is "
			+ "reused.",
		"tags": ["blood", "flow", "heap"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", Vector2(225, 165))


func run(t: TestContext) -> void:
	await t.frames(2)
	var differing: Array[int] = []
	var reused_query := false
	for i in FLOWS:
		var at := Vector2(180 + (i % 3) * 15, 130 + (i % 4) * 12)
		var aim := Vector2.from_angle(i * 0.7)
		seed(192_016 + i)
		var fast := BloodFlow.new(aim, [])
		seed(192_016 + i)
		var plain := ScanFlow.new(aim, [])
		var collision: Object = fast.get(&"_collision")
		var query: Object = collision.get(&"params") if collision != null else null
		for batch in BATCHES:
			fast.step(6, t.world.get_world_2d().direct_space_state, at, 180.0)
			plain.step(6, t.world.get_world_2d().direct_space_state, at, 180.0)
			if _claims(fast) != _claims(plain):
				differing.append(i)
				break
		if i == 0 and collision != null:
			query = collision.get(&"params")
			fast.step(6, t.world.get_world_2d().direct_space_state, at, 180.0)
			reused_query = query != null and collision.get(&"params") == query
	t.check(differing.is_empty(), "flows differing from the linear scan: %s" % str(differing))
	t.check(reused_query, "the blocked-cell query parameters were retained across steps")
	_frontier_edges(t)


func _claims(flow: BloodFlow) -> Array:
	var out: Array = []
	for cell in flow.cells:
		out.append([cell, flow.cells[cell]])
	return out


## Force cases a random flow may not produce: equal costs pop in insertion order, and a cheaper
## replacement leaves a stale heap entry. The decrease lands on a later cell's exact cost, proving
## the earlier insertion sequence breaks that tie too.
func _frontier_edges(t: TestContext) -> void:
	var script: Variant = BloodFlow.new(
		Vector2.ZERO,
		[],
	).get_script().get_script_constant_map().get(
		&"Frontier",
	)
	if not t.require(script != null, "BloodFlow has an ordered frontier heap"):
		return
	var heap: Object = script.new()
	var a := Vector2i(1, 0)
	var b := Vector2i(2, 0)
	var c := Vector2i(3, 0)
	var d := Vector2i(4, 0)
	heap.set_cost(a, 5.0)
	heap.set_cost(b, 5.0)
	heap.set_cost(c, 9.0)
	heap.set_cost(d, 1.0)
	heap.set_cost(c, 1.0)
	t.check(heap.pop() == c, "the decreased cost wins its tie by first insertion")
	heap.erase(c)
	t.check(heap.pop() == d, "the later-inserted equal-cost cell follows")
	heap.erase(d)
	t.check(heap.pop() == a, "the first inserted equal-cost cell wins")
	heap.erase(a)
	t.check(heap.pop() == b, "the second equal-cost cell follows")
	heap.erase(b)
	t.check(heap.is_empty(), "stale entries leave no frontier cell")


## Reference path: the original strict-< dictionary scan, with newest-first replacement semantics
## unchanged. It works against both the old dictionary and the new Frontier's public cost map.
class ScanFlow extends BloodFlow:
	func _pop_cheapest() -> Vector2i:
		var store: Variant = _frontier
		var costs: Dictionary = store if store is Dictionary else store.costs
		var best := Vector2i.ZERO
		var best_cost := INF
		for cell in costs:
			if costs[cell] < best_cost:
				best_cost = costs[cell]
				best = cell
		return best
