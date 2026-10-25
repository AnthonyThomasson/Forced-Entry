extends GameTest
## A body's one-polygon parts (its limb segments, its shoulders, fists and head, darkened once it
## is damaged, its shoulders' floor shadow, a folded or fallen trunk's faces) and its standing floor
## shadow's plain black shapes are drawn as meshes the body keeps (`body_meshes.gd`) instead of a
## polygon command each, which the renderer would build and free buffers for at every repaint. A
## mesh is cut into the engine's own triangles for the polygon and drawn in its colour, so it must
## paint exactly the polygon's pixels. Headless (the suite) this checks the parts go through meshes
## when meshes are on: every limb segment of a standing body, damaged or not, its shoulders, fists
## and head, and its shadow's shoulders and plain shapes. Run with a window
## (`tools/run_tests.sh --windowed --id=character/body_mesh_matches_polygons`) it freezes a
## walking, a running, a damaged, a crouched and a falling body, renders them magnified with meshes
## off (the polygons, `Deformation.draw_shape` and General's `FillBatch` as before), on, and off
## again, and checks every pixel is the same each way.

const BodyMeshes = preload("res://scenes/character/body/body_meshes.gd")
const ACTORS: Array[StringName] = [&"walker", &"runner", &"hurt", &"crouched", &"fallen"]
## A standing body's round parts: the shoulders, two fists and the head.
const ROUND_PARTS := 4
## The world rect the comparison view frames (the whole arena), and how much it magnifies it.
const FRAME := Rect2(0, 0, 600, 400)
const ZOOM := 2.0


