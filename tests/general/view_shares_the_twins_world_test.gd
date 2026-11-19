extends GameTest
## The 3D view draws the twins' own world (#194 del2d-b,
## `docs/adr/0014-twin-staging-and-plan-space.md`, interface 27): once Main's `View3D` is told of a
## staged world (`mirror_world`) its picture's viewport shares the 3D `World3D` of that world's
## `TwinSpace`, so the meshes and the lights stand in the world the bodies are in and the meshes can
## attach to them. Two staged worlds keep two worlds (a test that builds another beside the default
## arena never draws the other's), the window's is never used, a view that goes leaves the twins'
## physics space answering rays, and a world with no twin space (built by hand) is drawn in a world
## of the view's own.

const MAIN_VIEW3D := preload("res://scenes/main_view3d.gd")


func describe() -> Dictionary:
	return {
		"name": "The 3D view shares its staged world's twin space world",
		"description": "After mirror_world the view's viewport finds the same World3D as the "
			+ "world's TwinSpace (the mirror's meshes too), not the window's and not another "
			+ "twin space's; the twin space still answers a ray after the view is freed; a "
			+ "world with no twin space is drawn in a world of its own.",
		"tags": ["render", "3d", "twins"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 300, 200))


func run(t: TestContext) -> void:
	await t.frames(2)
	var twins: TwinSpace = t.world.twin_space()
	var camera := Camera2D.new()
	camera.position = Vector2(150.0, 100.0)
	t.world.add_child(camera)
	camera.make_current()
	var view := MAIN_VIEW3D.new()
	t.world.add_child(view)
	view.begin(camera)
	view.mirror_world(t.world)
	await t.frames(3)
	var shown: World3D = view.viewport.find_world_3d()
	t.check(shown == twins.find_world_3d(), "the view's viewport shares the twin space's world")
	t.check(shown != t.world.get_viewport().find_world_3d(), "and it is not the window's world")
	t.check(not view.viewport.own_world_3d, "the view has no world of its own")
	t.check(view.mirror.get_world_3d() == twins.find_world_3d(), "the mirror's meshes stand in it")
	t.check(view.rig.camera.get_world_3d() == twins.find_world_3d(), "the camera sees it")
	var other := TwinSpace.new()
	t.world.add_child(other)
	t.check(
		other.find_world_3d() != view.viewport.find_world_3d(),
		"another twin space is not the one the view draws",
	)
	other.queue_free()
	t.check(_ray_hits(twins), "the twin space answers a ray with the view up")
	view.get_parent().remove_child(view)
	view.queue_free()
	await t.frames(3)
	t.check(_ray_hits(twins), "the twin space answers a ray after the view is gone")
	await _a_world_with_no_twins(t, camera)


## A view of a world no `TwinSpace` stands in is drawn in a world of its own (nothing there blocks
## a line, but the picture needs a world that is not the window's).
func _a_world_with_no_twins(t: TestContext, camera: Camera2D) -> void:
	var bare := Node2D.new()
	t.world.add_child(bare)
	var view := MAIN_VIEW3D.new()
	t.world.add_child(view)
	view.begin(camera)
	view.mirror_world(bare)
	await t.frames(2)
	t.check(view.viewport.own_world_3d, "a world with no twin space is drawn in a world of its own")
	t.check(
		view.viewport.find_world_3d() != t.world.get_viewport().find_world_3d(),
		"and that is not the window's either",
	)
	view.queue_free()


## Whether a ray from above the arena down to under it meets any twin.
func _ray_hits(twins: TwinSpace) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		PlanSpace.lift(Vector2(150.0, 100.0), 500.0),
		PlanSpace.lift(Vector2(150.0, 100.0), -20.0),
	)
	query.collision_mask = 0xffffffff
	return not twins.space().intersect_ray(query).is_empty()
