extends GameTest
## The picture is the same when the bodies that move carry their meshes on their twins as when the
## mirror follows them (#194 del2d-b2b, windowed only: the headless renderer draws nothing). A
## furnished house shown by Main's `View3D` with its lights: a piece knocked over and lying on its
## side, a door swung open and a door knocked off its hinges (a slab lying where it fell) are drawn
## carried by their twins and the picture is read back; then `MirrorConfig.carry_meshes` goes off
## and those three are meshed again, now followed by the mirror, and the picture is read again in
## the same process and view, the lights held still: the same pixels. Environment:
## `CARRY_SHOT=<dir>` saves both pictures. Run:
## `tools/run_tests.sh --windowed --id=general/twin_moving_picture_windowed`.

const MAIN_VIEW3D := preload("res://scenes/main_view3d.gd")
const Probe := preload("res://tests/_objects/piece_probe.gd")
const SEED := 3
## Frames the picture settles for after the camera or the world is set, and seconds a body may take
## to come to rest.
const SETTLE := 20
const REST := 20.0
## Pixels (of a 0 to 255 channel) a pixel may differ by, and how many of them may.
const TOLERANCE := 1
const MAX_DIFFERING := 0
## The farthest (px) a body may stand from the camera for the picture to hold it.
const IN_VIEW := 300.0
## The highest a piece is (px) to be worth knocking over, and the push (px/s) that tips it.
const TALL := 60.0
const TIP_PUSH := 9000.0


func describe() -> Dictionary:
	return {
		"name": "The 3D picture is the same with moving meshes carried as followed (windowed)",
		"description": "A tipped piece, an open door and a fallen door slab drawn carried by "
			+ "their twins, then meshed again and followed by the mirror: the picture's pixels "
			+ "are the same. Windowed only.",
		"tags": ["render", "3d", "twins", "carriers", "windowed", "furniture", "door"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.set_static(MirrorConfig, &"carry_meshes", true)  # put back as it was when the test ends
	s.house(SEED)


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	await t.frames(2)
	var cast := _cast(t.world)
	if not t.require(not cast.is_empty(), "premise: a tall free piece and two doors stand near"):
		return
	var view := await _start_view(t, cast["at"])
	var movers: Array[Node2D] = [cast["piece"], cast["open"], cast["fell"]]
	await _stage(t, cast)
	for body in movers:
		var mesh := view.mirror.mesh_of(body)
		t.check(
			mesh != null and mesh.get_parent() == TwinSpace.twin_for(body),
			"premise: %s is carried by its twin" % body.name,
		)
	t.check(TwinSpace.twin_for(cast["piece"]) is PieceBody, "premise: the piece is a free body")
	t.check(TwinSpace.twin_for(cast["fell"]) is DoorSlab, "premise: the felled door is a slab")
	t.check(Probe.lean(cast["piece"]) > 60.0, "premise: the piece lies over")
	# the lights flicker: held still, the two pictures stand at the same instant of them
	view.lighting.process_mode = Node.PROCESS_MODE_DISABLED
	await t.frames(SETTLE)
	var on_twins := _picture(view)
	var again := _picture(view)
	t.check(_differing(on_twins, again) == 0, "premise: a picture of the same world holds still")
	MirrorConfig.carry_meshes = false
	for body in movers:
		view.mirror.remirror(body)
	await t.frames(SETTLE)
	for body in movers:
		var mesh := view.mirror.mesh_of(body)
		t.check(
			mesh != null and mesh.get_parent() == view.mirror,
			"premise: %s is followed again" % body.name,
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


## The bodies the picture is about, from the house: a tall free piece and the two doors nearest it,
## all within view of `at`, the plan point the camera looks at. {} when no piece has them.
func _cast(world: Node) -> Dictionary:
	var doors: Array[Node2D] = []
	for node: Node in world.get_tree().get_nodes_in_group(&"doors"):
		if world.is_ancestor_of(node) and TwinSpace.twin_for(node) is DoorBody:
			doors.append(node as Node2D)
	var best := {}
	var spread := INF
	for body: Node in world.find_children("*", "RigidBody2D", true, false):
		if not TwinSpace.twin_for(body) is PieceBody or Probe.top(body) < TALL:
			continue
		var from := (body as Node2D).global_position
		var near := doors.duplicate()
		near.sort_custom(
			func(a: Node2D, b: Node2D) -> bool:
				return a.global_position.distance_to(from) < b.global_position.distance_to(from)
		)
		if near.size() < 2:
			return {}
		var at: Vector2 = (from + near[0].global_position + near[1].global_position) / 3.0
		var far := maxf(
			from.distance_to(at),
			maxf(near[0].global_position.distance_to(at), near[1].global_position.distance_to(at)),
		)
		if far < spread:
			spread = far
			best = { "piece": body, "open": near[0], "fell": near[1], "at": at }
	if spread > IN_VIEW:
		return {}
	return best


## Knock the piece over, swing one door open and knock the other off its hinges; wait for all three
## to come to rest.
func _stage(t: TestContext, cast: Dictionary) -> void:
	var piece: Node2D = cast["piece"]
	Knockback.push(piece, Vector2(TIP_PUSH, 0.0), Vector2.ZERO, Probe.top(piece) - 4.0)
	var open: Node2D = cast["open"]
	open.toggle(null)
	var fell: Node2D = cast["fell"]
	fell.take_blow(&"kick", 10_000.0, Vector2(2200.0, 0.0), 40.0)
	await t.seconds(0.3)
	await Probe.settle(t, piece, REST)
	await Probe.settle(t, fell, REST)
	await t.until(func() -> bool: return not open.swing.moving(), REST)
	await t.frames(SETTLE)


## Main's 3D view of the house, lit, settled.
func _start_view(t: TestContext, at: Vector2) -> MAIN_VIEW3D:
	var camera := Camera2D.new()
	camera.position = at
	t.world.add_child(camera)
	camera.make_current()
	var view := MAIN_VIEW3D.new()
	t.world.add_child(view)
	view.begin(camera)
	view.mirror_world(t.world)
	view.light_world(t.world, SEED, t.world.rooms)
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
