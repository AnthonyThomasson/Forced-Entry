extends GameTest
## A bullet in flight is a tracer in the 3D world (#193 phase 2, Projectile): a short bright streak
## along the shot line at the bullet's height, as long as the tunable length, shorter over the
## last stretch of the bullet's range, and gone the frame the bullet is. Asserted at the seams: the
## layer `ProjectileMeshes.install` adds (`tracer_count`, `tracer_frame`: the tracer batch's parts)
## and the 2D bullets it follows. The tunings the numbers come from are pinned here, not read from
## the defaults. The look is judged in a window, `items_projectile_mesh_windowed_test.gd`.

const SCRATCH := "user://settings_tracer_mesh_test.json"
## The pinned tunings: the streak's length (px), the stretch of range it shortens over (px), the
## batch's size and how a bullet's 0..100 height maps to px of 3D height.
const LENGTH := 16.0
const FADE := 120.0
const CAPACITY := 8
const HEIGHT_SCALE := 0.96
## The bullet's height (the cover scale, 0..100) every bullet flies at.
const BULLET_HEIGHT := 50.0
const SLACK := 1.5
## A slow round, so a flight lasts many frames.
const SPEED := 900.0
const RANGE := 700.0


func describe() -> Dictionary:
	return {
		"name": "A bullet in flight is a tracer streak at its height",
		"description": "Each live bullet is one streak of the tracer batch along its heading at "
			+ "its height, its tip on the bullet, shortening over the last stretch of its range, "
			+ "gone with the bullet, bounded by the batch's size, and nothing runs with none.",
		"tags": ["mirror", "3d", "render", "projectile", "tracer"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(BallisticsFlightConfig, &"bullet_height", BULLET_HEIGHT)
	s.set_static(ProjectileMeshConfig, &"tracer_length", LENGTH)
	s.set_static(ProjectileMeshConfig, &"tracer_fade", FADE)
	s.set_static(ProjectileMeshConfig, &"tracer_capacity", CAPACITY)
	s.set_static(ProjectileMeshConfig, &"height_scale", HEIGHT_SCALE)
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	var layer := ProjectileMeshes.install(mirror, t.world)
	mirror.mirror(t.world)
	t.check(layer.tracer_count() == 0, "no bullet, no tracer")
	t.check(not layer.is_processing(), "and the layer does nothing while there is none")
	await _check_a_flight(t, layer)
	await _check_expires(t, layer)
	await _check_bounded(t, layer)


## One bullet: one streak at its height along its heading, its tip on the bullet, shorter over the
## last `FADE` px of its range.
func _check_a_flight(t: TestContext, layer: ShotLayer) -> void:
	var bullet := _shoot(t, Vector2(100, 300), Vector2.RIGHT, RANGE)
	await t.frames(2)
	t.expect_eq(layer.tracer_count(), 1, "a bullet in flight is one tracer")
	t.check(layer.is_processing(), "and the layer runs while it flies")
	var worst := 0.0
	var long := 0.0
	var short_end := INF
	var checked := 0
	while is_instance_valid(bullet):
		var frame := layer.tracer_frame(0)
		var half := LENGTH * frame.basis.get_scale().z * 0.5
		var tip := frame.origin + frame.basis.z.normalized() * half
		var at: Vector2 = bullet.global_position
		worst = maxf(worst, Vector2(tip.x - at.x, tip.z - at.y).length())
		t.expect_near(frame.origin.y, BULLET_HEIGHT * HEIGHT_SCALE, 0.01, "at the bullet's height")
		t.check(frame.basis.z.normalized().is_equal_approx(Vector3.RIGHT), "along its heading")
		var left: float = bullet.range_left()
		if left > FADE + 60.0:
			long = maxf(long, frame.basis.get_scale().z)
		elif left < FADE - 20.0 and left > 5.0:
			short_end = minf(short_end, frame.basis.get_scale().z)
		checked += 1
		await t.frames(1)
	t.check(checked > 10, "the flight lasted many frames (%d)" % checked)
	t.check(worst < SLACK, "its tip stays on the bullet (off by up to %.1f px)" % worst)
	t.expect_near(long, 1.0, 0.01, "it is whole while the bullet is far from the end of its range")
	t.check(short_end < 0.9, "and shorter over the last stretch (%.2f of its length)" % short_end)
	await t.frames(2)


## It is gone with the bullet: spent at its range, or struck against a wall.
func _check_expires(t: TestContext, layer: ShotLayer) -> void:
	t.expect_eq(layer.tracer_count(), 0, "a spent bullet leaves no tracer")
	var into_wall := [_shoot(t, Vector2(900, 300), Vector2.RIGHT, 2000.0)]
	await t.frames(2)
	t.expect_eq(layer.tracer_count(), 1, "a bullet fired at the wall is a tracer")
	await t.until(func(): return not is_instance_valid(into_wall[0]), 3.0)
	await t.frames(2)
	t.expect_eq(layer.tracer_count(), 0, "its tracer is gone once it has struck")
	t.check(not layer.is_processing(), "and the layer rests")


## More bullets than the batch holds: it shows its capacity, none past it, and recovers.
func _check_bounded(t: TestContext, layer: ShotLayer) -> void:
	var bullets := []
	for i in CAPACITY * 2 + 4:
		bullets.append(_shoot(t, Vector2(100, 60 + i * 20), Vector2.RIGHT, 300.0))
	await t.frames(2)
	t.expect_eq(layer.tracer_count(), CAPACITY, "the batch shows only what it holds")
	await t.until(func(): return bullets.all(func(b): return not is_instance_valid(b)), 5.0)
	await t.frames(2)
	t.expect_eq(layer.tracer_count(), 0, "and empties as they are spent")
	var late := _shoot(t, Vector2(100, 300), Vector2.RIGHT, 300.0)
	await t.frames(2)
	t.expect_eq(layer.tracer_count(), 1, "a place freed is taken again")
	late.queue_free()


## A bullet from `at` along `direction` that flies `range_px`, slowly.
func _shoot(t: TestContext, at: Vector2, direction: Vector2, range_px: float) -> Node:
	var shot := Shot.new()
	shot.muzzle_speed = SPEED
	shot.max_range = range_px
	return ProjectileSpawner.spawn(at, direction, t.world, shot)


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
