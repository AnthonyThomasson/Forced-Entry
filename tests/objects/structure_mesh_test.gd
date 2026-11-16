extends GameTest
## The building's structure in the 3D render (#193 phase 2, `domain-art/meshes.md`): Objects
## registers builders for its walls, house doors and floors (and the street's floor) and the mirror
## shows each by a kit-built mesh in place of its proxy box. Walls stand 96 px with their real
## thickness and the doorways open, one separable instance per segment, and a wall hit and rebuilt
## is meshed again;
## a door's leaf is 84 px tall, follows the 2D door's swing, lies flat when knocked down and loses
## its glass when it shatters; a floor is a flat slab level with the ground in the colour its
## painter draws; the street's road lies a kerb lower than its pavement with the lane and the
## crossing painted flat. Expected numbers are the how-to's (the scale is `RenderConfig.unit`); the
## look is only judged in a window (`structure_mesh_windowed_test.gd`).

const MainProbe := preload("res://tests/_main/main_probe.gd")
const ObjectArt := preload("res://scenes/objects/art/object_art.gd")
const SCRATCH := "user://settings_structure_mesh_test.json"
const WALL_HEIGHT := 96.0
const DOOR_HEIGHT := 84.0
const FLOOR_THICKNESS := 2.0
## How far a room floor's top stands over the ground (clear of the pavement slab it lies in).
const FLOOR_LIFT := 0.1
const KERB := 3.0
const MARK_LIFT := 0.3
const THICKNESS := 12.0
## How far a door's hinge stands from its doorway's middle: half the 52 px opening less the wall's
## half thickness that reaches into it.
const JAMB := 20.0
const DOORWAYS := [Vector2(400, 100), Vector2(400, 220)]
const MATCH := {
	"seed": 2,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}

## How many times the wall builder has been asked.
var wall_builds := 0


func describe() -> Dictionary:
	return {
		"name": "Walls, doors, floors and the street are shown by kit-built meshes",
		"description": "Objects' structure builders: a wall is 96 px tall per segment at its "
			+ "collider's footprint with its doorways open and meshed again when hit; a door's "
			+ "leaf is 84 px tall, swings with the 2D door, lies flat when down; a floor is a flat "
			+ "slab; the road lies a kerb below the pavement with its paint flat; Main registers "
			+ "them.",
		"tags": ["mirror", "3d", "render", "meshkit", "walls", "doors", "floors"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 300) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 300) },
	], [
		_doorway(DOORWAYS[0], "front", "hollow", "flush"),
		_doorway(DOORWAYS[1], "glassy", "glass", "panes"),
	], { "thickness": THICKNESS })
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func _doorway(pos: Vector2, id: String, material: String, style: String) -> Dictionary:
	return {
		"pos": pos, "width": 52.0,
		"door": {
			"name": id, "material": material, "style": style,
			"hinge": pos - Vector2(0, JAMB), "swing_into": Vector2.RIGHT,
		},
	}


func run(t: TestContext) -> void:
	await t.frames(5)
	var mirror := _mirror(t)
	ObjectMeshes.register(mirror.builders)
	var wall_builder: Callable = mirror.builders[MirrorProxy.WALL]
	mirror.builders[MirrorProxy.WALL] = func(body: Node2D) -> Node3D:
		wall_builds += 1
		return wall_builder.call(body)
	for key: StringName in [
		MirrorProxy.WALL, MirrorProxy.DOOR, MirrorProxy.FLOOR, MirrorProxy.floor_key("street"),
	]:
		t.check(mirror.builders.has(key), "Objects registers a builder under '%s'" % key)
	mirror.mirror(t.world)
	await t.frames(3)
	_walls(t, mirror)
	_floors(t, mirror)
	await _doors(t, mirror)
	await _street(t, mirror)
	await _hit_wall(t, mirror)
	await _half_scale(t)
	await _check_main(t)


