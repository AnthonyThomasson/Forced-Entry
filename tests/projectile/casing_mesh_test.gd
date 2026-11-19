extends GameTest
## A spent casing is a tiny mesh on the 3D floor (#193 phase 2, Projectile): tossed out it falls
## from the port's height on its 2D node's path (#194 ragdoll3d: the node flies in the twin 3D
## space, real gravity, no fixed arc), lying it rests on the floor where its node came to rest,
## turned as it is; the batch they share is bounded and shows exactly the casings the 2D world keeps
## (the `Despawner`'s cap), a place freed is taken again, and nothing runs once they all lie.
## Asserted at the seams: the layer `ProjectileMeshes.install` adds (`casing_count`, `casing_frame`,
## the casing batch) and the 2D casings it follows. The numbers are pinned here. The look is judged
## in a window, `items_projectile_mesh_windowed_test.gd`.

const SCRATCH := "user://settings_casing_mesh_test.json"
## A casing's size (the 2D art's): 4.5 px long and 2 px across.
const LENGTH := 4.5
const ACROSS := 2.0
## The batch's size (the `Despawner`'s cap when the layer is made), and the height a casing is let
## go from (px).
const CAPACITY := 20
const PORT := 50.0
## How far (px) the batch may lag its node in the toss: the node's flight steps in the physics
## frame and the layer in the render's, so the part is a frame behind it, a frame being at most
## 2 px at the toss's fastest.
const SLACK := 2.0
## The `Despawner`'s cap for this test (the 2D world keeps at most this many casings).
const KEPT := 30


func describe() -> Dictionary:
	return {
		"name": "A spent casing is a tiny mesh that arcs out and lies on the floor",
		"description": "A casing arcs off the floor along its node's toss, lies where its node "
			+ "lay, is one part of a bounded batch holding what the Despawner keeps in 2D "
			+ "under sustained fire, and nothing runs once they all lie.",
		"tags": ["mirror", "3d", "render", "projectile", "casing"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	_check_sized_by_the_despawner(t)
	var kept := Despawner.max_scene_objects
	Despawner.max_scene_objects = CAPACITY
	var mirror := _mirror(t)
	var layer := ProjectileMeshes.install(mirror, t.world)
	mirror.mirror(t.world)
	t.check(layer.casing_count() == 0, "no casing, none shown")
	await _check_one_casing(t, layer)
	Despawner.max_scene_objects = KEPT  # raised after the layer was made: the batch is now short
	await _check_sustained_fire(t, layer)
	Despawner.max_scene_objects = kept


## The casing batch holds at least what the Despawner keeps in the 2D world, at its cap as it is
## and as it is set.
func _check_sized_by_the_despawner(t: TestContext) -> void:
	var cap := Despawner.max_scene_objects
	var layer := ShotLayer.new()
	t.check(layer.casing_capacity() >= cap, "the casing batch holds the cap (%d)" % cap)
	layer.free()
	Despawner.max_scene_objects = 77
	layer = ShotLayer.new()
	t.check(layer.casing_capacity() >= 77, "and a cap that is set (77)")
	layer.free()
	Despawner.max_scene_objects = cap


## One casing: a tiny box; it arcs off the floor on its node's path, then lies at its node's place
## and turn.
func _check_one_casing(t: TestContext, layer: ShotLayer) -> void:
	var casing := CasingSpawner.spawn(Vector2(300, 300), Vector2.RIGHT, t.world, PORT)
	await t.frames(1)
	t.expect_eq(layer.casing_count(), 1, "a spent casing is one part of the casing batch")
	var size := layer.casing_batch().multimesh.mesh.get_aabb().size
	t.expect_near(size.x, LENGTH, 0.01, "it is as long as its 2D art")
	t.expect_near(size.z, ACROSS, 0.01, "and as wide")
	var highest := 0.0
	var worst := 0.0
	for _i in 160:
		var flying := layer.casing_frame(0)
		highest = maxf(highest, flying.origin.y)
		worst = maxf(worst, _off(flying, casing))
		await t.frames(1)
	t.check(
		highest > PORT * 0.5 and highest <= PORT + 8.0,
		"let go at its height (%.1f px)" % highest,
	)
	t.check(worst < SLACK, "along its node's toss (off by up to %.1f px)" % worst)
	var frame := layer.casing_frame(0)
	t.expect_near(frame.origin.y, 0.0, 0.01, "lying, it is on the floor")
	t.check(_off(frame, casing) < 0.1, "at its node's place")
	var along := Vector3(cos(casing.rotation), 0.0, sin(casing.rotation))
	t.check(frame.basis.x.normalized().is_equal_approx(along), "turned as its node is")
	t.check(not layer.is_processing(), "and the layer rests")
	casing.queue_free()
	await t.frames(2)
	t.expect_eq(layer.casing_count(), 0, "a casing the world loses leaves the batch")


## Sustained fire: far more casings than the world keeps, which is more than the batch holds (the
## cap was raised after it was made). The world keeps `KEPT`, the batch shows what it holds of them,
## nothing is made past that, and it all rests.
func _check_sustained_fire(t: TestContext, layer: ShotLayer) -> void:
	var made := 0
	for _i in 150:
		CasingSpawner.spawn(Vector2(200 + made % 40, 300), Vector2.UP, t.world, 30.0)
		made += 1
		await t.frames(1)
		t.check(layer.casing_count() <= CAPACITY, "the batch is never over its size")
	await t.frames(160)
	t.expect_eq(_kept(t), KEPT, "the world keeps what the Despawner allows")
	t.expect_eq(layer.casing_count(), CAPACITY, "the batch shows what it holds of them")
	t.expect_eq(layer.casing_capacity(), CAPACITY, "and its size is unchanged")
	t.check(not layer.is_processing(), "nothing runs once they all lie")
	var mesh_before := layer.casing_batch().multimesh.mesh
	await t.frames(10)
	t.check(layer.casing_batch().multimesh.mesh == mesh_before, "no new mesh is made")


## How far (px) the casing in `frame` is from its 2D node.
func _off(frame: Transform3D, casing: Node2D) -> float:
	var at := Vector2(frame.origin.x, frame.origin.z)
	return at.distance_to(casing.global_position)


## How many casings the 2D world holds.
func _kept(t: TestContext) -> int:
	return t.world.get_children().filter(
		func(n):
			var script: Script = n.get_script()
			return (
				not n.is_queued_for_deletion()
				and script != null
				and script.resource_path.ends_with("projectile/casing.gd")
			)
	).size()


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
