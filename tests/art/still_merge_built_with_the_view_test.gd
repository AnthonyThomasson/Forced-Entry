extends GameTest
## The still world's chunks are built as the view is built (`View3D.light_world`, interface 27), as
## the toon atlas is warmed, and never after: a mesh offered later, or one that moved and came to
## rest, draws itself. A door's and a vehicle's meshes are in none. A view whose merger is off
## builds none and takes no mesh to build later.

const ViewScript := preload("res://scenes/main_view3d.gd")
const TABLES: Array[StringName] = [&"table0", &"table1", &"table2", &"table3", &"table4"]
const HINGE := Vector2(400, 280)
## Frames long enough for a shoved table to rest and for anything waiting to be taken.
const LATER := 240


func describe() -> Dictionary:
	return {
		"name": "The still world's chunks are built with the view, none after it",
		"description": "Right after the view is built and lit the chunks hold the still world; "
			+ "no chunk is built in play, whatever moves or is offered; doors and vehicles are in "
			+ "none; with merging off none is built or offered.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 600) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 600) },
	], [{
		"pos": Vector2(400, 300), "width": 52.0,
		"door": {
			"name": "swing", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])
	for i in TABLES.size():
		s.object(TABLES[i], "table", Vector2(70 + 65 * i, 100 + 90 * (i % 2)))
	s.vehicle(&"car", &"car", Vector2(600, 450))
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(2.0)
	var camera := Camera2D.new()
	camera.position = Vector2(400, 300)
	t.world.add_child(camera)
	camera.make_current()
	var view := _view(t, camera, true)
	var merge: StillMerge = view.carrier.merge
	var built := merge.chunks().duplicate()
	if not t.require(not built.is_empty(), "the chunks are built before the first frame"):
		return
	for id in TABLES:
		t.check(merge.shows(_body(view, t.object(id))), "%s is in a chunk at once" % id)
	_never_merged(t, view, t.object(&"swing"), "the door")
	_never_merged(t, view, t.vehicle(&"car"), "the car")
	await _in_play(t, view, built)
	view.queue_free()
	await t.frames(2)
	var off := _view(t, camera, false)
	t.check(off.carrier.merge.chunks().is_empty(), "with merging off no chunk is built")
	off.carrier.merge.enabled = true
	off.carrier.merge.build_all()
	t.expect_eq(off.carrier.merge.held(), 0, "and no mesh offered meanwhile was taken")
	off.queue_free()


## None of the meshes `body` is shown by is in a chunk.
func _never_merged(t: TestContext, view: CanvasLayer, body: Node, label: String) -> void:
	var mesh: Node3D = view.carrier.mesh_of(body)
	if not t.require(mesh != null, "premise: %s is carried" % label):
		return
	var parts := mesh.find_children("*", "MeshInstance3D", true, false)
	t.require(not parts.is_empty(), "premise: %s has meshes" % label)
	t.check(
		not parts.any(view.carrier.merge.shows),
		"no mesh of %s is in a chunk" % label,
	)


## A table shoved to rest elsewhere and every mesh offered again: no chunk is built after the
## view's, and the table draws itself.
func _in_play(t: TestContext, view: CanvasLayer, built: Array) -> void:
	var merge: StillMerge = view.carrier.merge
	var table := t.object(TABLES[0]) as Node2D
	var mesh := _body(view, table)
	var from := table.global_position
	Knockback.push(table, Vector2(0.0, 4000.0))
	await t.frames(LATER)
	if not t.require(table.global_position.distance_to(from) > 2.0, "premise: the shove moved it"):
		return
	t.require(
		(TwinSpace.twin_for(table) as RigidBody3D).sleeping, "premise: it came to rest again"
	)
	var held := merge.held()
	for body: Node2D in TwinSpace.of_world(t.world).bodies():
		var carried: Node3D = view.carrier.mesh_of(body)
		if carried != null:
			merge.offer(carried)
	await t.frames(LATER)
	t.check(
		merge.chunks().all(func(chunk: MergeChunk) -> bool: return chunk in built),
		"no chunk is built in play (%d, %d with the view)" % [merge.chunks().size(), built.size()],
	)
	t.expect_eq(merge.held(), held, "and no mesh is taken")
	t.check(not merge.shows(mesh), "the moved table draws itself")


## The solids' node of the piece `body`.
func _body(view: CanvasLayer, body: Node) -> MeshInstance3D:
	return (view.carrier.mesh_of(body) as FurnitureRig).body


## A view of the test's world, lit, its merger on or off.
func _view(t: TestContext, camera: Camera2D, merging: bool) -> CanvasLayer:
	var view: CanvasLayer = ViewScript.new()
	t.world.add_child(view)
	view.begin(camera)
	view.carrier.merge.enabled = merging
	view.mirror_world(t.world)
	view.light_world(t.world, 1, t.world.rooms)
	return view
