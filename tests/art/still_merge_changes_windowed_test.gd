extends GameTest
## A change to merged meshes is in the very frame it is made in, and the picture of it is the one
## each mesh drawing itself makes: the chunks keep no stale vertices, shadows or look. In a
## district, held still, walls are faded as the wall fade does (their shadows off), furniture is
## shoved aside, hidden and destroyed, after every script of the frame has run (a destroyed piece
## is freed after that, at the frame's end);
## that frame is compared with the same frame with every mesh drawing itself, and so is the frame in
## which the fade and the hiding are taken back. Windowed only. The allowance is the ties of
## `art/still_merge_same_picture_windowed`.

const Frozen := preload("res://tests/_render/frozen_frame.gd")
const TIES := 512
## How many of each kind of thing are changed, nearest the middle of the view first.
const CHANGED := 6

## The walls' shadows, switched as the wall fade does.
var _shadows := FadeShadow.new()


func describe() -> Dictionary:
	return {
		"name": "A change to merged meshes shows in its own frame, with no stale picture",
		"description": "Merged walls faded, pieces shoved, hidden and destroyed show at once, as "
			+ "with every mesh drawing itself. Windowed only.",
		"tags": ["art", "render", "3d"],
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.district(4)
	s.switch(&"nav.rebake", false)
	s.lock_interaction([&"camera"])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var view := Frozen.view(t)
	var original := DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(1152, 648))
	await _drive(t, view)
	# on every way out: the world runs again and the window is as it was
	DisplayServer.window_set_size(original)
	Frozen.release(t)


## The changes and their taking back, each held against the same view drawn unmerged.
func _drive(t: TestContext, view: CanvasLayer) -> void:
	await t.seconds(5.0)
	await Frozen.hold(t, view, 0.2)
	var merge: StillMerge = view.carrier.merge
	merge.enabled = true
	merge.build_all()
	var middle := t.world.get_viewport().get_camera_2d().global_position
	var walls := _walls(view, merge, middle)
	var pieces := _pieces(view, merge, middle)
	if not t.require(
		walls.size() == CHANGED and pieces.size() == CHANGED * 3,
		"premise: walls and pieces in view are merged (%d, %d)" % [walls.size(), pieces.size()],
	):
		return
	var parts: Array[GeometryInstance3D] = []
	parts.assign(walls)
	_shadows.remember(parts)
	if not await _changed(t, view, walls, pieces):
		return
	await _restored(t, view, walls, pieces)


## Fade the walls and shove, hide and destroy pieces in one frame; false if nothing showed.
func _changed(t: TestContext, view: CanvasLayer, walls: Array, pieces: Array) -> bool:
	var before := await Frozen.picture(t)
	var changed := await _late_frame(t, _change.bind(view, walls, pieces))
	var settled := await Frozen.picture(t)
	var shown := Frozen.differing(before, settled)
	if not t.require(shown > TIES * 4, "premise: the changes show (%d pixels)" % shown):
		return false
	await _compare(t, view.carrier.merge, changed, settled, "changed")
	return true


## The first third of `pieces` shoved, the next hidden, the last destroyed; the walls faded.
func _change(view: CanvasLayer, walls: Array, pieces: Array) -> void:
	_fade(walls, 0.25, false)
	for i in CHANGED:
		var twin := TwinSpace.twin_for(pieces[i]) as Node3D
		twin.global_position += Vector3(23.0, 0.0, 17.0)
		# the carrier hides a hidden body's mesh in its own pass: the mesh at once here
		(pieces[CHANGED + i] as Node2D).visible = false
		view.carrier.mesh_of(pieces[CHANGED + i]).visible = false
		var destroyed := pieces[CHANGED * 2 + i] as Node
		view.carrier.mesh_of(destroyed).queue_free()
		destroyed.queue_free()


