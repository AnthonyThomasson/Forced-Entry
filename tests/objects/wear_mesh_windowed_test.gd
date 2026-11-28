extends GameTest
## Wear and decals of a 3D match in a real window (windowed only: the headless renderer draws
## nothing and compiles no shader; #193 phase 2, Objects). A Watch match started with 3D chosen,
## the camera parked over a worn room (floor marks and a mark on the wall), a road with a lane
## glyph and a floor stencil, each at zoom 1 (the game's default) and zoom 3 (closest): the decals
## are drawn without shader or engine errors (the log gate). With `WEAR_SHOT_DIR=<dir>` set it
## saves a picture of each. Run: `tools/run_tests.sh --windowed --id=objects/wear_mesh_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_wear_mesh_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const ZOOMS := [1.0, 3.0]
## The wall marks the room is picked by, most visible first.
const SHOWN_KINDS := ["peel", "cable", "wall_crack", "wall_stain"]
## How far off square (degrees) the camera looks at a wall's face.
const FACE_OFFSET := 25.0
const SPEC := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}

## The window the match is drawn in.
var window: SubViewport


func describe() -> Dictionary:
	return {
		"name": "Wear, glyphs and stencils draw in a 3D match (windowed)",
		"description": "A 3D Watch match, the camera over a worn room, a road with a lane glyph "
			+ "and a floor stencil at zoom 1 and 3: the decals are drawn without shader or "
			+ "engine errors. Windowed only.",
		"tags": ["render", "3d", "windowed", "meshkit", "wear", "decals"],
		"timeout": 150.0,
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
	window = SubViewport.new()
	window.size = SIZE
	window.world_2d = World2D.new()
	window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(window)
	var main := MainProbe.open(window)
	MainProbe.setup_menu(main).queue_free()
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	camera.set_script(CameraScript)
	main.add_child(camera)
	camera.make_current()
	var built: Dictionary = await main.start_match(SPEC.duplicate(true))
	if not t.require(not built.is_empty(), "a Watch match started in 3D"):
		return
	camera.set_process(false)
	camera.set_physics_process(false)
	var world: Node = built["world"]
	await t.frames(30)
	var room := _worn_room(world)
	if t.require(not room.is_empty(), "the match has a room with floor and wall marks"):
		await _shoot_room(t, main, camera, room)
	var road := _road_with_glyph(world)
	if t.require(road != null, "the match has a road with a lane glyph"):
		var glyph: Rect2 = road.find_child("StreetMarks", true, false).laid("glyph")[0]
		await _shoot_all(t, camera, road.global_position + glyph.get_center(), "street_glyph")
	var lobby := WorldGen.get_lobbies(built["house"])
	if t.require(not lobby.is_empty(), "the match has a lobby stencil"):
		await _shoot_all(t, camera, (lobby[0]["rect"] as Rect2).get_center(), "lobby_stencil")
	await MainProbe.close(t, window)


## The worn room's decals are there, and the camera looks at the wall's face from inside the room,
## a little off square.
func _shoot_room(t: TestContext, main: Node, camera: Camera2D, room: Dictionary) -> void:
	_check_room(t, main, room)
	var rig: CameraRig = main.get_node("View3D").rig
	var normal: Vector2 = room["mark"]["normal"]
	rig.yaw = rad_to_deg(atan2(normal.x, normal.y)) + FACE_OFFSET
	await _shoot_all(t, camera, _wall_spot(room), "worn_room")
	rig.yaw = RenderConfig.yaw_degrees


## Each shot of `name` at every zoom.
func _shoot_all(t: TestContext, camera: Camera2D, at: Vector2, shot_name: String) -> void:
	for zoom: float in ZOOMS:
		camera.zoom = Vector2(zoom, zoom)
		camera.global_position = at
		await t.frames(20)
		RenderingServer.force_draw(false)  # on demand: a covered window never draws
		var dir := OS.get_environment("WEAR_SHOT_DIR")
		if dir != "":
			window.get_texture().get_image().save_png(
				"%s/%s_zoom%d.png" % [dir, shot_name, int(zoom)]
			)


## The room's mesh shows its marks: decals on its floor and on a wall segment.
func _check_room(t: TestContext, main: Node, room: Dictionary) -> void:
	var mirror: MeshCarrier = main.get_node("View3D").carrier
	var floor_shown := mirror.proxies_of(room["floor"])
	t.check(
		not floor_shown.is_empty() and floor_shown[0].get_child_count() > 0,
		"the room's floor mesh carries decals",
	)
	var wall_shown := mirror.proxies_of(room["wall"])
	var on_walls := 0
	if not wall_shown.is_empty() and wall_shown[0] is WallMesh:
		for part: Node in (wall_shown[0] as WallMesh).segments().values():
			on_walls += part.get_child_count()
	t.check(on_walls > 0, "the room's wall segments carry decals (%d)" % on_walls)


## A floor of the match whose room has floor marks and a wall mark, the most visible kind of wall
## mark first (`SHOWN_KINDS`: a stain is faint): `{ floor, wall, wear, mark }`, or `{}`.
func _worn_room(world: Node) -> Dictionary:
	for kind: String in SHOWN_KINDS:
		for node: Node in world.get_tree().get_nodes_in_group(&"floors"):
			var wear: Variant = node.get("wear")
			if not world.is_ancestor_of(node) or not is_instance_valid(wear):
				continue
			var marks: Array = wear.wall_marks().filter(
				func(m: Dictionary) -> bool: return m["kind"] == kind
			)
			if wear.floor_marks().is_empty() or marks.is_empty():
				continue
			for wall in node.get_parent().get_children():
				if wall.has_method(&"wall_segments") and wall.get("wear") == wear:
					return { "floor": node, "wall": wall, "wear": wear, "mark": marks[0] }
	return {}


## Where to look at the room: the foot of the wall mark.
func _wall_spot(room: Dictionary) -> Vector2:
	return (room["wear"] as Node2D).to_global(room["mark"]["at"])


## The first road piece of the match whose marks hold a lane glyph.
func _road_with_glyph(world: Node) -> Node2D:
	for node: Node in world.get_tree().get_nodes_in_group(&"floors"):
		if not world.is_ancestor_of(node) or node.get("art") != "street":
			continue
		var layer := node.find_child("StreetMarks", true, false)
		if layer != null and not layer.laid("glyph").is_empty():
			return node as Node2D
	return null
