extends GameTest
## Despawner keeps the newest transient nodes up to its cap. Eviction queues the oldest node for
## deletion immediately, a lower cap applies on the next track as before, and the evicted node's
## later tree_exited signal must not erase a newer one. A node tracked twice is two entries, as it
## was in the array this replaced. Entries hold no reference cycle, so a store dropped with entries
## live returns its memory, and expiring many nodes leaves the store empty.

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
	_tracked_twice_is_two_entries(t)
	await _dropped_store_returns_its_memory(t)


## A stream below the cap, every node freeing itself: nothing is left tracked, however many came.
func _self_exits_stay_bounded(t: TestContext) -> void:
	var store: Node = DespawnerScript.new()
	t.world.add_child(store)
	for i in 5000:
		var node := Node.new()
		t.world.add_child(node)
		store.track(node)
		node.free()
	t.check(store.count() == 0, "every self-freed node dropped out")
	t.check(store.get(&"_fifo").is_empty() and store.get(&"_tickets").is_empty(),
		"self-exits retained no entries")
	store.free()


## The array this replaced held a node tracked twice as two entries: both counted, both evicted
## oldest first (the node is freed once), and its one exit dropped one entry, leaving a stale one
## that the next eviction passes over without freeing anything.
func _tracked_twice_is_two_entries(t: TestContext) -> void:
	var store: Node = DespawnerScript.new()
	t.world.add_child(store)
	store.max_scene_objects = 2
	var twice := Node.new()
	var other := Node.new()
	var newer := Node.new()
	for node in [twice, other, newer]:
		t.world.add_child(node)
	store.track(twice)
	store.track(twice)
	t.check(store.count() == 2, "a node tracked twice counts twice")
	store.track(other)
	t.check(store.count() == 2, "the third entry evicted the oldest entry")
	t.check(twice.is_queued_for_deletion() and not other.is_queued_for_deletion(),
		"the evicted entry was the first of the twice-tracked node")
	store.track(newer)
	t.check(store.count() == 2, "the fourth entry evicted the node's second entry")
	t.check(not other.is_queued_for_deletion() and not newer.is_queued_for_deletion(),
		"the entries evicted so far were both the twice-tracked node's")
	store.free()

	store = DespawnerScript.new()
	t.world.add_child(store)
	store.max_scene_objects = 2
	var gone := Node.new()
	var kept := Node.new()
	var last := Node.new()
	for node in [gone, kept, last]:
		t.world.add_child(node)
	store.track(gone)
	store.track(gone)
	gone.free()
	t.check(store.count() == 1, "one exit dropped one of the node's two entries")
	store.track(kept)
	store.track(last)
	t.check(store.count() == 2 and not kept.is_queued_for_deletion(),
		"the stale entry went first and freed nothing")
	store.free()
	kept.free()
	last.free()
	twice.free()
	other.free()
	newer.free()


## A store dropped with entries still live (a match torn down) must give them back: entries that
## pointed at one another would stay allocated for the rest of the run.
func _dropped_store_returns_its_memory(t: TestContext) -> void:
	var before := OS.get_static_memory_usage()
	var nodes: Array[Node] = []
	for i in 20_000:
		nodes.append(Node.new())
	var store: Node = DespawnerScript.new()
	t.world.add_child(store)
	store.max_scene_objects = 1_000_000
	for node in nodes:
		store.track(node)
	t.require(store.count() == nodes.size(), "the store tracks every node")
	var held := OS.get_static_memory_usage() - before
	store.free()
	for node in nodes:
		node.free()
	nodes.clear()
	await t.frames(1)
	var kept := OS.get_static_memory_usage() - before
	t.check(held > 2_000_000, "tracking 20,000 nodes takes memory (%d B)" % held)
	# entries left behind by cycles keep over 12 MB; the rest is other threads' allocations
	t.check(kept < 2_500_000, "a dropped store returns its entries (%d B kept)" % kept)
