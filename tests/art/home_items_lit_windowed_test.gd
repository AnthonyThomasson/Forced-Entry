extends GameTest
## A home item reads as bright and as colourful as the prop it replaced in the lit 3D picture, in a
## real window (windowed only: the headless renderer draws nothing; #194, D21 "the old
## look kept", `docs/stacked-items.md` SI14). `home_items_keep_the_old_look` compares the painted
## canvases only; the mesh is lit and toon-banded, so a fruit bowl can paint as the old prop and
## still draw as a small dark blob. A played 3D match (garage_home, seed 2); for each of the fruit
## bowl, the bowl, the vase, the mug and the book the OLD prop (`Props.draw` on a flat textured
## sheet, as the painted top lit it) and then the NEW item (`PieceCarries.patched` from the row that
## carries it) stand at the SAME spot under the same camera, so the same light falls on both. What
## each adds to the bare floor must be as bright (pixels over `BRIGHT`) and as saturated (the fruit,
## the flowers) as the old, at least `MIN_SHARE` of it. The barricade's sandbag and the coat rack's
## hat (#194, SI15) are tan and brown, so they are held to the old one's luminance
## (`MIN_LUMA`) against the old painters' drawing. With `HOME_LIT_SHOT_DIR=<dir>` set it saves
## a picture of each. Run: `HOME_LIT_SHOT_DIR=<dir> tools/run_tests.sh --windowed
## --id=art/home_items_lit_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const Props := preload("res://scenes/objects/art/props.gd")
const Tech := preload("res://scenes/objects/art/tech_painter.gd")
const SCRATCH := "user://settings_home_items_lit_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"plan": "garage_home",
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}
## The item's catalogue key, its old prop's name and the pieces whose rows carry it.
const KINDS := [
	["fruit_bowl", "fruit_bowl", ["island"]],
	["bowl", "bowl", ["console_table"]],
	["vase", "vase", ["console_table", "nightstand"]],
	["cup", "mug", ["side_table", "desk", "nightstand", "dresser"]],
	["book", "book", ["desk", "side_table", "nightstand", "console_table"]],
	# The barricade's sandbag and the coat rack's hat (SI15) have no `Props` prop: the old painters'
	# own drawing; they are plain tan and brown, so they are held to the old mean luminance.
	["sandbag", "sandbag", ["barricade"], true],
	["hat", "hat", ["coat_rack"], true],
]
## The luminance (`_mean_luma`) the new sandbag and hat show over the old one's at the least. They
## measure 1.00 (the bag) and 0.93 (the hat: its brim's outline is darker than the old sheet's);
## drawn in the run-down grade, as they were, they measure 0.39 and 0.64.
const MIN_LUMA := 0.85
const ZOOM := 4.0
## The patch of floor each item is looked at over, in px across.
const BOX := 24.0
## A pixel this much unlike the bare floor belongs to the item (its shadow too).
const CHANGED := 0.08
## A pixel at least this bright (the picture's luminance, 0 to 1), as the old fruit was.
const BRIGHT := 0.35
## A pixel at least this saturated and this bright.
const SATURATION := 0.45
const VALUE := 0.3
## What the new item shows of the old's bright pixels (`BRIGHT`) and saturated ones (`SATURATION`:
## the fruit's and the flowers' colours) at the least. The shares measure 0.61 (the fruit bowl),
## 0.63 (the vase), 0.67 (the mug) and 0.75 (the bowl). The cause is the mesh's toon outline: a dark
## ring one art px wide round its silhouette lies over the outer edge of its bright rim, and the
## ring's area in screen px is its length in art px times `ZOOM` squared (an art px is `ZOOM` screen
## px each way); round a bowl 6 px across that is about 450 of the old's 1136 bright screen pixels.
## The fruit's own luminance (a green or an olive is under `BRIGHT`) varies with the colours picked.
## 0.5 leaves a margin of 0.1 under the lowest share; an item drawn as a dull blob shows next to
## no bright pixel.
const MIN_SHARE := 0.5

var _window: SubViewport
var _camera: Camera2D
var _mirror: MeshCarrier
var _world: Node


