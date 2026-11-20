extends GameTest
## Performance guard (#194 del2d-b3): a car's and a character's mesh carried by its twin costs the
## 3D mirror no more than the same mesh followed by the mirror. Two mirrors look at one yard of 6
## cars and 24 characters walking about, one drawn in the twins' world (its meshes are its twins'
## children) and one in a world of its own (it follows each body); each frame both update, timed
## one after the other, so the machine's load is the same for both. The carried mirror's mean update
## is at most the followed one's (with a little slack for noise), and it writes no mesh at all. The
## numbers print as `MIRROR` lines.

const CARS := 6
const WALKERS := 24
const FRAMES := 150
## How much more (a share, and ms) the carried mirror's mean update may cost than the followed
## one's.
const SLACK_SHARE := 0.10
const SLACK_MS := 0.02


func describe() -> Dictionary:
	return {
		"name": "Carried cars and characters cost the mirror no more than followed ones",
		"description": "6 cars and 24 walking characters seen by a mirror in the twins' world "
			+ "(carried meshes) and one in a world of its own (followed); the carried one's "
			+ "update costs no more and writes no mesh.",
		"tags": ["perf", "mirror", "render3d", "twins", "carriers", "vehicle", "character"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1800, 1000), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	for i in CARS:
		s.vehicle(StringName("car%d" % i), &"car", Vector2(200 + i * 270, 150))
	for i in WALKERS:
		s.actor(
			StringName("w%d" % i), &"puppet",
			Vector2(120 + (i % 12) * 140, 500 + int(i / 12.0) * 200),
		)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var carried := _mirror(t, true)
	var followed := _mirror(t, false)
	await t.frames(4)
	carried.update()
	followed.update()
	t.check(carried.count > 0 and carried.count == followed.count, "premise: both mirror the yard")
	var car := t.vehicle(&"car0")
	var walker := t.actor(&"w0")
	for body: Node2D in [car, walker]:
		t.check(
			carried.mesh_of(body).get_parent() == TwinSpace.twin_for(body),
			"premise: the first mirror carries %s" % body.name,
		)
		t.check(followed.mesh_of(body).get_parent() == followed, "premise: the second follows")
	for i in WALKERS:
		var to := Vector2(300 + (i * 7919) % 1200, 520 + (i * 104_729) % 400)
		t.puppet(StringName("w%d" % i)).walk_to(to)
	var stats := await _measure(t, carried, followed)
	print(
		"MIRROR fleet carried %.4f ms followed %.4f ms (writes %d / %d)" % [
			stats["carried_ms"], stats["followed_ms"],
			stats["carried_written"], stats["followed_written"],
		]
	)
	t.expect_eq(stats["carried_written"], 0, "the carried mirror wrote no mesh")
	t.check(stats["followed_written"] > 0, "premise: the followed mirror wrote meshes")
	var limit: float = stats["followed_ms"] * (1.0 + SLACK_SHARE) + SLACK_MS
	t.check(
		stats["carried_ms"] <= limit,
		"carried update %.4f ms <= followed %.4f ms (+ slack)" % [stats["carried_ms"], limit],
	)


## A mirror of the world under `t`, drawn in the twins' world (`carry`) or in a world of its own;
## its own `_process` is off, the test updates it.
func _mirror(t: TestContext, carry: bool) -> WorldMirror:
	var view := SubViewport.new()
	if carry:
		view.world_3d = TwinSpace.of_world(t.world).find_world_3d()
	else:
		view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	VehicleMeshes.register(mirror.builders)
	CharacterMeshes.register(mirror.builders)
	view.add_child(mirror)
	mirror.mirror(t.world)
	mirror.set_process(false)
	return mirror


## `FRAMES` frames of both mirrors updating, each timed apart (the order alternates): their mean
## update (ms) and what each wrote.
func _measure(t: TestContext, carried: WorldMirror, followed: WorldMirror) -> Dictionary:
	var spent := [0.0, 0.0]
	var written := [0, 0]
	for i in FRAMES:
		await t.frames(1)
		var pair := [carried, followed]
		if i % 2 == 1:
			pair.reverse()
		for mirror: WorldMirror in pair:
			var from := Time.get_ticks_usec()
			mirror.update()
			var at := 0 if mirror == carried else 1
			spent[at] += float(Time.get_ticks_usec() - from) / 1000.0
			written[at] += mirror.written
	return {
		"carried_ms": spent[0] / FRAMES, "followed_ms": spent[1] / FRAMES,
		"carried_written": written[0], "followed_written": written[1],
	}