## Every wall of the layout, shown by one node of a separable instance per segment.
func _walls(t: TestContext, mirror: WorldMirror) -> void:
	var walls := _walls_of(t)
	t.check(walls.size() >= 2, "the layout has walls (%d)" % walls.size())
	var covered := 0
	for wall in walls:
		var node := _own_mesh(mirror, wall)
		if not t.require(node != null, "%s is shown by a mesh of its own" % wall.name):
			continue
		var shapes: Dictionary = wall.segment_shapes()
		t.expect_eq(
			node.get_child_count(), shapes.size(), "%s: one instance per segment" % wall.name
		)
		for i: int in shapes:
			var part := node.get_node_or_null("Segment%d" % i) as MeshInstance3D
			if t.require(part != null, "%s: segment %d is its own instance" % [wall.name, i]):
				covered += _segment(t, wall, part, shapes[i][0] as CollisionShape2D)
		_check_wall_colours(t, node, wall)
	t.expect_eq(covered, 0, "no wall stands in a doorway")


## One wall segment's mesh `part`: its collider's size and place, 96 px tall on the ground. The
## number of doorways its footprint covers.
func _segment(
	t: TestContext,
	wall: Node,
	part: MeshInstance3D,
	shape_node: CollisionShape2D,
) -> int:
	var what := "%s %s" % [wall.name, part.name]
	var size := (shape_node.shape as RectangleShape2D).size
	var box := part.mesh.get_aabb()
	t.expect_near(box.size.x, size.x, 0.01, "%s: as long as its collider" % what)
	t.expect_near(box.size.z, size.y, 0.01, "%s: as thick as its collider" % what)
	# A wall along z stands a hair (`wall_cross_lift`) taller than one along x.
	t.expect_near(box.size.y, WALL_HEIGHT, 0.02, "%s: 96 px tall" % what)
	t.expect_near(box.position.y, 0.0, 0.01, "%s: standing on the ground" % what)
	var at := part.global_position
	var world_at: Vector2 = wall.to_global(shape_node.position)
	t.expect_near(at.x, world_at.x, 0.01, "%s: over its collider (x)" % what)
	t.expect_near(at.z, world_at.y, 0.01, "%s: over its collider (z)" % what)
	var footprint := Rect2(
		Vector2(at.x, at.z) + Vector2(box.position.x, box.position.z),
		Vector2(box.size.x, box.size.z),
	)
	var covered := 0
	for doorway: Vector2 in DOORWAYS:
		covered += 1 if footprint.has_point(doorway) else 0
	return covered


## A wall with art wears its painter's flat tile: white faces (the art colours them) and a textured
## material showing the tile (the painter's art, drawn flat), every segment one tile's material.
func _check_wall_colours(t: TestContext, node: Node3D, wall: Node) -> void:
	var part := node.get_child(0) as MeshInstance3D
	var arrays := (part.mesh as ArrayMesh).surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var top_seen := false
	var side_seen := false
	for i in normals.size():
		if normals[i].dot(Vector3.UP) > 0.99:
			top_seen = true
		elif absf(normals[i].y) < 0.01:
			side_seen = true
		t.check(
			colours[i].is_equal_approx(Color.WHITE),
			"%s: faces are white for the tile" % wall.name,
		)
	t.check(top_seen and side_seen, "%s: the mesh has a top and sides" % wall.name)
	var material := part.material_override as ShaderMaterial
	if not t.require(material != null, "%s: a textured material" % wall.name):
		return
	var tile := material.get_shader_parameter(&"albedo_texture") as Texture2D
	t.check(tile != null, "%s: its cap tile is the material's texture" % wall.name)
	t.check(material.get_shader_parameter(&"tiled") == true, "%s: the tile repeats" % wall.name)