func describe() -> Dictionary:
	return {
		"name": "A home item reads as bright as the prop it replaced (windowed)",
		"description": "A 3D match in a window, each of the fruit bowl, bowl, vase, mug, book, "
			+ "sandbag and hat twice at one spot (the old prop as a flat textured sheet, the new "
			+ "item): the item's bright and saturated pixels are at least half of the old prop's, "
			+ "a sandbag's and a hat's luminance at least 0.85 of it. Windowed.",
		"tags": ["render", "3d", "windowed", "items", "unbake"],
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.lock_interaction([&"camera"])
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var built := await _start(t)
	if not t.require(not built.is_empty(), "a match started in 3D"):
		return
	var spot := _widest_floor()
	_camera.zoom = Vector2(ZOOM, ZOOM)
	_camera.global_position = spot
	await t.frames(60)
	var bare := await _picture(t, "bare")
	for kind: Array in KINDS:
		var row := _row(kind[0], kind[2])
		if not t.require(not row.is_empty(), "premise: a home top carries a %s" % kind[0]):
			continue
		await _compare(t, kind, row, spot, bare)
	await MainProbe.close(t, _window)


## The item `kind` (a `KINDS` row) at `spot` next to its old prop, both over `bare`: what each
## shows (`row` the carrying row of the item).
func _compare(t: TestContext, kind: Array, row: Dictionary, spot: Vector2, bare: Image) -> void:
	var key: String = kind[0]
	var definition := _item(key, row)
	var sheet := _old(kind[1], spot, definition["color"])
	var old_picture := await _picture(t, key + "_old")
	sheet.queue_free()
	var item := ObjectFactory.spawn(definition, spot, _world, {})
	var new_picture := await _picture(t, key + "_new")
	item.queue_free()
	if kind.size() > 3:
		var old_luma := _mean_luma(old_picture, bare)
		var new_luma := _mean_luma(new_picture, bare)
		t.check(
			new_luma >= old_luma * MIN_LUMA,
			"the new %s is as light as its prop (mean luminance %.3f against %.3f)"
			% [key, new_luma, old_luma],
		)
		return
	var old := _measure(old_picture, bare)
	var new := _measure(new_picture, bare)
	t.require(old.x > 0, "%s's old prop shows over the floor (%d px)" % [key, old.x])
	t.check(
		new.y >= int(old.y * MIN_SHARE),
		"the new %s is as bright as its prop (%d bright px against %d)" % [key, new.y, old.y],
	)
	t.check(
		new.z >= int(old.z * MIN_SHARE),
		"the new %s is as colourful as its prop (%d against %d saturated px)"
		% [key, new.z, old.z],
	)


## Main whole in the window with a played 3D match started and the camera on it: the match built
## (`{}` when it did not start).
func _start(t: TestContext) -> Dictionary:
	_window = SubViewport.new()
	_window.size = SIZE
	_window.world_2d = World2D.new()
	_window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(_window)
	var main := MainProbe.open(_window)
	MainProbe.setup_menu(main).queue_free()
	_camera = Camera2D.new()
	_camera.name = "MainCamera"
	_camera.set_script(CameraScript)
	main.add_child(_camera)
	_camera.make_current()
	var built: Dictionary = await main.start_match(SPEC.duplicate(true))
	if built.is_empty():
		return built
	_camera.set_process(false)
	_camera.set_physics_process(false)
	await t.frames(30)
	_mirror = main.get_node("View3D").carrier
	_world = built["world"]
	for body: Node in PlanProbe.bodies_under(_world):
		if MeshKinds.kind_of(body) == MeshKinds.WALL:
			for proxy in _mirror.proxies_of(body):
				proxy.visible = false
	return built


## The first `carries` row for `key` among `pieces`: `{}` when none.
func _row(key: String, pieces: Array) -> Dictionary:
	for piece: String in pieces:
		for row: Dictionary in WorldGen.object_definition(piece).get("carries", []):
			if row["key"] == key:
				return row
	return {}


## The item's definition as the row that carries it sets it.
func _item(key: String, row: Dictionary) -> Dictionary:
	return PieceCarries.patched(WorldGen.object_definition(key), PieceCarries.patch_of(row))


## The old prop `name` as a flat textured sheet on the floor at `spot`, as the painted top had it.
func _old(name_: String, spot: Vector2, colour: Color) -> MeshInstance3D:
	var c := PixelCanvas.new(48, 48, 7, Vector2.ZERO)  # the flat paint: no light of its own
	if name_ == "sandbag":  # The barricade painter's bag: a rounded box of the bag colour.
		Tech.box(c, Rect2i(16, 20, 15, 8), colour, 4, 3)
	elif name_ == "hat":  # The coat rack painter's hat: a darker brim round a crown.
		var brim := PixelShape.disc(Vector2i(24, 24), 4)
		c.fill(brim, colour.darkened(0.2), 4)
		c.outline(brim, colour.darkened(0.5))
		c.fill(PixelShape.disc(Vector2i(24, 24), 3), colour, 4)
	else:
		Props.draw(c, name_, Vector2i(24, 24))
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		for x in 48:
			var p := c.at(x, y)
			p.a = 1.0 if c.covered(x, y) else 0.0
			image.set_pixel(x, y, p)
	var plane := PlaneMesh.new()  # lit as the painted top was: the textured toon on a flat sheet
	plane.size = Vector2(48, 48) * RenderConfig.unit
	var sheet := MeshNodes.textured(
		plane, ImageTexture.create_from_image(image), Rect2(-24, -24, 48, 48), { "cutout": true },
	) as MeshInstance3D
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.position = Vector3(spot.x, MeshKitConfig.decal_lift, spot.y) * RenderConfig.unit
	_mirror.add_child(sheet)
	return sheet


## The window's picture (saved when asked to).
func _picture(t: TestContext, name_: String) -> Image:
	await t.frames(20)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	var image := _window.get_texture().get_image()
	var dir := OS.get_environment("HOME_LIT_SHOT_DIR")
	if dir != "":
		image.save_png("%s/%s.png" % [dir, name_])
	return image


## What `image` shows over `bare` in the middle box: `(changed, bright, saturated)` pixel counts.
func _measure(image: Image, bare: Image) -> Vector3i:
	var centre := Vector2i(Vector2(image.get_size()) * 0.5)
	var half := int(BOX * ZOOM * 0.5)
	var changed := 0
	var bright := 0
	var saturated := 0
	for y in range(centre.y - half, centre.y + half):
		for x in range(centre.x - half, centre.x + half):
			var p := image.get_pixel(x, y)
			var q := bare.get_pixel(x, y)
			if maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b))) < CHANGED:
				continue
			changed += 1
			bright += 1 if p.get_luminance() >= BRIGHT else 0
			saturated += 1 if p.s >= SATURATION and p.v >= VALUE else 0
	return Vector3i(changed, bright, saturated)


