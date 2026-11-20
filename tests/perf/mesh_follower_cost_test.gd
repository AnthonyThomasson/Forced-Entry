extends GameTest
## Performance guard (#194 del2d-b3b, del2d-b3c): the follower of the drawn things that are no body
## costs a frame what it did when the mirror it replaced was measured beside it. 300 plain nodes of
## a group (a floor of stencils, with 40 lying items that are moved every frame) are shown by a
## `MeshFollower`; each frame it updates, timed. Its mean update stays under `CEILING_MS` (the
## follower measured 0.48 ms on this load, the mirror's own tracking of the same nodes 0.95 ms
## before it was deleted), and it writes the moving ones only. The number prints as a `FOLLOWER`
## line.

const NODES := 300
const MOVING := 40
const FRAMES := 240
const GROUP := &"follower_cost_probe"
## The most the follower's mean update may be (ms): a third over the 0.48 ms it measured, and well
## under what tracking these nodes by a body mirror cost.
const CEILING_MS := 0.65


func describe() -> Dictionary:
	return {
		"name": "The mesh follower costs a frame no more than it did",
		"description": "300 grouped nodes (40 of them moving) shown by a follower; its update "
			+ "stays under its ceiling and it writes only the moving ones.",
		"tags": ["perf", "mesh-carrier", "render3d", "follower"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 400))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var holder := Node2D.new()
	t.world.add_child(holder)
	var nodes: Array[Node2D] = []
	for i in NODES:
		var node := Node2D.new()
		node.add_to_group(GROUP)
		holder.add_child(node)
		node.position = Vector2(i % 20, int(i / 20.0)) * 12.0
		nodes.append(node)
	var follower := _follower(t, holder)
	await t.frames(2)
	follower.update()
	t.check(follower.count == NODES, "premise: it shows every node")
	var spent := await _measure(t, follower, nodes)
	var follower_ms: float = spent[0] / FRAMES
	print("FOLLOWER follower %.4f ms (writes %d)" % [follower_ms, spent[1]])
	t.expect_eq(spent[1], MOVING * FRAMES, "it writes the moving ones only")
	t.check(
		follower_ms <= CEILING_MS,
		"follower update %.4f ms <= %.2f ms" % [follower_ms, CEILING_MS],
	)


## A follower in a view of its own, showing the grouped nodes under `holder`; its own `_process` is
## off, the test updates it.
func _follower(t: TestContext, holder: Node) -> MeshFollower:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var follower := MeshFollower.new()
	view.add_child(follower)
	follower.track_group(GROUP, func(_n: Node2D) -> Node3D: return Node3D.new())
	follower.follow(holder)
	follower.set_process(false)
	return follower


## `FRAMES` frames of the follower updating while the first `MOVING` nodes move, timed: its total ms
## and what it wrote.
func _measure(t: TestContext, follower: MeshFollower, nodes: Array[Node2D]) -> Array:
	var out := [0.0, 0]
	for i in FRAMES:
		for n in MOVING:
			nodes[n].position.x += 0.5
		await t.frames(1)
		var from := Time.get_ticks_usec()
		follower.update()
		out[0] += float(Time.get_ticks_usec() - from) / 1000.0
		out[1] += follower.written
	return out
