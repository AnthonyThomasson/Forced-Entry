extends GameTest
## The pixel post while the camera turns (#193 rule 6: "turning the camera must not leave obvious
## shimmer"). Windowed only (the headless renderer draws nothing). A fixed room (a floor, long
## walls with thin tops, furniture, thin rails, specks and capsules) is drawn by Main's 3D view
## through the real post at 1152x648 while the rig's `yaw` turns 1.5 degrees a frame (90 a second),
## and the picture is read back every frame. A pixel of the picture (one per internal pixel) that
## changes colour and changes back the next frame is flicker: an edge crawling on and off, which
## a steadily moving edge never does. The variants are the post's shimmer mitigations
## (`PixelPostConfig.supersample`, `silhouette_px`) against the plain post; the default the holder
## ships must flicker no more than the plain one. `PIXELPOST_OUT=<file.json>` writes the numbers,
## `PIXELPOST_SHOTS=<dir>` saves two consecutive mid-turn frames per variant.
## Run: `tools/run_tests.sh --windowed --id=art/pixel_post_shimmer`.

const ViewScript := preload("res://scenes/main_view3d.gd")
const SIZE := Vector2i(1152, 648)
## Screen pixels to a picture pixel at 1152x648 (216 lines): the grid the picture is sampled on.
const PIXEL := 3
## The middle of the picture the flicker is read over (screen pixels): half the window's width and
## height, from a quarter in, on a pixel's middle.
const FROM := Vector2i(289, 163)
const TO := Vector2i(865, 487)
const FRAMES := 40
const STEP := 1.5
const START_YAW := 45.0
## A change of colour that counts (the sum of the channels' difference).
const CHANGED := 0.06
## The plain post, then each mitigation; `default` is whatever the holder ships.
const VARIANTS := {
	"plain": { "supersample": 1, "silhouette_px": 1.0 },
	"wide": { "supersample": 1, "silhouette_px": 2.0 },
	"x2": { "supersample": 2, "silhouette_px": 1.0 },
	"x2_wide": { "supersample": 2, "silhouette_px": 2.0 },
}


