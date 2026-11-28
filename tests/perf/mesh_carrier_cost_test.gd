extends GameTest
## Performance guard (#194): a piece's mesh carried by its twin costs the
## carrier a frame what it did when the mirror it replaced was measured beside it. A `MeshCarrier`
## looks at one pile of 120 pieces shoved all at once; each frame it updates, timed, while the pile
## moves and once it rests. Its update, timed beside a fixed reference loop
## (`tests/_perf/perf_reference.gd`), stays under `CEILING_RATIO` times it, about 4x the 0.8 it
## measures (0.29 ms against a loop of 0.36 ms; the carried arm of the mirror measured 0.40 ms
## moving and 0.38 ms resting before it was deleted), and it writes no mesh at all.
## The numbers print as `CARRIER` lines.

const Piece := preload("res://tests/_objects/piece_probe.gd")
const Reference := preload("res://tests/_perf/perf_reference.gd")
const COLUMNS := 12
const ROWS := 10
const KINDS := ["chair", "side_table", "armchair", "plant"]
const MOVING_FRAMES := 120
const RESTING_FRAMES := 120
## The most the carrier's update may cost, as a multiple of the reference loop timed in the same
## frames (`perf_reference.gd`): a load slows both, so the ratio holds under it.
const CEILING_RATIO := 3.5


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
	var ref_loop := Reference.new()
	var moving := await _measure(t, carrier, ref_loop, MOVING_FRAMES)
	var settled := await t.until(_all_asleep.bind(t), 20.0)
	t.require(settled, "premise: the pile comes to rest")
	var resting := await _measure(t, carrier, ref_loop, RESTING_FRAMES)
	ref_loop.release()
	print(
		"CARRIER moving %.4f ms (x%.2f) resting %.4f ms (x%.2f)"
		% [moving["ms"], moving["ratio"], resting["ms"], resting["ratio"]]
	)
	for phase: Dictionary in [moving, resting]:
		t.expect_eq(phase["written"], 0, "the carrier wrote no mesh")
		t.check(
			phase["ratio"] <= CEILING_RATIO,
			"carrier update %.2f times the reference loop <= %.1f" % [
				phase["ratio"],
				CEILING_RATIO,
			],
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
func _measure(
	t: TestContext, carrier: MeshCarrier, ref_loop: RefCounted, frames: int
) -> Dictionary:
	var spent := 0.0
	var spent_ref := 0.0
	var written := 0
	for i in frames:
		await t.frames(1)
		var from := Time.get_ticks_usec()
		carrier.update()
		spent += float(Time.get_ticks_usec() - from) / 1000.0
		spent_ref += ref_loop.time_ms()
		written += carrier.written
	return { "ms": spent / frames, "ratio": spent / maxf(spent_ref, 0.001), "written": written }