## Each room's floor: a flat slab level with the ground at the floor's footprint and colour.
func _floors(t: TestContext, mirror: WorldMirror) -> void:
	var floors := t.world.get_tree().get_nodes_in_group(&"floors").filter(
		func(node: Node) -> bool: return t.world.is_ancestor_of(node)
	)
	t.check(floors.size() >= 2, "the layout has floors (%d)" % floors.size())
	for floor_node: Node2D in floors:
		var shown := mirror.proxies_of(floor_node)
		if not t.require(shown.size() == 1 and shown[0] is MeshInstance3D,
				"%s is shown by one mesh" % floor_node.name):
			continue
		var node := shown[0] as MeshInstance3D
		if node.mesh is BoxMesh:
			t.check(false, "%s is shown by a mesh of the kit, not its proxy box" % floor_node.name)
			continue
		var size: Vector2 = floor_node.size
		var box := node.mesh.get_aabb()
		t.expect_near(box.size.x, size.x, 0.01, "%s: as wide as the floor" % floor_node.name)
		t.expect_near(box.size.z, size.y, 0.01, "%s: as deep as the floor" % floor_node.name)
		t.expect_near(box.size.y, FLOOR_THICKNESS, 0.01, "%s: a thin slab" % floor_node.name)
		t.expect_near(
			box.end.y,
			FLOOR_LIFT,
			0.01,
			"%s: its top just over the ground" % floor_node.name,
		)
		t.expect_near(node.global_position.x, floor_node.global_position.x, 0.01,
				"%s: at the floor's corner (x)" % floor_node.name)
		t.expect_near(node.global_position.z, floor_node.global_position.y, 0.01,
				"%s: at the floor's corner (z)" % floor_node.name)
		var material := node.material_override as ShaderMaterial
		if t.require(material != null, "%s: wears a textured material" % floor_node.name):
			var tile := material.get_shader_parameter(&"albedo_texture") as Texture2D
			var painted := ObjectArt.tile_flat(
				floor_node.art, floor_node.color, floor_node.floor_material, floor_node.art_opts
			)
			t.check(tile == painted, "%s: its painter's flat tile" % floor_node.name)
			t.check(
				material.get_shader_parameter(&"tiled") == true,
				"%s: repeated" % floor_node.name,
			)
		t.check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s: the ground casts no shadow" % floor_node.name)


## A door's leaf: 84 px tall at the 2D leaf's length, following its swing, lying when knocked down,
## losing the glass when it shatters.
func _doors(t: TestContext, mirror: WorldMirror) -> void:
	var door := t.object(&"front")
	var shown := mirror.proxies_of(door)
	if not t.require(not shown.is_empty() and shown[0] is DoorMesh, "the door is a DoorMesh"):
		return
	var node := shown[0]
	var leaf := node.get_child(0) as MeshInstance3D
	var box := leaf.mesh.get_aabb()
	var size: Vector2 = door.leaf_size()
	t.expect_near(box.size.x, size.x, 0.01, "the leaf is as long as the 2D leaf")
	t.expect_near(box.size.y, DOOR_HEIGHT, 0.01, "the leaf stands 84 px")
	t.check(box.size.z >= size.y, "the leaf is at least as thick as the 2D leaf")
	t.expect_near(box.position.y, 0.0, 0.01, "the leaf stands on the ground")
	t.check(leaf.visible and node.get_child_count() == 1, "a standing door shows its leaf only")
	_at_door(t, node, door, "shut")
	var shut_yaw := node.global_rotation.y
	door.toggle(null)
	await t.seconds(0.2)
	t.check(
		absf(angle_difference(node.global_rotation.y, shut_yaw)) > 0.1,
		"the mesh turns with the leaf as it swings",
	)
	await t.seconds(0.4)
	t.expect_near(door.angle(), 90.0, 0.5, "the door swung open")
	_at_door(t, node, door, "open")
	await _glass(t, mirror)
	door.take_damage(10_000.0)
	await t.frames(2)
	t.check(door.is_down(), "the door is knocked down")
	_lies_flat(t, node, door)


## A glass-panel door loses its glass when its panes shatter.
func _glass(t: TestContext, mirror: WorldMirror) -> void:
	var glassy := t.object(&"glassy")
	var pane := mirror.proxies_of(glassy)[0]
	var whole := (pane.get_child(0) as MeshInstance3D).mesh
	glassy.look.broken = true
	await t.frames(2)
	var broken := (pane.get_child(0) as MeshInstance3D).mesh
	t.check(
		broken != whole and _vertex_count(broken) < _vertex_count(whole),
		"a door whose panes shattered loses its glass",
	)


## A knocked-down door shows the flat slab, where the 2D door lies and as big as it.
func _lies_flat(t: TestContext, node: Node3D, door: Node2D) -> void:
	t.check(
		not node.get_child(0).visible and node.get_child(1).visible,
		"a knocked-down door shows its flat slab",
	)
	var flat := (node.get_child(1) as MeshInstance3D).mesh.get_aabb()
	t.expect_near(flat.size.x, DoorConfig.fallen_length, 0.01, "the fallen door is as long as 2D's")
	t.expect_near(flat.size.z, door.width, 0.01, "the fallen door is as wide as the doorway")
	t.expect_near(flat.size.y, DoorConfig.leaf_thickness, 0.01, "it lies flat, a leaf thick")
	_at_door(t, node, door, "fallen")


