extends GameTest
## Every chunk of the still world is built as the view is built (`View3D.light_world`, interface
## 27), as the toon atlas is warmed: none is built in a played frame while nothing moves. What does
## wait in play (here: every mesh, let go and offered again) is built one chunk a frame at most, in
## chunks of `MirrorMergeConfig.play_vertices`. A view whose merger is off builds none.

const ViewScript := preload("res://scenes/main_view3d.gd")
const ARENA := Rect2(0, 0, 600, 400)
const PIECES := 5
## A chunk's size in play, small enough that the arena calls for several.
const PLAY_VERTICES := 100


func describe() -> Dictionary:
	return {
		"name": "The still world's chunks are built with the view, none in play",
		"description": "Right after the view is built and lit the chunks hold the still world, "
			+ "and no chunk is built in the frames that follow. With merging off none is.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(ARENA)
	for i in PIECES:
		s.object(StringName("table%d" % i), "table", Vector2(90 + 100 * i, 120))
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)
	s.set_static(MirrorMergeConfig, &"play_vertices", PLAY_VERTICES)


func run(t: TestContext) -> void:
	await t.frames(2)
	var camera := Camera2D.new()
	camera.position = ARENA.get_center()
	t.world.add_child(camera)
	camera.make_current()
	var view := _view(t, camera, true)
	var merge: StillMerge = view.carrier.merge
	var built := merge.chunks().duplicate()
	var held := merge.held()
	t.require(not built.is_empty(), "the chunks are built before the first frame")
	for i in PIECES:
		var rig := view.carrier.mesh_of(t.object(StringName("table%d" % i))) as FurnitureRig
		t.check(merge.shows(rig.body), "table %d is in a chunk at once" % i)
	# past the frames a mesh settles in and a whole round of the waiting ones
	await t.frames(MirrorMergeConfig.settle_frames + MirrorMergeConfig.round_frames * 2)
	t.check(merge.chunks() == built, "no chunk is built in play (%d)" % merge.chunks().size())
	t.expect_eq(merge.held(), held, "and nothing waited to join one")
	await _in_play(t, view, built.size())
	view.queue_free()
	await t.frames(2)
	var off := _view(t, camera, false)
	t.check(off.carrier.merge.chunks().is_empty(), "with merging off no chunk is built")
	off.queue_free()


## Every mesh let go and offered again, as ones that moved are: the chunks come one a frame at
## most, and smaller than the `at_build` the view was built with.
func _in_play(t: TestContext, view: CanvasLayer, at_build: int) -> void:
	var merge: StillMerge = view.carrier.merge
	merge.release()
	for body: Node2D in TwinSpace.of_world(t.world).bodies():
		var mesh: Node3D = view.carrier.mesh_of(body)
		if mesh != null:
			merge.offer(mesh)
	var most := 0
	var last := 0
	for i in MirrorMergeConfig.settle_frames + MirrorMergeConfig.round_frames * 3:
		await t.world.get_tree().process_frame
		most = maxi(most, merge.chunks().size() - last)
		last = merge.chunks().size()
	t.expect_eq(most, 1, "one chunk is built a frame at most")
	t.check(
		last > at_build,
		"in play the chunks are smaller than the build's (%d against %d)" % [last, at_build],
	)


## A view of the test's world, lit, its merger on or off.
func _view(t: TestContext, camera: Camera2D, merging: bool) -> CanvasLayer:
	var view: CanvasLayer = ViewScript.new()
	t.world.add_child(view)
	view.begin(camera)
	view.carrier.merge.enabled = merging
	view.mirror_world(t.world)
	view.light_world(t.world, 1, t.world.rooms)
	return view
