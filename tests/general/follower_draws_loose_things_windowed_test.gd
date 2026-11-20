extends GameTest
## The follower and the viewport's layers draw the loose things (#194 del2d-b3c, windowed only: the
## headless renderer draws nothing). A furnished house shown by Main's `View3D` with its lights held
## still; the picture is read back, then a floor stencil, a rifle lying near the camera and blood on
## the floor are added one by one, and each changes the picture: some pixels differ from the picture
## before it. The follower's `count` and the effects' layer say the same from the inside. Run:
## `tools/run_tests.sh --windowed --id=general/follower_draws_loose_things_windowed`.

const MAIN_VIEW3D := preload("res://scenes/main_view3d.gd")
const SEED := 3
## Frames the picture settles for after the camera or the world is set.
const SETTLE := 20
## Seconds a loose thing settles for (the rifle lands, the blood stops spreading).
const REST := 3.0
## Pixels (of a 0 to 255 channel) a pixel may differ by, and the fewest that must differ.
const TOLERANCE := 1
const MIN_DIFFERING := 50


func describe() -> Dictionary:
	return {
		"name": "The follower and the layers draw a stencil, a rifle and blood (windowed)",
		"description": "A house with its lights held: a floor stencil, a lying rifle and blood "
			+ "each change the picture's pixels where they lie. Windowed only.",
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
	view.lighting.process_mode = Node.PROCESS_MODE_DISABLED
	var at := _middle(t.world.rooms)
	await t.frames(2)
	var clean := _picture(view)
	t.check(_differing(clean, _picture(view)) == 0, "premise: a picture holds still")
	var count := view.follower.count
	DecalFactory.stencil(
		Rect2(at + Vector2(-60, -30), Vector2(80, 40)), { "text": "X" }, "Probe", t.world
	)
	await t.seconds(REST)
	t.check(view.follower.count > count, "the follower shows the stencil")
	var with_stencil := _picture(view)
	_check_changed(t, clean, with_stencil, "a floor stencil")
	count = view.follower.count
	var rifle := DroppedItem.spawn(ItemRegistry.create(6), 0.0, Vector2.ZERO)
	rifle.place(t.world, at + Vector2(40, 30), at + Vector2(40, 30))
	await t.seconds(REST)
	t.check(view.follower.count > count, "the follower shows the rifle")
	var with_rifle := _picture(view)
	_check_changed(t, with_stencil, with_rifle, "a lying rifle")
	var fx := view.viewport.get_node("FxLayer")
	for i in 6:
		var throw := BloodThrow.new()
		throw.size = 3.5
		throw.energy = 0.6
		BloodSpawner.splat(t.world, at + Vector2(-30 + i * 12, 70 + (i % 2) * 8), throw)
	await t.seconds(REST)
	t.check(fx.ink.count_of(InkMark.Kind.SPLAT) > 0, "premise: the blood lies on the floor")
	_check_changed(t, with_rifle, _picture(view), "blood on the floor")
	_save(clean, with_rifle)


## `after` differs from `before` in at least `MIN_DIFFERING` pixels: `what` is drawn.
func _check_changed(t: TestContext, before: Image, after: Image, what: String) -> void:
	var differing := _differing(before, after)
	t.check(
		differing >= MIN_DIFFERING,
		"%s changes the picture (%d pixels differ, at least %d)" % [what, differing, MIN_DIFFERING],
	)


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


## Save the first and last pictures when `FOLLOWER_SHOT` names a directory.
func _save(first: Image, last: Image) -> void:
	var dir := OS.get_environment("FOLLOWER_SHOT")
	if dir != "":
		first.save_png(dir.path_join("clean.png"))
		last.save_png(dir.path_join("loose.png"))


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
	var differing := 0
	for y in a.get_height():
		for x in a.get_width():
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			var worst := maxf(
				maxf(
					absf(pa.r - pb.r),
					absf(pa.g - pb.g),
				), maxf(absf(pa.b - pb.b), absf(pa.a - pb.a))
			)
			if worst * 255.0 > TOLERANCE:
				differing += 1
	return differing