## The node stands where `door` is and turned as it is, `when`.
func _at_door(t: TestContext, node: Node3D, door: Node2D, when: String) -> void:
	t.expect_near(node.global_position.x, door.global_position.x, 0.5, "%s: at the door (x)" % when)
	t.expect_near(node.global_position.z, door.global_position.y, 0.5, "%s: at the door (z)" % when)
	t.expect_near(
		absf(angle_difference(node.global_rotation.y, -door.global_rotation)), 0.0, 0.02,
		"%s: turned as the door is" % when,
	)


## The road lies a kerb below the pavement, paint flat on it.
func _street(t: TestContext, mirror: WorldMirror) -> void:
	var road_def: Dictionary = GeneralCatalog.STREET["asphalt"].duplicate(true)
	road_def["marks"] = {
		"seed": 1, "lane": true, "edges": [],
		"crossings": [{ "side": Vector2.RIGHT, "reach": 70.0 }], "glyphs": [],
	}
	var walk_def: Dictionary = GeneralCatalog.STREET["sidewalk"].duplicate(true)
	walk_def["marks"] = { "seed": 2, "edges": [Vector2.DOWN] }
	var road := FloorFactory.spawn(Rect2(1000, 0, 300, 120), road_def, "Road", t.world)
	var walk := FloorFactory.spawn(Rect2(1000, 120, 300, 50), walk_def, "Pavement", t.world)
	await t.frames(3)
	var road_node := _mesh_of(mirror, road)
	var walk_node := _mesh_of(mirror, walk)
	if not t.require(road_node != null and walk_node != null, "the street is shown by meshes"):
		return
	_check_road(t, road_node)
	var walk_box := walk_node.mesh.get_aabb()
	t.expect_near(walk_box.end.y, 0.0, 0.01, "the pavement is level with the ground")
	t.check(walk_box.position.y <= -KERB, "the pavement's edge shows the kerb over the road")
	var kerb := walk_node.get_node_or_null("Paint") as MeshInstance3D
	if t.require(kerb != null, "the kerb band is a Paint mesh over the pavement"):
		t.expect_near(kerb.mesh.get_aabb().end.y, MARK_LIFT, 0.01, "the kerb band lies over it")
		t.check(_marks(kerb.mesh as ArrayMesh, 0.0).size() > 0, "the kerb is a band on its edge")
	for node: MeshInstance3D in [road_node, walk_node]:
		t.check(node.material_override is ShaderMaterial, "a street slab wears its tile")


## The road is a slab a kerb down, its lane and its crossing painted flat on it.
func _check_road(t: TestContext, road_node: MeshInstance3D) -> void:
	t.expect_near(
		road_node.mesh.get_aabb().position.y, -KERB - FLOOR_THICKNESS, 0.01, "the road is a slab"
	)
	var paint := road_node.get_node_or_null("Paint") as MeshInstance3D
	if not t.require(paint != null, "the road's paint is a Paint mesh over the slab"):
		return
	var marks := _marks(paint.mesh as ArrayMesh, -KERB)
	t.check(marks.size() > 0, "paint lies flat on the road, %.1f px over it" % MARK_LIFT)
	var dash := false
	var bars := false
	for p in marks:
		dash = dash or (p.x < 230.0 and absf(p.z - 60.0) <= 2.0)
		bars = bars or p.x > 230.0
	t.check(dash, "the lane's dashes run down the middle of the road")
	t.check(bars, "the junction's crossing is painted at the road's end")
	t.check(
		road_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the road casts no shadow",
	)


