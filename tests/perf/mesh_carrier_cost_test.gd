extends GameTest
## Performance guard (#194 del2d-b2b, del2d-b3c): a piece's mesh carried by its twin costs the
## carrier a frame what it did when the mirror it replaced was measured beside it. A `MeshCarrier`
## looks at one pile of 120 pieces shoved all at once; each frame it updates, timed, while the pile
## moves and once it rests. Its mean update stays under `CEILING_MS` (the carried arm measured 0.40
## ms moving and 0.38 ms resting before the mirror was deleted, 0.30 and 0.29 after), and it writes
## no mesh at all. The numbers print as `CARRIER` lines.

const Piece := preload("res://tests/_objects/piece_probe.gd")
const COLUMNS := 12
const ROWS := 10
const KINDS := ["chair", "side_table", "armchair", "plant"]
const MOVING_FRAMES := 120
const RESTING_FRAMES := 120
## The most the carrier's mean update may be (ms): a third over the 0.40 ms the carried arm
## measured.
const CEILING_MS := 0.55


func describe() -> Dictionary:
	return {
		"name": "A carried piece costs the carrier a frame no more than it did",
		"description": "120 shoved pieces carried by their twins; the carrier's update stays under "
			+ "its ceiling while the pile moves or rests, and writes no mesh.",
		"tags": ["perf", "mesh-carrier", "render3d", "twins", "carriers", "furniture"],
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
	var carrier := _carrier(t)
	await t.frames(4)
	carrier.update()
	t.check(carrier.count > 0, "premise: it carries the pile")
	var piece := t.object(_id(0))
	t.check(
		carrier.mesh_of(piece).get_parent() == TwinSpace.twin_for(piece),
		"premise: it carries on the twins",
	)
	for i in COLUMNS * ROWS:
		var shoved := t.object(_id(i)) as Node2D
		var toward := (Vector2(650, 550) - shoved.global_position).normalized()
		Knockback.push(shoved, toward * 1500.0)
	var moving := await _measure(t, carrier, MOVING_FRAMES)
	var settled := await t.until(_all_asleep.bind(t), 20.0)
	t.require(settled, "premise: the pile comes to rest")
	var resting := await _measure(t, carrier, RESTING_FRAMES)
	print("CARRIER moving %.4f ms resting %.4f ms" % [moving["ms"], resting["ms"]])
	for phase: Dictionary in [moving, resting]:
		t.expect_eq(phase["written"], 0, "the carrier wrote no mesh")
		t.check(
			phase["ms"] <= CEILING_MS,
			"carrier update %.4f ms <= %.2f ms" % [phase["ms"], CEILING_MS],
		)


## A carrier of the world under `t`, in the twins' world; its own `_process` is off, the test
## updates it.
func _carrier(t: TestContext) -> MeshCarrier:
	var view := SubViewport.new()
	view.world_3d = TwinSpace.of_world(t.world).find_world_3d()
	t.world.add_child(view)
	var carrier := MeshCarrier.new()
	ObjectMeshes.register(carrier.builders)
	view.add_child(carrier)
	carrier.carry(t.world)
	carrier.set_process(false)
	return carrier


## Whether every piece's 3D body sleeps.
func _all_asleep(t: TestContext) -> bool:
	for i in COLUMNS * ROWS:
		if not Piece.asleep(t.object(_id(i))):
			return false
	return true


## `frames` frames of the carrier updating, timed: its mean update (ms) and what it wrote.
func _measure(t: TestContext, carrier: MeshCarrier, frames: int) -> Dictionary:
	var spent := 0.0
	var written := 0
	for i in frames:
		await t.frames(1)
		var from := Time.get_ticks_usec()
		carrier.update()
		spent += float(Time.get_ticks_usec() - from) / 1000.0
		written += carrier.written
	return { "ms": spent / frames, "written": written }
