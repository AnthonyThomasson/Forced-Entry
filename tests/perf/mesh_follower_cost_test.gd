extends GameTest
## Performance guard (#194): the follower of the drawn things that are no body
## costs a frame what it did when the mirror it replaced was measured beside it. 300 plain nodes of
## a group (a floor of stencils, with 40 lying items that are moved every frame) are shown by a
## `MeshFollower`; each frame it updates, timed beside a fixed reference loop
## (`tests/_perf/perf_reference.gd`). Its update stays under `CEILING_RATIO` times that loop, about
## 4x the 1.35 it measures (0.48 ms; the mirror's own tracking of the same nodes cost 0.95 ms
## before it was deleted), and it writes the moving ones only. The number prints as a `FOLLOWER`
## line.

const Reference := preload("res://tests/_perf/perf_reference.gd")
const NODES := 300
const MOVING := 40
const FRAMES := 240
const GROUP := &"follower_cost_probe"
## The most the follower's update may cost, as a multiple of the reference loop timed in the same
## frames (`perf_reference.gd`): a load slows both, so the ratio holds under it.
const CEILING_RATIO := 5.5


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
	var ratio: float = spent[0] / maxf(spent[2], 0.001)
	print("FOLLOWER follower %.4f ms (x%.2f) (writes %d)" % [follower_ms, ratio, spent[1]])
	t.expect_eq(spent[1], MOVING * FRAMES, "it writes the moving ones only")
	t.check(
		ratio <= CEILING_RATIO,
		"follower update %.2f times the reference loop <= %.1f" % [ratio, CEILING_RATIO],
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
	var out := [0.0, 0, 0.0]
	var ref_loop := Reference.new()
	for i in FRAMES:
		for n in MOVING:
			nodes[n].position.x += 0.5
		await t.frames(1)
		var from := Time.get_ticks_usec()
		follower.update()
		out[0] += float(Time.get_ticks_usec() - from) / 1000.0
		out[1] += follower.written
		out[2] += ref_loop.time_ms()
	ref_loop.release()
	return out
