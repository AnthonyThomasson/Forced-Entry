extends GameTest
## The commercial, shell and street kinds of a 3D match in a real window (windowed only: the
## headless renderer draws nothing and compiles no shader; #193 phase 2, Objects). A Watch match
## in the downtown district of seed 2 started with 3D chosen, the camera over a shop front, a
## noodle stand, a clinic, a security post, a street with lamps and props and a tower's podium at
## camera zoom 1 and 3, and close on a piece of each kind laid out in a gallery beside the district
## (every catalogue row, the district not holding them all): each piece is shown by its kit mesh,
## the toon bands, outline and glows are in the picture, and the log gate fails the test on any
## shader or engine error. With `COMMERCIAL_SHOT_DIR=<dir>` set it saves a picture of each (and
## `COMMERCIAL_ONLY=shelf_aisle,shop_front,...` takes only those: a window that is not drawn to,
## behind others, stops rendering after some seconds, so a long gallery is taken in parts). Run:
## `COMMERCIAL_SHOT_DIR=<dir> tools/run_tests.sh --windowed \
## --id=objects/furniture_commercial_mesh_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_furniture_commercial_mesh_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"plan": "garage_home",
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}
## The camera zooms a scene is taken at, and the one of a close-up of a kind.
const ZOOMS := [1.0, 3.0]
const CLOSE_ZOOM := 4.0
## The zoom of a piece whose overhang stands high (a lamp's head, an awning): wider, so the post
## and the head are both in the picture.
const HEAD_ZOOM := 2.4
## How far out from an awning's wall, in px, a combatant stands to be under it.
const UNDER := 8.0
## The scenes: a picture name, the art and option (`kind`, or `head` for a streetlight) of the piece
## the camera is put over.
const SCENES := [
	["shop_front", "shop", "counter"],
	["noodle_stand", "noodle", "bar"],
	["clinic", "clinic", "tool_cart"],
	["security_post", "security", "barricade"],
	["street", "street_prop", "vending"],
	["lamps", "streetlight", "cobra"],
	["podium", "podium", ""],
]
## The catalogue rows laid out in the gallery, in rows of `PER_ROW`, `STEP` px apart.
const GALLERY := [
	"monitor_wall", "server_rack", "tool_cart", "cyberware_shelf", "barricade", "scanner_post",
	"lockers", "shop_counter", "shelf_aisle", "drinks_fridge", "snack_machine", "noodle_counter",
	"bar_stool", "noodle_booth", "menu_board", "crate_stack", "wrapped_pallet", "wall_safe",
	"vending_machine", "street_bench", "street_bin", "drain_grate", "litter", "podium", "rebar",
	"rubble", "scaffold", "cement_bags", "wall_stain", "trash", "cables", "cable_nest", "cardboard",
	"puddle", "neon_tube", "streetlight", "street_sign", "awning", "glyph_sign", "car",
]
const PER_ROW := 8
const STEP := Vector2(300.0, 320.0)

var _window: SubViewport
var _camera: Camera2D
var _mirror: WorldMirror
var _world: Node
var _gallery: Dictionary = {}
## The pictures to take (`COMMERCIAL_ONLY`, a comma-separated list of scene names, gallery rows,
## `stencil` and `awning`); every one when it is not set.
var _only := PackedStringArray()


