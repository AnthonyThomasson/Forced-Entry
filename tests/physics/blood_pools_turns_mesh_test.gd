extends GameTest
## A volley of bleeding pools in the 3D render (#193 phase 2, Physics): the layer builds at most one
## pool's picture a frame, in turn, so five pools growing at once cost one build a frame and not
## five; every pool is built within a few frames of its interval, none starves, and a pool that
## settled is built no more. Asserted at the seams: the layer `PhysicsMeshes.install` adds, its
## `pools` and the 2D `BloodPool`s it mirrors.

const SCRATCH := "user://settings_blood_pools_turns_mesh_test.json"
const POOLS := 5
## Pools are rebuilt as often as the frame allows, so each frame has five due.
const INTERVAL := 0.0


func describe() -> Dictionary:
	return {
		"name": "Five bleeding pools in 3D are rebuilt one a frame, in turn",
		"description": "With five pools all growing, the layer builds no more than one picture a "
			+ "frame, each pool gets its turn, and settled pools are not built again.",
		"tags": ["mirror", "3d", "render", "physics", "blood", "pool", "perf"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", true)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(PhysicsInkConfig, &"pool_interval", INTERVAL)
	s.set_static(BloodPoolConfig, &"bleed_out_duration", 2.0)
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	var layer := PhysicsMeshes.install(mirror)
	mirror.mirror(t.world)
	var pools := []
	for i in POOLS:
		var anchor := Node2D.new()
		t.world.add_child(anchor)
		anchor.global_position = Vector2(150.0 + i * 200.0, 300.0)
		pools.append(BloodSpawner.bleed(t.world, anchor, []))
	t.expect_eq(layer.pools.count(), POOLS, "five pools lie on the floor")
	var seen := await _volley(t, layer, pools)
	var most: int = seen[0]
	var first_seen: Dictionary = seen[1]
	t.expect_eq(most, 1, "never more than one pool is built in a frame")
	t.expect_eq(first_seen.size(), POOLS, "each pool is built")
	var latest := 0
	for pool: Node2D in pools:
		latest = maxi(latest, first_seen.get(pool, 9999))
	t.check(latest <= POOLS + 3, "and each in its turn, none starved (frame %d)" % latest)
	await t.seconds(1.0)
	t.expect_eq(layer.pools.waiting(), 0, "none waits once they settle")
	var kept := layer.pools.builds
	await t.seconds(0.5)
	t.expect_eq(layer.pools.builds, kept, "settled pools are built no more")
	t.check(not layer.is_processing(), "and the layer rests")


## Let the pools grow until they settle: the most built in one frame, and the frame each was first
## built.
func _volley(t: TestContext, layer: FxLayer, pools: Array) -> Array:
	var most := 0
	var first_seen := {}
	var frame := 0
	while not _settled(pools) and frame < 600:
		var before := layer.pools.builds
		await t.frames(1)
		frame += 1
		most = maxi(most, layer.pools.builds - before)
		for pool: Node2D in pools:
			if layer.pools.picture_of(pool) != null and not first_seen.has(pool):
				first_seen[pool] = frame
	return [most, first_seen]


## Whether every pool's flow has settled.
func _settled(pools: Array) -> bool:
	for pool: Node2D in pools:
		if not pool.flow.settled():
			return false
	return true


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
