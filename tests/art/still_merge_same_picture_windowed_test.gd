extends GameTest
## The still world drawn in merged chunks (`StillMerge`) is the picture each mesh drawing itself
## made. In a district, held still, each frame is drawn with the chunks and again with every mesh
## its own. Cause of what differs: a chunk holds its meshes' vertices pre-transformed into the
## world, where the GPU places a mesh of its own, and the two round to floats differently; a pixel
## falling exactly on an edge or between two texels may then pick the other. These ties are accepted
## as the same picture (#194): single art pixels (2x2), mostly 1 to 8 levels of a channel, now and
## then an outline for a surface, 40 to 153 pixels of a 1152 wide frame and 144 to 396 of a 2560
## wide one. `TIES` is that allowance; a part drawn wrong turns thousands. With each chunk keeping
## its one mesh's own transform, at most 24 pixels differed. Windowed only.
## `STILL_MERGE_SHOTS=<dir>` saves the pair of every frame that differs.

const Frozen := preload("res://tests/_render/frozen_frame.gd")
const SIZES: Array[Vector2i] = [Vector2i(1152, 648), Vector2i(2560, 1440)]
## The most pixels of a frame a tie may turn.
const TIES := 512


func describe() -> Dictionary:
	return {
		"name": "The still world in merged chunks draws the picture each mesh drew",
		"description": "Held frames of a district with the still meshes merged and with each "
			+ "drawing itself are the same but for ties. Windowed only.",
		"tags": ["art", "render", "3d"],
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.district(4)
	s.switch(&"nav.rebake", false)
	s.lock_interaction([&"camera"])
	# armed figures by the first spot, so the picture holds characters and guns too
	for i in 3:
		var at := Frozen.CENTRE + Vector2(Frozen.RADIUS - 40.0 * i, 30.0 * i)
		s.actor(StringName("figure%d" % i), &"puppet", at, { "start_slot": 3 })


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var view := Frozen.view(t)
	var merge: StillMerge = view.carrier.merge
	var original := DisplayServer.window_get_size()
	await t.seconds(5.0)
	for size in SIZES:
		DisplayServer.window_set_size(size)
		await t.frames(10)
		for turn: float in Frozen.TURNS:
			await Frozen.hold(t, view, turn)
			await _compare(t, view, merge, "%d wide, %.1f round" % [size.x, turn])
	DisplayServer.window_set_size(original)
	Frozen.release(t)


## The held frame with the chunks and with every mesh drawing itself.
func _compare(t: TestContext, view: CanvasLayer, merge: StillMerge, label: String) -> void:
	merge.enabled = true
	merge.merge_now()
	var merged := await Frozen.picture(t)
	var with_chunks := _draws(view, Viewport.RENDER_INFO_TYPE_VISIBLE)
	var cast_chunks := _draws(view, Viewport.RENDER_INFO_TYPE_SHADOW)
	t.require(merge.held() > 500, "premise: the chunks hold the district (%d)" % merge.held())
	var own: Array[Node] = []
	for chunk in merge.chunks():
		for member in chunk.members:
			own.append(member.node)
	merge.enabled = false
	merge.release()
	var apart := await Frozen.picture(t)
	var without := _draws(view, Viewport.RENDER_INFO_TYPE_VISIBLE)
	var cast_without := _draws(view, Viewport.RENDER_INFO_TYPE_SHADOW)
	t.check(
		with_chunks * 2 < without,
		"%s: the chunks draw far fewer calls (%d against %d)" % [label, with_chunks, without],
	)
	var differ := Frozen.differing(merged, apart)
	t.check(differ <= TIES, "%s: only ties differ (%d pixels)" % [label, differ])
	print(
		"STILL ", label, " draws ", with_chunks, " against ", without, ", shadow draws ",
		cast_chunks, " against ", cast_without, ", differ ", differ,
	)
	var dir := OS.get_environment("STILL_MERGE_SHOTS")
	if dir != "" and differ > 0:
		merged.save_png("%s/%s_merged.png" % [dir, label.replace(" ", "_")])
		apart.save_png("%s/%s_apart.png" % [dir, label.replace(" ", "_")])
	# carried meshes are offered again as they were first
	for node in own:
		if is_instance_valid(node):
			merge.offer(node)
	merge.enabled = true


## The draw calls of `type` (the visible ones, the shadow passes') in the 3D view's last frame.
func _draws(view: CanvasLayer, type: Viewport.RenderInfoType) -> int:
	var viewport: SubViewport = view.viewport
	return viewport.get_render_info(type, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
