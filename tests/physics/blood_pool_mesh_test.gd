extends GameTest
## A dead body's bleed-out pool on the 3D floor (#193 phase 2, Physics): a decal over the box of
## cells the 2D pool covers, its picture the pool's fill field cut into two tones (a rim and the
## deep blood), growing as the pool's front sweeps out and built again at most every
## `PhysicsInkConfig.pool_interval` s; once the pool has settled nothing is built, and the decal
## goes with its pool. Asserted at the seams: the layer `PhysicsMeshes.install` adds, its `pools`
## and the 2D `BloodPool` it mirrors. The numbers are pinned here; the look is judged in a window,
## `physics_mesh_windowed_test.gd`.

const SCRATCH := "user://settings_blood_pool_mesh_test.json"
const AT := Vector2(300, 250)
## The pool's layer's height over the ground (px: layer 5 of 0.25), a decal's own float over it
## (`MeshKitConfig`), and the deep tone (`BloodConfig.color`, the art's sRGB).
const LIFT := 1.25
const FLOAT := 0.15
const DEEP := Color(0.42, 0.02, 0.03)
## The picture is this many times finer than a flow cell, and the pool is rebuilt this often (s).
const UPSCALE := 2
const INTERVAL := 0.2


func describe() -> Dictionary:
	return {
		"name": "A bleed-out pool is a decal on the 3D floor that grows with the pool",
		"description": "A dead body's pool is one decal over the cells the 2D pool covers, in two "
			+ "tones, built again as the pool grows at the interval, never once it has settled, "
			+ "and gone with its pool.",
		"tags": ["mirror", "3d", "render", "physics", "blood", "pool"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", true)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(PhysicsInkConfig, &"pool_upscale", UPSCALE)
	s.set_static(PhysicsInkConfig, &"pool_interval", INTERVAL)
	s.set_static(BloodPoolConfig, &"bleed_out_duration", 2.0)
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	var layer := PhysicsMeshes.install(mirror)
	mirror.mirror(t.world)
	var anchor := Node2D.new()
	t.world.add_child(anchor)
	anchor.global_position = AT
	var pool := BloodSpawner.bleed(t.world, anchor, [])
	t.expect_eq(layer.pools.count(), 1, "a pool lies on the floor")
	await t.seconds(0.4)
	var early := _blood_pixels(layer.pools.picture_of(pool))
	while not pool.flow.settled():
		await t.seconds(0.25)
	await t.seconds(0.6)
	var late := _blood_pixels(layer.pools.picture_of(pool))
	t.check(late > early * 1.5, "the picture grows with the pool (%d to %d px)" % [early, late])
	_check_the_picture(t, layer, pool)
	await _check_at_rest(t, layer)
	pool.queue_free()
	await t.frames(3)
	t.expect_eq(layer.pools.count(), 0, "a pool goes with its node")


## The settled pool's decal: at its height, over its cells, opaque where it lies, deep in the
## middle.
func _check_the_picture(t: TestContext, layer: FxLayer, pool: Node2D) -> void:
	var decal := layer.pools.decal_of(pool)
	if not t.require(decal != null, "the pool has a decal"):
		return
	t.expect_near(decal.position.y, LIFT + FLOAT, 0.001, "at the pool's height")
	var image := layer.pools.picture_of(pool)
	var cell := BloodPoolConfig.flow_cell_size
	var area := float(_blood_pixels(image)) * pow(cell / UPSCALE, 2.0)
	var claimed := float(pool.flow.cells.size()) * cell * cell
	t.check(
		area > claimed * 0.6 and area < claimed * 1.4,
		"it covers what the pool claims (%.0f px² of %.0f)" % [area, claimed],
	)
	var width := Vector2(image.get_size()) * cell / UPSCALE
	var middle := image.get_pixelv(image.get_size() / 2 - Vector2i(UPSCALE, UPSCALE))
	t.check(middle.a > 0.5, "the middle is blood (%s)" % middle)
	t.check(width.x > cell * 3.0, "over a box of cells")


## How many pixels of `image` are blood.
func _blood_pixels(image: Image) -> int:
	var lying := 0
	for y in image.get_height():
		for x in image.get_width():
			lying += 1 if image.get_pixel(x, y).a > 0.5 else 0
	return lying


## A settled pool is not built again, and the layer rests.
func _check_at_rest(t: TestContext, layer: FxLayer) -> void:
	await t.seconds(INTERVAL * 3.0)
	var built := layer.pools.builds
	await t.seconds(1.0)
	t.expect_eq(layer.pools.builds, built, "a settled pool is built no more")
	t.check(not layer.is_processing(), "and the layer rests")


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
