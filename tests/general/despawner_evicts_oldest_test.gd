extends GameTest
## Despawner keeps the newest transient nodes up to its cap. Eviction queues the oldest node for
## deletion immediately, a lower cap applies on the next track as before, and the evicted node's
## later tree_exited signal must not erase a newer one. The FIFO head proves oldest eviction;
## repeated self-exits must retain no entries after the last node leaves.

const DespawnerScript = preload("res://scenes/general/despawner.gd")
const CAP := 4


func describe() -> Dictionary:
	return {
		"name": "The despawner evicts its oldest tracked object",
		"description": "The newest nodes survive additions and cap reductions, self-removal keeps "
			+ "the count exact, and an evicted node's exit cannot remove a newer node.",
		"tags": ["despawner", "cap", "eviction"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 300, 200))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var store: Node = DespawnerScript.new()
	t.world.add_child(store)
	store.max_scene_objects = CAP
	var nodes: Array[Node] = []
	for i in CAP + 2:
		var node := Node.new()
		t.world.add_child(node)
		nodes.append(node)
		store.track(node)
	t.check(store.count() == CAP, "adding past the cap enforced it immediately")
	t.check(is_instance_valid(nodes[0]) and nodes[0].is_queued_for_deletion(),
		"the oldest node was queued for deletion")
	t.check(is_instance_valid(nodes[1]) and nodes[1].is_queued_for_deletion(),
		"the next-oldest node was queued for deletion")
	var head: Variant = store.get(&"_head")
	t.check(head is Dictionary and head.get("node") == nodes[2],
		"oldest eviction advanced the FIFO head")
	nodes[2].free()
	t.check(store.count() == CAP - 1, "a node leaving on its own dropped out of the count")
	store.max_scene_objects = 2
	t.check(store.count() == 3, "lowering the cap alone kept the old deferred enforcement")
	var newest := Node.new()
	t.world.add_child(newest)
	nodes.append(newest)
	store.track(newest)
	t.check(store.count() == 2, "the next track enforced the lower cap")
	t.check(nodes[3].is_queued_for_deletion()
			and nodes[4].is_queued_for_deletion()
			and not nodes[5].is_queued_for_deletion()
			and not newest.is_queued_for_deletion(),
		"the lower cap evicted the oldest and kept the newest two")
	await t.frames(2)
	t.check(store.count() == 2, "late exits from already evicted nodes changed nothing")
	store.free()
	_self_exits_stay_bounded(t)


## A stream below the cap still compacts consumed slots as every node frees itself.
func _self_exits_stay_bounded(t: TestContext) -> void:
	var store: Node = DespawnerScript.new()
	t.world.add_child(store)
	for i in 160:
		var node := Node.new()
		t.world.add_child(node)
		store.track(node)
		node.free()
	t.check(store.count() == 0, "every self-freed node dropped out")
	var head: Variant = store.get(&"_head")
	var tail: Variant = store.get(&"_tail")
	t.check(head is Dictionary and head.is_empty() and tail is Dictionary and tail.is_empty(),
		"self-exits retained no FIFO entries")
	store.free()