## A wall hit meshes only the struck segment, once: the node stays, the builder is not asked
## again, one segment instance is replaced and the others are the very same.
func _hit_wall(t: TestContext, mirror: WorldMirror) -> void:
	var wall := _walls_of(t)[0]
	var before := _own_mesh(mirror, wall) as WallMesh
	var ids: Array[int] = []
	for part in before.get_children():
		ids.append(part.get_instance_id())
	var builds := wall_builds
	var hit := HitInfo.new()
	hit.position = wall.to_global(Vector2(60.0, 0.0))
	hit.normal = Vector2.DOWN
	hit.direction = Vector2.UP
	hit.damage = 60.0
	hit.speed_factor = 1.0
	wall.take_hit(hit)
	await t.frames(6)
	t.check(_own_mesh(mirror, wall) == before, "a hit wall keeps its mesh node")
	t.expect_eq(wall_builds, builds, "a hit does not build the wall's mesh again")
	t.expect_eq(before.rebuilds, 1, "a hit rebuilds one segment, once")
	var after: Array[Node] = before.get_children()
	t.expect_eq(after.size(), ids.size(), "every segment is still its own instance")
	var replaced := 0
	for part in after:
		replaced += 0 if ids.has(part.get_instance_id()) else 1
	t.expect_eq(replaced, 1, "only the struck segment's instance was replaced")
	var dented := 0
	for part: MeshInstance3D in after:
		dented += 1 if _vertex_count(part.mesh) > 36 else 0
	t.check(dented >= 1, "the struck segment is built from its dented colliders")


## Half scale halves the wall, the door and the floor in every direction.
func _half_scale(t: TestContext) -> void:
	RenderConfig.unit = 0.5
	var halved := _mirror(t)
	ObjectMeshes.register(halved.builders)
	halved.mirror(t.world)
	await t.frames(3)
	var wall := _own_mesh(halved, _walls_of(t)[0])
	if t.require(wall != null, "a wall at half scale is shown by a mesh"):
		t.expect_near((wall.get_child(0) as MeshInstance3D).mesh.get_aabb().size.y,
				WALL_HEIGHT * 0.5, 0.01, "a wall at half scale stands half as tall")
	var door_node := halved.proxies_of(t.object(&"front"))
	if t.require(not door_node.is_empty(), "a door at half scale is shown"):
		var leaf := (door_node[0] as Node3D).get_child(0) as MeshInstance3D
		t.expect_near(
			leaf.mesh.get_aabb().size.y, DOOR_HEIGHT * 0.5, 0.01, "a half-scale door is half high"
		)
	RenderConfig.unit = 1.0


## Main's 3D view registers the structure's builders.
func _check_main(t: TestContext) -> void:
	var window := MainProbe.viewport(t)
	var main := MainProbe.open(window)
	MainProbe.setup_menu(main).queue_free()
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	main.add_child(camera)
	var built: Dictionary = await main.start_match(MATCH.duplicate(true))
	if not t.require(not built.is_empty(), "a 3D match started"):
		return
	await t.frames(4)
	var view := main.get_node_or_null("View3D")
	if t.require(view != null, "Main built the 3D view"):
		for key: StringName in [MirrorProxy.WALL, MirrorProxy.DOOR, MirrorProxy.FLOOR]:
			t.check(view.mirror.builders.has(key), "Main's view registers the '%s' builder" % key)
		var shown := 0
		for body: Node in (built["world"] as Node).find_children("*", "StaticBody2D", true, false):
			if body.has_method(&"segment_shapes") and _own_mesh(view.mirror, body) != null:
				shown += 1
		t.check(shown > 0, "the match's walls are shown by their meshes")
	await MainProbe.close(t, window)


## The walls of the layout (a `StaticBody2D` with `wall_segments`).
func _walls_of(t: TestContext) -> Array[Node]:
	var out: Array[Node] = []
	for node in t.world.find_children("*", "StaticBody2D", true, false):
		if node.has_method(&"wall_segments"):
			out.append(node)
	return out


## The mesh node of `body` when the mirror shows it by one of a domain's own (not a plain proxy).
func _own_mesh(mirror: WorldMirror, body: Node) -> Node3D:
	var shown := mirror.proxies_of(body)
	if shown.size() != 1 or shown[0] is MeshInstance3D:
		return null
	return shown[0]


## The `MeshInstance3D` of `floor_node` when the mirror shows it by a kit mesh.
func _mesh_of(mirror: WorldMirror, floor_node: Node) -> MeshInstance3D:
	var shown := mirror.proxies_of(floor_node)
	if shown.size() != 1 or not shown[0] is MeshInstance3D:
		return null
	var node := shown[0] as MeshInstance3D
	return null if node.mesh is BoxMesh else node


## The vertices of `mesh` facing up at height `top` + the paint's lift.
func _marks(mesh: ArrayMesh, top: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		if normals[i].dot(Vector3.UP) > 0.99 and is_equal_approx(vertices[i].y, top + MARK_LIFT):
			out.append(vertices[i])
	return out


func _vertex_count(mesh: Mesh) -> int:
	var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
