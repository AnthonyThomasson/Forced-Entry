extends GameTest
## Rule 36 of #192: the body's draw caches (`BodyDrawCache`: `PixelArt.render_turned`'s last hit per
## part, the silhouette and uvs of an undented part, no empty per-draw lists, one reused
## `FillBatch`) change nothing it draws. A body is frozen after walking, in a changed outfit, with
## another weapon, dented, crouched and fallen, and drawn plainly (`BodyDrawCache.enabled` off),
## cached, then cached again: the textures, the order and every silhouette and uv it painted are
## equal each way, and windowed every pixel of the rendered frame. The second cached draw must be
## answered by the caches (the counters), so a draw that quietly stopped caching cannot pass.

const BodyMeshes = preload("res://scenes/character/body/body_meshes.gd")
const Visuals = preload("res://scenes/character/body/character_visuals.gd")
const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const ACTORS: Array[StringName] = [&"walker", &"hurt", &"crouched", &"fallen"]
## The world rect the comparison view frames (the whole arena), and how much it magnifies it.
const FRAME := Rect2(0, 0, 600, 400)
const ZOOM := 2.0
## Walking samples, and the seconds between them.
const WALK_SAMPLES := 4
const WALK_STEP := 0.15


func describe() -> Dictionary:
	return {
		"name": "The draw caches paint what the plain draw painted",
		"description": "Cached and uncached draws of a walking, outfit-swapped, re-armed, dented, "
			+ "crouched and fallen body paint the same textures, shapes and pixels, and the "
			+ "caches answer the repeat draw.",
		"tags": ["draw", "character", "cache"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(FRAME)
	s.switch(&"lighting.enabled", false)
	s.switch(&"physics.blood", false)
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)
	s.set_static(BodyDrawCache, &"enabled", true)
	s.set_static(BodyMeshes, &"enabled", DisplayServer.get_name() != "headless")
	s.actor(&"walker", &"puppet", Vector2(120, 140), { "start_slot": 3 })
	s.actor(&"hurt", &"puppet", Vector2(460, 140), { "start_slot": 2 })
	s.actor(&"crouched", &"puppet", Vector2(220, 280), { "start_slot": 5 })
	s.actor(&"fallen", &"puppet", Vector2(400, 270), { "max_health": 10.0 })
	s.camera_follow(ACTORS)
	s.lock_interaction([&"camera", &"pause", &"overlays"])


func run(t: TestContext) -> void:
	for id in ACTORS:
		t.actor(id).get_node("Visuals").cache.record = true
	t.puppet(&"walker").aim_at(Vector2(600, 140))
	t.puppet(&"walker").walk(Vector2.RIGHT)
	t.puppet(&"crouched").aim_at(Vector2(0, 0))
	t.puppet(&"crouched").set_posture(&"crouch")
	var view := _comparison_view(t)
	var repeat_hits := 0
	for i in WALK_SAMPLES:
		await t.seconds(WALK_STEP)
		repeat_hits += await _compare(t, view, "walking frame %d" % i)
	OutfitProbe.wear(t.actor(&"walker"), OutfitProbe.PLATED_KIT)
	t.puppet(&"walker").stop()
	await t.seconds(0.3)
	repeat_hits += await _compare(t, view, "after an outfit swap")
	t.puppet(&"walker").select_slot(6)
	await t.seconds(0.4)
	repeat_hits += await _compare(t, view, "after a weapon swap")
	_dent(t.actor(&"hurt"))
	await t.seconds(0.2)
	repeat_hits += await _compare(t, view, "dented")
	t.actor(&"fallen").take_damage(100.0)
	await t.seconds(0.35)
	repeat_hits += await _compare(t, view, "falling")
	await t.seconds(2.5)
	repeat_hits += await _compare(t, view, "fallen")
	_check_no_empty_lists(t, t.actor(&"walker").get_node("Visuals"))
	t.check(repeat_hits > 0, "the caches answered the repeat draws (%d)" % repeat_hits)
	t.check(
		PixelArt.last_hits > 0,
		"render_turned's last-hit slots answered (%d)" % PixelArt.last_hits,
	)
	t.check(
		BodyDrawCache.shape_hits > 0,
		"undented silhouettes were reused (%d)" % BodyDrawCache.shape_hits,
	)


## Draw the frozen bodies plainly, cached, then cached again, and check the three agree. Returns
## how many cache answers the repeat draw made.
func _compare(t: TestContext, view: SubViewport, label: String) -> int:
	for id in ACTORS:
		t.actor(id).process_mode = Node.PROCESS_MODE_DISABLED
	var seen: Array[Dictionary] = []
	var images: Array[Image] = []
	var repeat_hits := 0
	for pass_index in 3:
		BodyDrawCache.enabled = pass_index > 0
		var before := PixelArt.last_hits + BodyDrawCache.shape_hits
		var batches := BodyDrawCache.batches_made
		_repaint(t)
		await t.frames(2)
		if pass_index == 2:
			repeat_hits = PixelArt.last_hits + BodyDrawCache.shape_hits - before
			t.expect_eq(BodyDrawCache.batches_made, batches,
				"%s: the repeat draw makes no new FillBatch" % label)
		elif pass_index == 0:
			t.check(BodyDrawCache.batches_made > batches,
				"%s: the plain draw makes its FillBatches (premise)" % label)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			images.append(view.get_texture().get_image())
		seen.append(_read(t))
	BodyDrawCache.enabled = true
	for id in ACTORS:
		t.actor(id).process_mode = Node.PROCESS_MODE_INHERIT
	if not images.is_empty():
		var used := images[0].get_used_rect().size
		t.check(used.x * used.y > 20_000, "the bodies were rendered (%s painted)" % [used])
	for pass_index in [1, 2]:
		for id in ACTORS:
			t.check(
				seen[pass_index][id] == seen[0][id],
				"%s, %s: pass %d paints the plain draw's textures, order and shapes"
					% [label, id, pass_index],
			)
		if not images.is_empty():
			t.expect_eq(_differing(images[0], images[pass_index]), 0,
				"%s: pixels differing from the plain draw, pass %d" % [label, pass_index])
	return repeat_hits


## What each frozen body's last draw painted: its textures, order and shapes.
func _read(t: TestContext) -> Dictionary:
	var out := {}
	for id in ACTORS:
		var visuals = t.actor(id).get_node("Visuals")
		out[id] = {
			"art": visuals.drawn_art(),
			"order": visuals.draw_order.duplicate(),
			"shapes": visuals.cache.shapes.duplicate(true),
		}
	return out


func _repaint(t: TestContext) -> void:
	for id in ACTORS:
		var visuals = t.actor(id).get_node("Visuals")
		visuals.queue_redraw()
		visuals.shadow.node.queue_redraw()


func _dent(body: Node) -> void:
	var hit := HitInfo.new()
	hit.position = body.global_position + Vector2(-8, 0)
	hit.normal = Vector2.LEFT
	hit.direction = Vector2.RIGHT
	hit.damage = 20.0
	body.anatomy.deformable.record(hit, body.anatomy.pose.torso_angle)


## A view under the test's world rendering the world's canvas, `FRAME` magnified `ZOOM` times.
func _comparison_view(t: TestContext) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(FRAME.size * ZOOM)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(view)
	view.world_2d = t.world.get_viewport().world_2d
	view.canvas_transform = Transform2D(0.0, Vector2(ZOOM, ZOOM), 0.0, -FRAME.position * ZOOM)
	return view


static func _differing(a: Image, b: Image) -> int:
	if a.get_data() == b.get_data():
		return 0
	var out := 0
	for y in a.get_height():
		for x in a.get_width():
			out += 0 if a.get_pixel(x, y) == b.get_pixel(x, y) else 1
	return out


## A body with no wounds draws with the list it has, not a new empty one per part.
func _check_no_empty_lists(t: TestContext, visuals: Node) -> void:
	var none := []
	t.check(is_same(Visuals._turned(none, 0.7), none), "no wounds, none turned into a new list")
	t.check(is_same(Visuals._shifted(none, Vector2(3, 4)), none), "none shifted into a new list")
	t.check(is_same(visuals._through(none, Vector2.ZERO, 5.0), none), "none seated in a part")
