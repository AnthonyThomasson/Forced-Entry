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
	t.check(view.carrier.get_world_3d() == twins.find_world_3d(), "the mirror's meshes stand in it")
	t.check(view.rig.camera.get_world_3d() == twins.find_world_3d(), "the camera sees it")
	t.check(
		view.viewport.get_node_or_null("FxLayer") != null,
		"the effects' layer is in the viewport",
	)
	t.check(view.viewport.get_node_or_null("ShotLayer") != null, "so is the shots' layer")
	t.check(
		view.carrier.get_child_count() == 0 or _no_layers(view.carrier),
		"none is under the mirror",
	)
	t.check(view.follower.get_world_3d() == twins.find_world_3d(), "the follower stands in it too")
	for layer: Node3D in [view.viewport.get_node("FxLayer"), view.viewport.get_node("ShotLayer")]:
		t.check(layer.get_world_3d() == twins.find_world_3d(), "%s stands in it" % layer.name)
		t.check(layer.global_transform.is_equal_approx(Transform3D.IDENTITY), "at the origin")
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
	await _a_view_that_waits(t, camera)


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


## Whether no effects' or shots' layer is a child of `mirror`.
func _no_layers(mirror: Node) -> bool:
	var fx := mirror.get_node_or_null("FxLayer")
	return fx == null and mirror.get_node_or_null("ShotLayer") == null


## Whether a ray from above the arena down to under it meets any twin.
func _ray_hits(twins: TwinSpace) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		PlanSpace.lift(Vector2(150.0, 100.0), 500.0),
		PlanSpace.lift(Vector2(150.0, 100.0), -20.0),
	)
	query.collision_mask = 0xffffffff
	return not twins.space().intersect_ray(query).is_empty()


## A view that has only begun (Main builds it before the match) draws a world of its own, never the
## window's and never another view's (the pixel-post tests hold ten at once: each draws its own
## rooms); told of a staged world later it takes that twin space's world, a view that fell back to
## its own world included (the second call clears the own world and takes the twins').
func _a_view_that_waits(t: TestContext, camera: Camera2D) -> void:
	var first := MAIN_VIEW3D.new()
	var second := MAIN_VIEW3D.new()
	t.world.add_child(first)
	t.world.add_child(second)
	first.begin(camera)
	second.begin(camera)
	await t.frames(2)
	var window := t.world.get_viewport().find_world_3d()
	t.check(
		first.viewport.find_world_3d() != window,
		"a view that only began is not in the window's world",
	)
	t.check(
		first.viewport.find_world_3d() != second.viewport.find_world_3d(),
		"and two such views do not share one world",
	)
	var twins: TwinSpace = t.world.twin_space()
	first.mirror_world(t.world)
	await t.frames(2)
	t.check(
		first.viewport.find_world_3d() == twins.find_world_3d(),
		"told of a world it takes the twins'",
	)
	t.check(
		second.viewport.find_world_3d() != twins.find_world_3d(),
		"and the other view still draws its own",
	)
	var bare := Node2D.new()
	t.world.add_child(bare)
	second.mirror_world(bare)  # no twin space: its own world stays
	second.mirror_world(t.world)  # then a staged world: the own world is given up
	await t.frames(2)
	t.check(
		second.viewport.find_world_3d() == twins.find_world_3d(),
		"a second call takes the twins' world",
	)
	t.check(not second.viewport.own_world_3d, "and the view's own world is cleared")
	first.queue_free()
	second.queue_free()