func describe() -> Dictionary:
	return {
		"name": "The pixel post's shimmer while the camera turns (windowed)",
		"description": "A fixed room turned at 90 degrees a second through the real post: the "
			+ "picture's flicker (a pixel that changes and changes back) for the plain post "
			+ "and each shimmer mitigation; the shipped default is no worse than plain.",
		"tags": ["render", "3d", "pixel", "windowed"],
		"timeout": 400.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(PixelPostConfig, &"supersample", PixelPostConfig.supersample)
	s.set_static(PixelPostConfig, &"silhouette_px", PixelPostConfig.silhouette_px)
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var shipped := {
		"supersample": PixelPostConfig.supersample,
		"silhouette_px": PixelPostConfig.silhouette_px,
	}
	var rows := {}
	for key: String in VARIANTS:
		rows[key] = await _turn(t, key, VARIANTS[key])
	rows["default"] = await _turn(t, "default", shipped)
	var out := OS.get_environment("PIXELPOST_OUT")
	if out != "":
		var file := FileAccess.open(out, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(rows, "\t"))
	for key: String in rows:
		var row: Dictionary = rows[key]
		t.check(
			int(row["changed"]) > 0,
			"%s: the picture turns (%d px changed)" % [key, row["changed"]],
		)
		print("SHIMMER %s flicker=%d changed=%d per_frame=%.1f" % [
			key, row["flicker"], row["changed"], float(row["flicker"]) / float(FRAMES - 2),
		])
	t.check(
		int(rows["default"]["flicker"]) <= int(rows["plain"]["flicker"]),
		"the default (%d) flickers no more than the plain post (%d)" % [
			rows["default"]["flicker"], rows["plain"]["flicker"],
		],
	)


## Turn the room under the post set by `variant` and count the flicker; `{ flicker, changed }`.
func _turn(t: TestContext, key: String, variant: Dictionary) -> Dictionary:
	PixelPostConfig.supersample = variant["supersample"]
	PixelPostConfig.silhouette_px = variant["silhouette_px"]
	var window := SubViewport.new()
	window.size = SIZE
	window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(window)
	var camera := Camera2D.new()
	window.add_child(camera)
	camera.make_current()
	var view: CanvasLayer = ViewScript.new()
	window.add_child(view)
	view.begin(camera)
	_room(view.viewport)
	view.rig.yaw = START_YAW
	await t.frames(6)
	var frames: Array[PackedInt32Array] = []
	var shots := OS.get_environment("PIXELPOST_SHOTS")
	for n in FRAMES:
		view.rig.yaw = START_YAW + float(n) * STEP
		await t.frames(1)
		await RenderingServer.frame_post_draw
		var image := window.get_texture().get_image()
		frames.append(_sample(image))
		if shots != "" and (n == 20 or n == 21):
			image.save_png("%s/%s_%d.png" % [shots, key, n])
	window.render_target_update_mode = SubViewport.UPDATE_DISABLED
	await t.frames(1)
	window.queue_free()
	await t.frames(2)
	return _count(frames)


## Count, over the frames, the pixels that changed and the ones that changed and changed back the
## next frame; `{ flicker, changed }`.
func _count(frames: Array[PackedInt32Array]) -> Dictionary:
	var flicker := 0
	var changed := 0
	for n in range(1, frames.size() - 1):
		var before := frames[n - 1]
		var now := frames[n]
		var after := frames[n + 1]
		for i in now.size():
			if _differs(before[i], now[i]):
				changed += 1
				if not _differs(before[i], after[i]):
					flicker += 1
	return { "flicker": flicker, "changed": changed }


## One colour per picture pixel of the middle of the picture (the middle of each 3x3 block of the
## nearest upscale, over half the window's width and height: GDScript reads it all every frame),
## packed as 8 bits a channel.
func _sample(image: Image) -> PackedInt32Array:
	var out := PackedInt32Array()
	for y in range(FROM.y, TO.y, PIXEL):
		for x in range(FROM.x, TO.x, PIXEL):
			out.append(image.get_pixel(x, y).to_rgba32() >> 8)
	return out


func _differs(a: int, b: int) -> bool:
	var sum := absi(((a >> 16) & 255) - ((b >> 16) & 255))
	sum += absi(((a >> 8) & 255) - ((b >> 8) & 255)) + absi((a & 255) - (b & 255))
	return float(sum) / 255.0 > CHANGED


## The fixed room in the view's 3D world: a floor, long walls, furniture, thin rails, specks and
## capsules, every mesh in the one toon material.
func _room(world: Node) -> void:
	var material := ToonMaterial.make()
	_box(world, material, Vector3(0, -1, 0), Vector3(760, 2, 520), Color(0.5, 0.45, 0.4))
	var wall := Color(0.85, 0.78, 0.45)
	_box(world, material, Vector3(0, 48, -260), Vector3(760, 96, 12), wall)
	_box(world, material, Vector3(0, 48, 260), Vector3(760, 96, 12), wall)
	_box(world, material, Vector3(-380, 48, 0), Vector3(12, 96, 520), wall)
	_box(world, material, Vector3(380, 48, 0), Vector3(12, 96, 520), wall)
	_box(world, material, Vector3(-80, 48, -80), Vector3(12, 96, 300), wall)
	_box(world, material, Vector3(120, 48, 120), Vector3(300, 96, 12), wall)
	for i in 6:
		var at := Vector3(-260.0 + float(i) * 100.0, 18, -170.0 + float(i % 3) * 120.0)
		_box(
			world,
			material,
			at,
			Vector3(46 + float(i) * 6.0, 36, 38),
			Color.from_hsv(float(i) / 6.0, 0.3, 0.7),
		)
	_box(world, material, Vector3(250, 6, -120), Vector3(140, 3, 2), Color(0.3, 0.3, 0.35))
	_box(world, material, Vector3(250, 6, -100), Vector3(2, 3, 120), Color(0.3, 0.3, 0.35))
	for i in 8:
		_box(
			world,
			material,
			Vector3(-300.0 + float(i) * 30.0, 2, 200),
			Vector3(4, 4, 4),
			Color(0.9, 0.8, 0.3),
		)
	for i in 3:
		var capsule := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 11.0
		mesh.height = 58.0
		capsule.mesh = mesh
		capsule.material_override = material
		capsule.set_instance_shader_parameter(&"base_color", Color(0.4, 0.7, 0.45))
		capsule.position = Vector3(-60.0 + float(i) * 40.0, 29, 40)
		world.add_child(capsule)


func _box(world: Node, material: Material, at: Vector3, size: Vector3, colour: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.set_instance_shader_parameter(&"base_color", colour)
	node.position = at
	world.add_child(node)
