extends GameTest
## The picture is the same when the follower and the viewport's layers draw the loose things as when
## the mirror tracked them and the layers hung under it (#194 del2d-b3b, windowed only: the headless
## renderer draws nothing). A furnished house shown by Main's `View3D` with its lights, a floor
## stencil, a rifle lying near the camera and blood on the floor: the picture is read back (the
## stencil and the rifle shown by the `MeshFollower`, the effects' and the shots' layers children of
## the viewport); then the follower is gone, the mirror tracks the same groups and the layers are
## put under the mirror as they were, and the picture is read again in the same instant of the
## lights: the same pixels. Environment: `FOLLOWER_SHOT=<dir>` saves both pictures. Run:
## `tools/run_tests.sh --windowed --id=general/follower_picture_windowed`.

const MAIN_VIEW3D := preload("res://scenes/main_view3d.gd")
const SEED := 3
## Frames the picture settles for after the camera or the world is set.
const SETTLE := 20
## Seconds the loose things settle for.
const REST := 4.0
## Pixels (of a 0 to 255 channel) a pixel may differ by, and how many of them may.
const TOLERANCE := 1
const MAX_DIFFERING := 0


func describe() -> Dictionary:
	return {
		"name": "The picture is the same with the follower as with the mirror tracking (windowed)",
		"description": "A house with a floor stencil, a lying rifle and blood, drawn with the "
			+ "mesh follower and the layers in the viewport, then tracked by the mirror with the "
			+ "layers under it: the picture's pixels are the same. Windowed only.",
		"tags": ["render", "3d", "follower", "windowed"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.house(SEED)


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	await t.frames(2)
	var view := await _start_view(t)
	var at := _middle(t.world.rooms)
	_litter(t, at)
	await t.seconds(REST)  # the rifle lands, the blood stops spreading
	t.check(view.follower.count >= 2, "premise: the follower shows the stencil and the rifle")
	var layers := [view.viewport.get_node("FxLayer"), view.viewport.get_node("ShotLayer")]
	t.check(layers[0].ink.count_of(InkMark.Kind.SPLAT) > 0, "premise: the blood lies on the floor")
	t.check(layers[1].tracer_count() > 0, "premise: the shots' layer draws a tracer")
	t.check(layers[1].casing_count() > 0, "premise: and a casing")
	view.lighting.process_mode = Node.PROCESS_MODE_DISABLED
	await t.frames(2)
	var on_follower := _picture(view)
	t.check(_differing(on_follower, _picture(view)) == 0, "premise: a picture holds still")
	view.follower.free()
	ObjectMeshes.track(view.mirror)
	ItemMeshes.register(view.mirror)
	for layer: Node in layers:
		layer.reparent(view.mirror, false)
	await t.frames(3)  # the transforms of what was just built reach the renderer
	t.expect_eq(view.mirror.count > 0, true, "premise: the mirror tracks them now")
	var on_mirror := _picture(view)
	_save(on_follower, on_mirror)
	t.expect_eq(on_follower.get_size(), on_mirror.get_size(), "the pictures are the same size")
	var differing := _differing(on_follower, on_mirror)
	t.check(
		differing <= MAX_DIFFERING,
		"the picture is the same with the follower or the mirror (%d pixels differ)" % differing,
	)
	t.check(_tones(on_follower) >= 8, "premise: the picture holds a world")


## A stencil, a rifle, blood, a bullet hanging in the air and a casing lying on the floor round `at`
## (the last two held still: no process moves them, so the two pictures draw the same instant).
func _litter(t: TestContext, at: Vector2) -> void:
	DecalFactory.stencil(
		Rect2(at + Vector2(-60, -30), Vector2(80, 40)),
		{ "text": "X" },
		"Probe",
		t.world,
	)
	var rifle := DroppedItem.spawn(ItemRegistry.create(6), 0.0, Vector2.ZERO)
	rifle.place(t.world, at + Vector2(40, 30), at + Vector2(40, 30))
	for i in 6:
		var throw := BloodThrow.new()
		throw.size = 3.5
		throw.energy = 0.6
		BloodSpawner.splat(t.world, at + Vector2(-30 + i * 12, 10 + (i % 2) * 8), throw)
	var shot := Shot.new()
	shot.muzzle_speed = 900.0
	shot.max_range = 600.0
	shot.height = 20.0
	var bullet := ProjectileSpawner.spawn(at + Vector2(-80, 60), Vector2.RIGHT, t.world, shot)
	var casing := CasingSpawner.spawn(at + Vector2(-20, 70), Vector2.RIGHT, t.world)
	for held: Node in [bullet, casing]:
		held.set_physics_process(false)
		held.set_process(false)


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
	view.light_world(t.world, SEED, t.world.rooms)
	t.world.visible = false
	await t.frames(SETTLE)
	return view


## Save the two pictures when `FOLLOWER_SHOT` names a directory.
func _save(first: Image, second: Image) -> void:
	var dir := OS.get_environment("FOLLOWER_SHOT")
	if dir != "":
		first.save_png(dir.path_join("follower.png"))
		second.save_png(dir.path_join("mirror.png"))


## How many tones the picture holds, sampled every 8 pixels.
func _tones(picture: Image) -> int:
	var tones := {}
	for y in range(0, picture.get_height(), 8):
		for x in range(0, picture.get_width(), 8):
			tones[picture.get_pixel(x, y).to_html(false)] = true
	return tones.size()


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