func describe() -> Dictionary:
	return {
		"name": "A body's meshes paint what its polygons painted",
		"description": "The textured limb segments, shoulder shadow and trunk faces go through "
			+ "kept meshes; windowed, they render the same pixels as polygon commands.",
		"tags": ["draw", "character"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(FRAME)
	s.switch(&"lighting.enabled", false)
	s.switch(&"physics.blood", false)
	s.switch(&"physics.debris", false)
	s.set_static(BodyMeshes, &"enabled", true)
	s.actor(&"walker", &"puppet", Vector2(180, 140), { "start_slot": 3 })
	s.actor(&"runner", &"puppet", Vector2(330, 150), { "start_slot": 6 })
	s.actor(&"hurt", &"puppet", Vector2(460, 140), { "start_slot": 2 })
	s.actor(&"crouched", &"puppet", Vector2(220, 280), { "start_slot": 5 })
	s.actor(&"fallen", &"puppet", Vector2(400, 270), { "max_health": 10.0 })
	s.camera_follow(ACTORS)
	s.lock_interaction([&"camera", &"pause", &"overlays"])


func run(t: TestContext) -> void:
	if not await _freeze_bodies(t):
		return
	await _repaint(t)
	var walker = t.actor(&"walker").get_node("Visuals")
	_check_meshes_used(t, walker)
	if DisplayServer.get_name() == "headless":
		return
	await _check_pixels(t, walker)


## Set the bodies walking, running, crouched, damaged and falling, then freeze them all mid-way.
## Whether the fallen one is falling (false after a failed `require`).
func _freeze_bodies(t: TestContext) -> bool:
	t.puppet(&"walker").aim_at(Vector2(600, 0))
	t.puppet(&"walker").walk(Vector2.RIGHT)
	t.puppet(&"runner").aim_at(Vector2(0, 400))
	t.puppet(&"runner").set_run(true)
	t.puppet(&"runner").walk(Vector2(1, 1).normalized())
	t.puppet(&"crouched").aim_at(Vector2(0, 0))
	t.puppet(&"crouched").set_posture(&"crouch")
	var hurt_body: Node = t.actor(&"hurt")
	var hit := HitInfo.new()  # A wound: the body's dented and darkened.
	hit.position = hurt_body.global_position + Vector2(-8, 0)
	hit.normal = Vector2.LEFT
	hit.direction = Vector2.RIGHT
	hit.damage = 20.0
	hurt_body._deformable.record(hit, hurt_body.pose.torso_angle)
	await t.seconds(0.8)
	t.actor(&"fallen").take_damage(100.0)
	await t.seconds(0.35)  # Mid-fall: the trunk tipped, its faces turned up.
	if not t.require(t.actor(&"fallen").ragdoll != null, "the fallen body is falling"):
		return false
	for id in ACTORS:
		t.actor(id).process_mode = Node.PROCESS_MODE_DISABLED
	return true


## Headless too: the parts of every frozen body go through meshes (`walker` the walker's visuals).
func _check_meshes_used(t: TestContext, walker: Node) -> void:
	var segments := 0
	for chain in walker._limbs(walker._rig):
		segments += (chain["segs"] as Array).size()
	t.expect_eq(
		walker._meshes.used(),
		segments + ROUND_PARTS,
		"every limb segment of a standing body is a mesh, and its shoulders, fists and head",
	)
	t.expect_eq(
		walker.shadow.meshes.used(),
		2,
		"its shadow is two: the shoulders and every plain black shape",
	)
	var hurt = t.actor(&"hurt").get_node("Visuals")
	t.expect_eq(
		hurt._meshes.used(),
		segments + ROUND_PARTS,
		"a damaged body's darkened shoulders, fists and head are meshes too",
	)
	for id in [&"crouched", &"fallen"]:
		var visuals = t.actor(id).get_node("Visuals")
		t.check(
			visuals._meshes.used() > segments,
			"%s: the limbs and the trunk's faces are meshes (%d)" % [id, visuals._meshes.used()],
		)


## Windowed: the frozen scene rendered magnified with meshes off, on and off again paints the same
## pixels each way (`walker` the walker's visuals, whose meshes count the mode).
func _check_pixels(t: TestContext, walker: Node) -> void:
	var view := _comparison_view(t)
	var images: Array[Image] = []
	var used: Array[int] = []
	for meshes in [false, true, false]:
		BodyMeshes.enabled = meshes
		await _repaint(t)
		await RenderingServer.frame_post_draw
		images.append(view.get_texture().get_image())
		used.append(walker._meshes.used())
	BodyMeshes.enabled = true
	t.check(used[0] == 0 and used[2] == 0 and used[1] > 0, "meshes only when on (%s)" % [used])
	var painted := 0
	for y in images[0].get_height():
		for x in images[0].get_width():
			painted += 1 if images[0].get_pixel(x, y).a > 0.0 else 0
	t.check(painted > 10_000, "the bodies were rendered (%d pixels painted)" % painted)
	t.check(
		_differing(images[0], images[2]) == 0,
		"polygons drawn twice paint the same pixels (the frozen scene holds still)",
	)
	t.expect_eq(_differing(images[0], images[1]), 0, "polygons, then meshes: pixels differing")
	t.expect_eq(_differing(images[1], images[2]), 0, "meshes, then polygons: pixels differing")


## A view under the test's world rendering the world's canvas (none of the overlays), `FRAME`
## magnified `ZOOM` times.
func _comparison_view(t: TestContext) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(FRAME.size * ZOOM)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(view)
	view.world_2d = t.world.get_viewport().world_2d  # The world's canvas, none of the overlays.
	view.canvas_transform = Transform2D(0.0, Vector2(ZOOM, ZOOM), 0.0, -FRAME.position * ZOOM)
	return view


## Repaint every frozen body and its shadow, and let the repaint reach the renderer.
func _repaint(t: TestContext) -> void:
	for id in ACTORS:
		var visuals = t.actor(id).get_node("Visuals")
		visuals.queue_redraw()
		visuals.shadow.node.queue_redraw()
	await t.frames(3)


## How many pixels of `a` and `b` differ.
static func _differing(a: Image, b: Image) -> int:
	if a.get_data() == b.get_data():
		return 0
	var out := 0
	for y in a.get_height():
		for x in a.get_width():
			out += 0 if a.get_pixel(x, y) == b.get_pixel(x, y) else 1
	return out