func describe() -> Dictionary:
	return {
		"name": "Commercial, shell and street pieces draw in a 3D match without errors (windowed)",
		"description": "A 3D Watch match in the downtown district: the camera over a shop front, "
			+ "a noodle stand, a clinic, a security post, a street and a podium at two zooms, "
			+ "and close on each kind: the pieces are shown by their kit meshes and the "
			+ "pictures are drawn. Windowed only.",
		"tags": ["render", "3d", "windowed", "meshkit", "furniture", "district"],
		"timeout": 900.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.lock_interaction([&"camera"])
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	_only = OS.get_environment("COMMERCIAL_ONLY").split(",", false)
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
	if not t.require(not built.is_empty(), "a Watch match started in 3D"):
		return
	_camera.set_process(false)
	_camera.set_physics_process(false)
	await t.frames(30)
	_mirror = main.get_node("View3D").mirror
	_world = built["world"]
	_hide_walls(_world)  # full-height walls would stand between the camera and the pieces
	await _scenes(t)
	await _stencils(t)
	await _awning_fade(t, main.get_node("View3D").fade)
	await _gallery_close_ups(t, built["district"])
	await MainProbe.close(t, _window)


## A picture of each scene at each zoom, the camera over the first piece of its kind.
func _scenes(t: TestContext) -> void:
	for scene: Array in SCENES:
		if not _wanted(scene[0]):
			continue
		var piece := _first_of(scene[1], scene[2])
		if not t.require(piece != null, "the district has a %s %s" % [scene[1], scene[2]]):
			continue
		_camera.global_position = piece.global_position
		for zoom: float in ZOOMS:
			_camera.zoom = Vector2(zoom, zoom)
			await t.frames(12)
			_check_rig(t, piece, "the %s of the %s" % [scene[1], scene[0]])
			RenderingServer.force_draw(false)  # on demand: a covered window never draws
			_save("scene_%s_zoom%d" % [scene[0], int(zoom)])


## Every floor stencil the district holds is shown by a flat decal.
func _stencils(t: TestContext) -> void:
	var stencils := _world.get_tree().get_nodes_in_group(DecalFactory.STENCIL_GROUP)
	for sprite: Node in stencils:
		var shown := _mirror.proxies_of(sprite)
		t.check(shown.size() == 1, "the stencil %s is shown by one node" % sprite.name)
	if stencils.is_empty() or not _wanted("stencil"):
		return
	var first := stencils[0] as Sprite2D
	_camera.global_position = first.global_position + first.texture.get_size() * 0.5
	_camera.zoom = Vector2(CLOSE_ZOOM * 0.5, CLOSE_ZOOM * 0.5)
	await t.frames(12)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	_save("kind_stencil")


## Lay every catalogue row of `GALLERY` out beside the `district` and take a close-up of each.
func _gallery_close_ups(t: TestContext, district: Node2D) -> void:
	var bounds := WorldGen.district_bounds(district)
	var origin := Vector2(bounds.end.x + 800.0, bounds.position.y)
	for i in GALLERY.size():
		var key: String = GALLERY[i]
		if not _wanted(key):
			continue
		var at := origin + Vector2(i % PER_ROW, int(i / float(PER_ROW))) * STEP
		var piece := ObjectFactory.spawn(WorldGen.object_definition(key), at, _world, {})
		_gallery[key] = piece
	await t.frames(20)
	for key: String in _gallery:
		var piece: Node2D = _gallery[key]
		var reach: Rect2 = piece.look.overhang_rect()
		# A piece with an overhang (a lamp's head, an awning) is framed at the part that stands
		# out, wider, so the head is in the picture and not above it.
		var zoom := CLOSE_ZOOM if reach == Rect2() else HEAD_ZOOM
		_camera.zoom = Vector2(zoom, zoom)
		_camera.global_position = piece.global_position + reach.get_center()
		await t.frames(8)
		_check_rig(t, piece, "a %s" % key)
		RenderingServer.force_draw(false)  # on demand: a covered window never draws
		_save("kind_%s" % key)


## A combatant under a real district awning fades it, as 2D's `fade_under` did: the camera frames
## that one combatant (held where it stands), every instance of the awning's mesh thins out, and is
## whole again once the combatant is away.
func _awning_fade(t: TestContext, wall_fade: WallFade) -> void:
	if not _wanted("awning"):
		return
	var awning := _first_of("awning", "")
	var who: Array = _world.get_tree().get_nodes_in_group("characters")
	if not t.require(awning != null and not who.is_empty(), "the district has an awning"):
		return
	var unit := wall_fade.unit_of(awning.get_instance_id())
	if not t.require(unit != null, "the wall fade looks after the awning"):
		return
	var combatant := who[0] as Node2D
	combatant.process_mode = Node.PROCESS_MODE_DISABLED
	_camera.frame([combatant])
	var facing: Vector2 = awning.look.facing
	var out := awning.global_position + facing * UNDER
	_camera.global_position = out
	_camera.zoom = Vector2(CLOSE_ZOOM * 0.5, CLOSE_ZOOM * 0.5)
	combatant.global_position = out
	await t.frames(40)
	var parts := _parts_of(awning)
	t.check(not parts.is_empty(), "the awning is shown by a mesh")
	t.check(
		parts.all(func(p: Node) -> bool: return _level(p) < 0.5),
		"the awning fades while a combatant stands under it",
	)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	_save("awning_faded")
	combatant.global_position = awning.global_position + facing * 900.0
	await t.frames(40)
	t.check(
		parts.all(func(p: Node) -> bool: return _level(p) > 0.99),
		"and whole once it has gone",
	)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	_save("awning_whole")


## Every geometry instance of the mesh shown for `body`.
func _parts_of(body: Node) -> Array:
	var parts: Array = []
	for mesh: Node3D in _mirror.proxies_of(body):
		if mesh is GeometryInstance3D:
			parts.append(mesh)
		parts.append_array(mesh.find_children("*", "GeometryInstance3D", true, false))
	return parts


## The fade level an instance is drawn at (1 whole).
func _level(part: Node) -> float:
	var value: Variant = (part as GeometryInstance3D).get_instance_shader_parameter(&"fade")
	return 1.0 if value == null else float(value)


## Whether the picture of `name` is to be taken (`_only`).
func _wanted(name: String) -> bool:
	return _only.is_empty() or name in _only


## `piece` is shown by a furniture rig, not its proxy box.
func _check_rig(t: TestContext, piece: Node2D, what: String) -> void:
	var rigs := _mirror.proxies_of(piece)
	t.check(rigs.size() == 1 and rigs[0] is FurnitureRig, "%s is shown by a furniture rig" % what)


## Save the window's picture as `<COMMERCIAL_SHOT_DIR>/<name>.png` when the directory is named.
func _save(picture: String) -> void:
	var dir := OS.get_environment("COMMERCIAL_SHOT_DIR")
	if dir != "":
		_window.get_texture().get_image().save_png("%s/%s.png" % [dir, picture])


## Hide the proxies of every wall, so the picture shows what stands inside the rooms (the walls
## fade round the player only in the wall-fade job).
func _hide_walls(world: Node) -> void:
	for body: Node in world.find_children("*", "PhysicsBody2D", true, false):
		if MirrorProxy.kind_of(body) == MirrorProxy.WALL:
			for proxy in _mirror.proxies_of(body):
				proxy.visible = false


## The first piece the match built painted as `art` with the option `kind` (a streetlight's
## `head`; an empty one for any).
func _first_of(art: String, kind: String) -> Node2D:
	for body: Node in _world.find_children("*", "RigidBody2D", true, false):
		var look: Variant = body.get("look")
		if not look is Object or (look as Object).get("art") != art:
			continue
		var opts: Dictionary = (look as Object).get("art_opts")
		if kind == "" or kind in [opts.get("kind", ""), opts.get("head", "")]:
			return body as Node2D
	return null
