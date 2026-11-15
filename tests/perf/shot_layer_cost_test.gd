extends GameTest
## Performance guard: what the 3D render's shot layer (Projectile's `ShotLayer`, #193 phase 2) costs
## a frame at its worst. Two loads, each timed as the wall time of the layer's own per-frame work
## (`_process`): the tracer pool full (every one of its places a bullet in flight, each written
## every frame) and the casing pool full while all of it is tossed at once (the `Despawner`'s cap of
## casings in the air, each written every frame of the toss, which no real fight reaches: tens fly
## at a time); and, once they lie, that the layer is idle and costs nothing. Headless the renderer
## is a dummy, so a part's write is free there: the windowed run
## (`tools/run_tests.sh --windowed --id=perf/shot_layer_cost`) is the real number.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const SCRATCH := "user://settings_shot_layer_cost_test.json"
## Timed calls of the layer's work for each load.
const CALLS := 40
## Budgets (ms per frame): the worst case of each load, a fraction of a 60 fps frame
## (`Perf.SMOOTH_AVG_MS`).
const TRACERS_MS := 1.5
const CASINGS_MS := 4.0


func describe() -> Dictionary:
	return {
		"name": "The shot layer costs little with every pool full",
		"description": "The tracer pool full of bullets in flight and the casing pool full of "
			+ "casings in the air: the layer's per-frame work stays within budget, and once "
			+ "the casings lie the layer is idle.",
		"tags": ["perf", "render", "3d", "projectile", "tracer", "casing"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	var layer := ProjectileMeshes.install(mirror, t.world)
	await _tracers(t, layer)
	await _casings(t, layer)


## Every tracer place taken by a bullet that stays where it is: the layer writes them all each
## frame.
func _tracers(t: TestContext, layer: ShotLayer) -> void:
	var bullets := []
	for i in ProjectileMeshConfig.tracer_capacity:
		var shot := Shot.new()
		shot.muzzle_speed = 100.0
		var at := Vector2(40 + (i % 32) * 28, 40 + floori(i / 32.0) * 28)
		var bullet := ProjectileSpawner.spawn(at, Vector2.from_angle(i * 0.5), t.world, shot)
		bullet.set_physics_process(false)
		bullets.append(bullet)
	await t.frames(2)
	t.expect_eq(layer.tracer_count(), ProjectileMeshConfig.tracer_capacity, "the pool is full")
	var ms := _time(layer)
	Perf.within(
		t,
		"shot layer, %d tracers in flight (ms/frame)" % layer.tracer_count(),
		ms,
		TRACERS_MS,
	)
	for bullet: Node in bullets:
		bullet.queue_free()
	await t.frames(2)
	t.expect_eq(layer.tracer_count(), 0, "the pool empties with the bullets")


## The `Despawner`'s cap of casings, all in the air at once, then all lying.
func _casings(t: TestContext, layer: ShotLayer) -> void:
	for i in Despawner.max_scene_objects:
		CasingSpawner.spawn(
			Vector2(40 + (i % 40) * 20, 40 + floori(i / 40.0) * 20),
			Vector2.UP,
			t.world,
		)
	t.expect_eq(layer.casing_count(), Despawner.max_scene_objects, "every casing has a place")
	var ms := _time(layer)
	Perf.within(
		t,
		"shot layer, %d casings in the air (ms/frame)" % layer.casing_count(),
		ms,
		CASINGS_MS,
	)
	await t.seconds(1.0)
	t.check(not layer.is_processing(), "once they lie the layer is idle")
	t.expect_eq(layer.casing_count(), Despawner.max_scene_objects, "and still shows them all")


## The mean wall time (ms) of the layer's per-frame work over `CALLS` calls that move nothing on
## (a delta of 0, so the tossed casings stay in the air).
func _time(layer: ShotLayer) -> float:
	var total := 0.0
	for _i in CALLS:
		total += Perf.time_ms(func(): layer._process(0.0))
	return total / CALLS
