extends GameTest
## Performance guard (#194): a car's and a character's mesh carried by its twin
## costs the carrier a frame what it did when the mirror it replaced was measured. A `MeshCarrier`
## looks at one yard of 6 cars and 24 characters walking about; each frame it updates, timed beside
## a fixed reference loop (`tests/_perf/perf_reference.gd`). Its update stays under `CEILING_RATIO`
## times that loop, about 4x the 6.0 it measures (2.05 to 2.1 ms against a loop of 0.35 ms; the
## mirror's carried arm measured 2.1 to 2.4 ms timed the same way). A load moves the ratio little
## (6.2 at load 31). It writes no mesh (a character's turn aside). The number prints as a
## `CARRIER` line.

const Reference := preload("res://tests/_perf/perf_reference.gd")
const CARS := 6
const WALKERS := 24
const FRAMES := 150
## The most the carrier's update may cost, as a multiple of the reference loop timed in the same
## frames (`perf_reference.gd`): a load slows both, so the ratio holds under it.
const CEILING_RATIO := 24.0


func describe() -> Dictionary:
	return {
		"name": "Carried cars and characters cost the carrier a frame no more than they did",
		"description": "6 cars and 24 walking characters carried by their twins; the carrier's "
			+ "update stays under its ceiling and writes no mesh.",
		"tags": ["perf", "mesh-carrier", "render3d", "twins", "carriers", "vehicle", "character"],
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
	var carrier := _carrier(t)
	await t.frames(4)
	carrier.update()
	t.check(carrier.count > 0, "premise: it carries the yard")
	var car := t.vehicle(&"car0")
	var walker := t.actor(&"w0")
	for body: Node2D in [car, walker]:
		var mesh := carrier.mesh_of(body)
		t.check(
			mesh != null and mesh.get_parent() == TwinSpace.twin_for(body),
			"premise: it carries %s" % body.name,
		)
	for i in WALKERS:
		var to := Vector2(300 + (i * 7919) % 1200, 520 + (i * 104_729) % 400)
		t.puppet(StringName("w%d" % i)).walk_to(to)
	var stats := await _measure(t, carrier)
	print(
		"CARRIER fleet %.4f ms (x%.2f) (writes %d)"
		% [stats["ms"], stats["ratio"], stats["written"]]
	)
	t.expect_eq(stats["written"], 0, "the carrier wrote no mesh")
	t.check(
		stats["ratio"] <= CEILING_RATIO,
		"carrier update %.2f times the reference loop <= %.1f" % [stats["ratio"], CEILING_RATIO],
	)


## A carrier of the world under `t`, in the twins' world; its own `_process` is off, the test
## updates it.
func _carrier(t: TestContext) -> MeshCarrier:
	var view := SubViewport.new()
	view.world_3d = TwinSpace.of_world(t.world).find_world_3d()
	t.world.add_child(view)
	var carrier := MeshCarrier.new()
	VehicleMeshes.register(carrier.builders)
	CharacterMeshes.register(carrier.builders)
	view.add_child(carrier)
	carrier.carry(t.world)
	carrier.set_process(false)
	return carrier


## `FRAMES` frames of the carrier updating, timed: its mean update (ms) and what it wrote.
func _measure(t: TestContext, carrier: MeshCarrier) -> Dictionary:
	var ref_loop := Reference.new()
	var spent := 0.0
	var spent_ref := 0.0
	var written := 0
	for i in FRAMES:
		await t.frames(1)
		var from := Time.get_ticks_usec()
		carrier.update()
		spent += float(Time.get_ticks_usec() - from) / 1000.0
		spent_ref += ref_loop.time_ms()
		written += carrier.written
	ref_loop.release()
	return { "ms": spent / FRAMES, "ratio": spent / maxf(spent_ref, 0.001), "written": written }
