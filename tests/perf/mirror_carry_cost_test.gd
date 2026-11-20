extends GameTest
## Performance guard (#194 del2d-b2b): a piece's mesh carried by its twin costs the 3D mirror no
## more than the same mesh followed by the mirror. Two mirrors look at one pile of 120 pieces
## shoved all at once, one drawn in the twins' world (its meshes are its twins' children) and one in
## a world of its own (it follows each piece); each frame both update, timed one after the other,
## so the machine's load is the same for both. Measured while the pile moves and once it rests:
## the carried mirror's mean update is at most the followed one's (with a little slack for noise),
## and it writes no mesh at all. The numbers print as `MIRROR` lines.

const Piece := preload("res://tests/_objects/piece_probe.gd")
const COLUMNS := 12
const ROWS := 10
const KINDS := ["chair", "side_table", "armchair", "plant"]
const MOVING_FRAMES := 120
const RESTING_FRAMES := 120
## How much more (a share, and ms) the carried mirror's mean update may cost than the followed
## one's.
const SLACK_SHARE := 0.10
const SLACK_MS := 0.02


func describe() -> Dictionary:
	return {
		"name": "A carried piece costs the mirror no more than a followed one",
		"description": "120 shoved pieces seen by a mirror in the twins' world (carried meshes) "
			+ "and one in a world of its own (followed); the carried one's update costs no more "
			+ "while the pile moves or rests, and writes no mesh.",
		"tags": ["perf", "mirror", "render3d", "twins", "carriers", "furniture"],
		"timeout": 40.0,
	}


func _id(i: int) -> StringName:
	return StringName("piece%d" % i)


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1300, 1100))
	s.switch(&"nav.rebake", false)  # shoved pieces overlap
	for i in COLUMNS * ROWS:
		var at := Vector2(120 + (i % COLUMNS) * 90, 120 + (int(i / float(COLUMNS))) * 90)
		s.object(_id(i), KINDS[i % KINDS.size()], at)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var carried := _mirror(t, true)
	var followed := _mirror(t, false)
	await t.frames(4)
	carried.update()
	followed.update()
	t.check(carried.count > 0 and carried.count == followed.count, "premise: both mirror the pile")
	var piece := t.object(_id(0))
	t.check(
		carried.mesh_of(piece).get_parent() == TwinSpace.twin_for(piece),
		"premise: the first mirror carries",
	)
	t.check(followed.mesh_of(piece).get_parent() == followed, "premise: the second follows")
	for i in COLUMNS * ROWS:
		var shoved := t.object(_id(i)) as Node2D
		var toward := (Vector2(650, 550) - shoved.global_position).normalized()
		Knockback.push(shoved, toward * 1500.0)
	var moving := await _measure(t, carried, followed, MOVING_FRAMES)
	var settled := await t.until(_all_asleep.bind(t), 20.0)
	t.require(settled, "premise: the pile comes to rest")
	var resting := await _measure(t, carried, followed, RESTING_FRAMES)
	_report("moving", moving)
	_report("resting", resting)
	t.expect_eq(moving["carried_written"], 0, "the carried mirror wrote no mesh while it moved")
	t.expect_eq(resting["carried_written"], 0, "nor while it rested")
	t.check(moving["followed_written"] > 0, "premise: the followed mirror wrote meshes (moving)")
	for phase: Dictionary in [moving, resting]:
		var limit: float = phase["followed_ms"] * (1.0 + SLACK_SHARE) + SLACK_MS
		t.check(
			phase["carried_ms"] <= limit,
			"carried update %.4f ms <= followed %.4f ms (+ slack)" % [phase["carried_ms"], limit],
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
	ObjectMeshes.register(mirror.builders)
	view.add_child(mirror)
	mirror.mirror(t.world)
	mirror.set_process(false)
	return mirror


## Whether every piece's 3D body sleeps.
func _all_asleep(t: TestContext) -> bool:
	for i in COLUMNS * ROWS:
		if not Piece.asleep(t.object(_id(i))):
			return false
	return true


## `frames` frames of both mirrors updating, each timed apart (the order alternates): their mean
## update (ms) and what each wrote.
func _measure(
	t: TestContext, carried: WorldMirror, followed: WorldMirror, frames: int
) -> Dictionary:
	var spent := [0.0, 0.0]
	var written := [0, 0]
	for i in frames:
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
		"carried_ms": spent[0] / frames, "followed_ms": spent[1] / frames,
		"carried_written": written[0], "followed_written": written[1],
	}


func _report(phase: String, stats: Dictionary) -> void:
	print(
		"MIRROR %s carried %.4f ms followed %.4f ms (writes %d / %d)" % [
			phase, stats["carried_ms"], stats["followed_ms"],
			stats["carried_written"], stats["followed_written"],
		]
	)