## Merge everything again as it is now with the walls faded, then take the fade and the hiding
## back: the walls return to their chunks in that frame.
func _restored(t: TestContext, view: CanvasLayer, walls: Array, pieces: Array) -> void:
	var merge: StillMerge = view.carrier.merge
	merge.release()
	merge.enabled = true
	for node: Node in view.carrier.find_children("*", "MeshInstance3D", true, false):
		merge.offer(node)
	for body: Node2D in TwinSpace.of_world(t.world).bodies():
		var mesh: Node3D = view.carrier.mesh_of(body)
		if mesh != null:
			merge.offer(mesh)
	_fade(walls, 1.0, true)
	for i in CHANGED:
		(pieces[CHANGED + i] as Node2D).visible = true
	await Frozen.picture(t)
	merge.enabled = true
	merge.build_all()
	_fade(walls, 0.25, false)
	await Frozen.picture(t)
	var restored := await _late_frame(t, _fade.bind(walls, 1.0, true))
	await _compare(t, merge, restored, await Frozen.picture(t), "restored")


## Make `change` after every script of the next frame has run and give that frame's picture.
func _late_frame(t: TestContext, change: Callable) -> Image:
	var late := Late.new()
	late.change = change
	t.world.add_child(late)
	await late.done
	late.queue_free()
	await Frozen.drawn(t.world.get_tree())
	var image := t.world.get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image


## `at_once` (the frame the change was made in) and `settled` against the same view with every
## mesh drawing itself.
func _compare(
	t: TestContext, merge: StillMerge, at_once: Image, settled: Image, label: String
) -> void:
	merge.enabled = false
	merge.release()
	var apart := await Frozen.picture(t)
	var first := Frozen.differing(at_once, apart)
	var later := Frozen.differing(settled, apart)
	print("STILL ", label, " first frame differs ", first, " settled ", later)
	t.check(first <= TIES, "%s: its own frame shows it (%d pixels differ)" % [label, first])
	t.check(later <= TIES, "%s: nothing stale stays (%d pixels differ)" % [label, later])
	var dir := OS.get_environment("STILL_MERGE_SHOTS")
	if dir != "":
		at_once.save_png("%s/%s_first.png" % [dir, label])
		apart.save_png("%s/%s_apart.png" % [dir, label])


## What the wall fade writes: the dither, and past half faded no shadow (`FadeShadow`).
func _fade(parts: Array, amount: float, casting: bool) -> void:
	var cast: Array[GeometryInstance3D] = []
	cast.assign(parts)
	_shadows.apply(cast, casting)
	for part: MeshInstance3D in parts:
		MeshNodes.fade(part, amount)


## The `CHANGED` merged wall segments nearest `middle`.
func _walls(view: CanvasLayer, merge: StillMerge, middle: Vector2) -> Array:
	var out: Array = []
	for body: Node2D in _near(view, middle):
		var mesh := view.carrier.mesh_of(body) as WallMesh
		if mesh == null:
			continue
		for part: MeshInstance3D in mesh.segments().values():
			if merge.shows(part) and out.size() < CHANGED:
				out.append(part)
	return out


## The `CHANGED * 3` merged pieces of furniture nearest `middle`, their bodies.
func _pieces(view: CanvasLayer, merge: StillMerge, middle: Vector2) -> Array:
	var out: Array = []
	for body: Node2D in _near(view, middle):
		var rig := view.carrier.mesh_of(body) as FurnitureRig
		if rig != null and merge.shows(rig.body) and TwinSpace.twin_for(body) != null:
			out.append(body)
			if out.size() == CHANGED * 3:
				break
	return out


## The twinned bodies, nearest `middle` first.
func _near(view: CanvasLayer, middle: Vector2) -> Array:
	var bodies: Array = []
	for body: Node2D in TwinSpace.of_world(view.get_parent()).bodies():
		bodies.append(body)
	bodies.sort_custom(
		func(a: Node2D, b: Node2D) -> bool:
			return (
				a.global_position.distance_squared_to(middle)
				< b.global_position.distance_squared_to(middle)
			)
	)
	return bodies


## A node that runs after the merger's own pass and makes the change then.
class Late:
	extends Node

	signal done

	var change := Callable()

	func _init() -> void:
		process_priority = StillMerge.LAST + 1
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		set_process(false)
		change.call()
		done.emit()
