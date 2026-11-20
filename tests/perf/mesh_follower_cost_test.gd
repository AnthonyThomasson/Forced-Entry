extends GameTest
## Performance guard (#194 del2d-b3b): the follower of the drawn things that are no body costs no
## more than the mirror's own tracking of them did. 300 plain nodes of a group (a floor of stencils,
## with 40 lying items that are moved every frame) are shown by a `MeshFollower` and by a
## `WorldMirror` tracking the same group with the same builder; each frame both update, timed one
## after the other (the order alternates), so the machine's load is the same for both. The
## follower's mean update is at most the mirror's (80 % of it, the follower measuring about half),
## and it writes the moving ones only. The numbers print as `FOLLOWER` lines.

const NODES := 300
const MOVING := 40
const FRAMES := 240
const GROUP := &"follower_cost_probe"
## The most the follower's mean update may be of the mirror's (it measures about half: a follower
## as slow as the mirror fails).
const SHARE_OF_MIRROR := 0.8


func describe() -> Dictionary:
	return {
		"name": "The mesh follower costs no more than the mirror's tracking did",
		"description": "300 grouped nodes (40 of them moving) shown by a follower and by a mirror "
			+ "tracking the same group; the follower's update costs no more and it writes only "
			+ "the moving ones.",
		"tags": ["perf", "mirror", "render3d", "follower"],
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
	var drawers := _drawers(t, holder)
	await t.frames(2)
	for drawer: Node in drawers:
		drawer.update()
		t.check(drawer.count == NODES, "premise: it shows every node")
	var spent := await _measure(t, drawers, nodes)
	var follower_ms: float = spent[0] / FRAMES
	var mirror_ms: float = spent[1] / FRAMES
	print("FOLLOWER follower %.4f ms mirror %.4f ms (writes %d / %d)" % [
		follower_ms, mirror_ms, spent[2], spent[3],
	])
	t.expect_eq(spent[2], spent[3], "it writes as many meshes as the mirror: the moving ones")
	t.check(spent[2] > 0, "premise: the moving ones were written")
	var limit := mirror_ms * SHARE_OF_MIRROR
	t.check(
		follower_ms <= limit,
		"follower update %.4f ms <= %.4f ms (80 %% of the mirror's)" % [follower_ms, limit],
	)


## A follower and a mirror, in a world of their own, both showing the grouped nodes under `holder`;
## their own `_process` is off, the test updates them.
func _drawers(t: TestContext, holder: Node) -> Array[Node]:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var builder := func(_n: Node2D) -> Node3D: return Node3D.new()
	var follower := MeshFollower.new()
	var mirror := WorldMirror.new()
	view.add_child(follower)
	view.add_child(mirror)
	follower.track_group(GROUP, builder)
	mirror.track_group(GROUP, builder)
	follower.follow(holder)
	mirror.mirror(holder)
	follower.set_process(false)
	mirror.set_process(false)
	return [follower, mirror]


## `FRAMES` frames of both updating while the first `MOVING` nodes move, each timed apart (the order
## alternates): the follower's and the mirror's total ms, then what each wrote.
func _measure(t: TestContext, drawers: Array[Node], nodes: Array[Node2D]) -> Array:
	var out := [0.0, 0.0, 0, 0]
	for i in FRAMES:
		for n in MOVING:
			nodes[n].position.x += 0.5
		await t.frames(1)
		var order := [0, 1]
		if i % 2 == 1:
			order.reverse()
		for at: int in order:
			var from := Time.get_ticks_usec()
			drawers[at].update()
			out[at] += float(Time.get_ticks_usec() - from) / 1000.0
			out[2 + at] += drawers[at].written
	return out
