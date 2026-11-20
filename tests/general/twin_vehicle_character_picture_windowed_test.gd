extends GameTest
## The picture is the same when a vehicle and the characters carry their meshes on their twins as
## when each mesh is placed by hand (#194 del2d-b3, windowed only: the headless renderer draws
## nothing). An arena shown by Main's `View3D`: a car driven round and left at rest, a character
## that walked and stopped, one crouched and one fallen (a ragdoll) are drawn carried by their twins
## and the picture is read back; then those five are shown by `FollowedBaseline` (the same meshes
## built anew, off their twins, placed by hand from the 2D bodies), and the picture is read again in
## the same process and view: the same pixels (both are of meshes built just now: a mesh remembers
## how it got to its pose). Environment: `CARRY_SHOT=<dir>` saves both pictures. Run:
## `tools/run_tests.sh --windowed --id=general/twin_vehicle_character_picture_windowed`.

const MAIN_VIEW3D := preload("res://scenes/main_view3d.gd")
const Baseline := preload("res://tests/_art/art_followed_baseline.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
## Frames the picture settles for after the camera or the world is set.
const SETTLE := 20
## Frames a mesh built anew takes to ease to its pose.
const EASE := 240
const CAR_AT := Vector2(420, 260)
## Pixels (of a 0 to 255 channel) a pixel may differ by, and how many of them may.
const TOLERANCE := 1
## A car at rest stands up to 2e-6 px off the floor plane (the solver's rest), which turns a depth
## edge of its roof over in a pixel or two; nothing else may differ.
const MAX_DIFFERING := 4


func describe() -> Dictionary:
	return {
		"name": "The 3D picture is the same with a car and characters carried (windowed)",
		"description": "A car driven and left, a walker, a crouched and a fallen character drawn "
			+ "carried by their twins, then meshed again and followed by the mirror: the "
			+ "picture's pixels are the same. Windowed only.",
		"tags": ["render", "3d", "twins", "carriers", "windowed", "vehicle", "character"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 900, 520), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", CAR_AT)
	s.actor(&"driver", &"puppet", Vector2(300, 160))
	s.actor(&"walker", &"puppet", Vector2(150, 120))
	s.actor(&"duck", &"puppet", Vector2(150, 260))
	s.actor(&"fallen", &"puppet", Vector2(150, 400))


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	await t.frames(2)
	var view := await _start_view(t, Vector2(330, 260))
	var car := t.vehicle(&"car") as Node2D
	if not t.require(
		await VehicleRide.board_by(t, &"driver", car, &"front_left"), "premise: the driver boards"
	):
		return
	await _stage(t, car)
	var movers: Array[Node2D] = [
		car, t.actor(&"walker"), t.actor(&"duck"), t.actor(&"fallen"), t.actor(&"driver"),
	]
	for body in movers:
		var mesh := view.carrier.mesh_of(body)
		t.check(
			mesh != null and mesh.get_parent() == TwinSpace.twin_for(body),
			"premise: %s is carried by its twin" % body.name,
		)
	t.check(TwinSpace.twin_for(car) is VehicleBody, "premise: the car is a free body")
	# the lights flicker: held still, the two pictures stand at the same instant of them
	view.lighting.process_mode = Node.PROCESS_MODE_DISABLED
	# so are the bodies (a breath, a wheel easing to straight): the sim is held, the view draws on
	t.world.process_mode = Node.PROCESS_MODE_DISABLED
	# both pictures are of meshes built just now, on the same state: a mesh remembers how it got to
	# its pose (a limb's ease, a corpse's fall), so one built long ago is not the one to compare
	_mesh_again(view, movers)
	await t.frames(EASE)
	var on_twins := _picture(view)
	var again := _picture(view)
	t.check(_differing(on_twins, again) == 0, "premise: a picture of the same world holds still")
	await _follow_again(t, view, movers)
	var followed := _picture(view)
	_save(on_twins, followed)
	t.expect_eq(on_twins.get_size(), followed.get_size(), "the pictures are the same size")
	var differing := _differing(on_twins, followed)
	t.check(
		differing <= MAX_DIFFERING,
		"the picture is the same carried or followed (%d pixels differ, in %s)"
		% [differing, str(_where(on_twins, followed))],
	)
	var tones := _tones(on_twins)
	t.check(tones >= 8, "premise: the picture holds a world (%d tones)" % tones)


## Show `movers` by `FollowedBaseline`: the same meshes built anew, placed by hand from the 2D
## bodies.
func _follow_again(t: TestContext, view: MAIN_VIEW3D, movers: Array[Node2D]) -> void:
	var baseline := Baseline.new()
	view.viewport.add_child(baseline)
	t.expect_eq(
		baseline.show_followed(view.carrier, movers), movers.size(),
		"premise: every mover is placed by hand",
	)
	await t.frames(EASE)
	for body in movers:
		var mesh := baseline.mesh_of(body)
		t.check(
			mesh != null and mesh.get_parent() == baseline,
			"premise: %s is followed again" % body.name,
		)


## Build the meshes of `movers` anew on their twins.
func _mesh_again(view: MAIN_VIEW3D, movers: Array[Node2D]) -> void:
	for body in movers:
		view.carrier.remirror(body)


## The driver takes the car round and stops it; the walker walks and stops, one ducks, one is shot
## dead; all come to rest.
func _stage(t: TestContext, car: Node2D) -> void:
	var driver := t.puppet(&"driver")
	for i in 90:
		driver.drive(1.0, 0.0 if i < 30 else 0.6, false)
		await t.frames(1)
	for _i in 60:
		driver.drive(-1.0, 0.0, false)
		await t.frames(1)
	driver.drive(0.0, 0.0, false)
	t.puppet(&"walker").walk_to(Vector2(260, 120))
	t.actor(&"duck").movement.set_posture(&"crouch")
	var fallen := t.actor(&"fallen")
	fallen.health = 1.0
	fallen.take_damage(1000.0)
	await t.seconds(4.0)
	t.require(car.speed() < 1.0, "premise: the car is at rest")


## Main's 3D view of the arena, settled.
func _start_view(t: TestContext, at: Vector2) -> MAIN_VIEW3D:
	var camera := Camera2D.new()
	camera.position = at
	t.world.add_child(camera)
	camera.make_current()
	var view := MAIN_VIEW3D.new()
	t.world.add_child(view)
	view.begin(camera)
	view.mirror_world(t.world)
	view.light_world(t.world, 1, [])
	t.world.visible = false
	await t.frames(SETTLE)
	return view


## Save the two pictures when `CARRY_SHOT` names a directory.
func _save(carried: Image, followed: Image) -> void:
	var dir := OS.get_environment("CARRY_SHOT")
	if dir != "":
		carried.save_png(dir.path_join("carried.png"))
		followed.save_png(dir.path_join("followed.png"))
		var diff := Image.create(
			carried.get_width(),
			carried.get_height(),
			false,
			Image.FORMAT_RGB8,
		)
		for y in carried.get_height():
			for x in carried.get_width():
				var p := carried.get_pixel(x, y)
				var q := followed.get_pixel(x, y)
				if absf(p.r - q.r) > 0.01 or absf(p.g - q.g) > 0.01 or absf(p.b - q.b) > 0.01:
					diff.set_pixel(x, y, Color.WHITE)
		diff.save_png(dir.path_join("diff.png"))


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


## The rectangle the pixels of `a` that differ from `b` lie in.
func _where(a: Image, b: Image) -> Rect2i:
	var box := Rect2i()
	var slack := float(TOLERANCE) / 255.0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > slack or absf(p.g - q.g) > slack or absf(p.b - q.b) > slack:
				box = Rect2i(
					x,
					y,
					1,
					1,
				) if box.size == Vector2i.ZERO else box.expand(Vector2i(x, y))
	return box
