extends GameTest
## The picture is the same when the static classes carry their meshes on their twins as when each
## mesh is placed by hand from its 2D body (#194 del2d-b2, windowed only: the headless renderer
## draws nothing). A furnished house shown by Main's `View3D` with its lights, the picture read back
## (its walls, floors and anchored pieces carried by their twins); then every body and floor is
## shown by `FollowedBaseline` instead (the same mesh, off its twin, standing where the 2D body
## does), and the picture is read again in the same process, the same view and the same instant of
## the lights: the same pixels. Environment: `CARRY_SHOT=<dir>` saves both pictures. Run:
## `tools/run_tests.sh --windowed --id=general/twin_carried_picture_windowed`.

const MAIN_VIEW3D := preload("res://scenes/main_view3d.gd")
const Baseline := preload("res://tests/_art/art_followed_baseline.gd")
const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const SEEDS: Array[int] = [3, 7]
## Frames the picture settles for after the camera or the world is set.
const SETTLE := 20
## Pixels (of a 0 to 255 channel) a pixel may differ by, and how many of them may.
const TOLERANCE := 1
const MAX_DIFFERING := 0


func describe() -> Dictionary:
	return {
		"name": "The 3D picture is the same with carried meshes as with followed ones (windowed)",
		"description": "A furnished house drawn with its walls, floors and anchored pieces carried "
			+ "by their twins, then meshed again and followed by the mirror: the picture's pixels "
			+ "are the same. Windowed only.",
		"tags": ["render", "3d", "twins", "carriers", "windowed"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.house(SEEDS[0])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	await t.frames(2)
	var view := await _start_view(t)
	t.check(
		view.viewport.find_world_3d() == t.world.twin_space().find_world_3d(),
		"premise: the view draws the twins' world",
	)
	var carried := _carried(view.carrier, t.world)
	t.check(carried["wall"] > 0, "premise: the walls are carried (%d)" % carried["wall"])
	t.check(carried["floor"] > 0, "premise: the floors are carried (%d)" % carried["floor"])
	# the lights flicker: held still, the two pictures stand at the same instant of them
	view.lighting.process_mode = Node.PROCESS_MODE_DISABLED
	await t.frames(2)
	var on_twins := _picture(view)
	var again := _picture(view)
	t.check(_differing(on_twins, again) == 0, "premise: a picture of the same world holds still")
	var baseline := Baseline.new()
	view.viewport.add_child(baseline)
	var bodies := _static_bodies(t.world)
	t.expect_eq(
		baseline.show_followed(view.carrier, bodies), bodies.size(),
		"premise: every body is placed by hand",
	)
	await t.frames(SETTLE)
	t.expect_eq(
		_carried(view.carrier, t.world),
		{ "wall": 0, "floor": 0, "piece": 0 },
		"premise: nothing is carried any more",
	)
	var followed := _picture(view)
	_save(on_twins, followed)
	t.expect_eq(on_twins.get_size(), followed.get_size(), "the pictures are the same size")
	var differing := _differing(on_twins, followed)
	t.check(
		differing <= MAX_DIFFERING,
		"the picture is the same carried or followed (%d pixels differ)" % differing,
	)
	var tones := _tones(on_twins)
	t.check(tones >= 8, "premise: the picture holds a world (%d tones)" % tones)


## Main's 3D view of the house, lit, settled.
func _start_view(t: TestContext) -> MAIN_VIEW3D:
	var camera := Camera2D.new()
	camera.position = _middle(t.world.rooms)
	t.world.add_child(camera)
	camera.make_current()
	var view := MAIN_VIEW3D.new()
	t.world.add_child(view)
	view.begin(camera)
	view.mirror_world(t.world)
	view.light_world(t.world, SEEDS[0], t.world.rooms)
	t.world.visible = false
	await t.frames(SETTLE)
	return view


## Save the two pictures when `CARRY_SHOT` names a directory.
func _save(carried: Image, followed: Image) -> void:
	var dir := OS.get_environment("CARRY_SHOT")
	if dir != "":
		carried.save_png(dir.path_join("carried.png"))
		followed.save_png(dir.path_join("followed.png"))


## How many tones the picture holds, sampled every 8 pixels.
func _tones(picture: Image) -> int:
	var tones := {}
	for y in range(0, picture.get_height(), 8):
		for x in range(0, picture.get_width(), 8):
			tones[picture.get_pixel(x, y).to_html(false)] = true
	return tones.size()


## The bodies and floors whose twin is a static body: what carries its mesh.
func _static_bodies(world: Node) -> Array[Node2D]:
	var found: Array[Node2D] = []
	for body: Node in PlanProbe.bodies_under(world):
		if TwinSpace.twin_for(body) is StaticBody3D:
			found.append(body as Node2D)
	for node: Node in world.get_tree().get_nodes_in_group(&"floors"):
		if world.is_ancestor_of(node) and TwinSpace.twin_for(node) is StaticBody3D:
			found.append(node as Node2D)
	return found


## How many walls, floors and pieces have their mesh on their twin.
func _carried(mirror: MeshCarrier, world: Node) -> Dictionary:
	var count := { "wall": 0, "floor": 0, "piece": 0 }
	for node in _static_bodies(world):
		var mesh := mirror.mesh_of(node)
		if mesh == null or mesh.get_parent() != TwinSpace.twin_for(node):
			continue
		var kind := "floor" if node.is_in_group(&"floors") else (
			"wall" if node.has_method(&"segment_shapes") else "piece"
		)
		count[kind] += 1
	return count


## The middle of the rooms' bounds.
func _middle(rooms: Array) -> Vector2:
	var box := Rect2()
	for i in rooms.size():
		var rect := Rect2(rooms[i].get("rect", Rect2()))
		box = rect if i == 0 else box.merge(rect)
	return box.get_center()


## The picture the view shows now.
func _picture(view: CanvasLayer) -> Image:
	RenderingServer.force_draw(false)
	return view.shown.get_texture().get_image()


## How many pixels of `a` differ from `b` by more than `TOLERANCE` in any channel.
func _differing(a: Image, b: Image) -> int:
	var count := 0
	var slack := float(TOLERANCE) / 255.0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > slack or absf(p.g - q.g) > slack or absf(p.b - q.b) > slack:
				count += 1
	return count