## The mean luminance of the brighter half of what `image` shows over `bare` in the middle box: the
## colour of the item's own faces, not the toon's dark outline ring and a seam (the old prop's flat
## sheet has none).
func _mean_luma(image: Image, bare: Image) -> float:
	var centre := Vector2i(Vector2(image.get_size()) * 0.5)
	var half := int(BOX * ZOOM * 0.5)
	var lumas: Array[float] = []
	for y in range(centre.y - half, centre.y + half):
		for x in range(centre.x - half, centre.x + half):
			var p := image.get_pixel(x, y)
			var q := bare.get_pixel(x, y)
			if maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b))) >= CHANGED:
				lumas.append(p.get_luminance())
	lumas.sort()
	var from := int(lumas.size() * 0.5)
	var sum := 0.0
	for i in range(from, lumas.size()):
		sum += lumas[i]
	return sum / float(maxi(lumas.size() - from, 1))


## The emptiest spot of the house's largest floor: the grid point furthest from every body, where
## nothing stands over or beside the item and the dusk lights it.
func _widest_floor() -> Vector2:
	var best := Rect2()
	for node: Node in _world.get_tree().get_nodes_in_group(&"floors"):
		if _world.is_ancestor_of(node) and node.get("art") != "street":
			var rect := Rect2((node as Node2D).global_position, node.get("size"))
			if rect.get_area() > best.get_area():
				best = rect
	var bodies: Array[Vector2] = []
	for body: Node in PlanProbe.bodies_under(_world):
		if body is Node2D and MeshKinds.kind_of(body) != MeshKinds.FLOOR:
			bodies.append((body as Node2D).global_position)
	var spot := best.get_center()
	var room := -1.0
	for y in range(int(best.position.y) + 40, int(best.end.y) - 40, 10):
		for x in range(int(best.position.x) + 40, int(best.end.x) - 40, 10):
			var near := INF
			for at in bodies:
				near = minf(near, at.distance_to(Vector2(x, y)))
			if near > room:
				room = near
				spot = Vector2(x, y)
	return spot
