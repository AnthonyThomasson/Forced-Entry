extends GameTest
## A house door's 3D leaf wears the door painter's flat art as the 2D door shows it (#193 phase 2b):
## a shattered glass door is its two stiles alone (the floor shows through the empty panes, as in
## 2D, not a white sill), a knocked-down door is the same leaf, lying as its free body does (#194
## doors3d, D18), and the art is laid again when the panes shatter on a door that already lies. The
## painted handle of the flat leaf is dropped (the 3D leaf has a handle mesh of its own).

const ObjectArt := preload("res://scenes/objects/art/object_art.gd")
const Probe := preload("res://tests/_objects/piece_probe.gd")
const SCRATCH := "user://settings_structure_door_art_test.json"


func describe() -> Dictionary:
	return {
		"name": "A door's 3D leaf wears its 2D art: shattered, fallen",
		"description": "A shattered glass leaf is its stiles alone; a fallen door is the same leaf "
			+ "lying as its free body does, its art laid again when the panes shatter while it "
			+ "lies; the flat leaf paints no handle.",
		"tags": ["mirror", "3d", "render", "doors", "art"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 300) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 300) },
	], [{
		"pos": Vector2(400, 220), "width": 52.0,
		"door": {
			"name": "glassy", "material": "glass", "style": "panes",
			"hinge": Vector2(400, 200), "swing_into": Vector2.RIGHT,
		},
	}], { "thickness": 12.0 })
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(ArtCanvasConfig, &"pixel_size", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	await t.frames(5)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	view.add_child(mirror)
	ObjectMeshes.register(mirror.builders)
	mirror.carry(t.world)
	await t.frames(3)
	var door := t.object(&"glassy")
	var node := mirror.proxies_of(door)[0] as DoorMesh
	_flat_leaf(t, door)
	await _shattered_leaf(t, door, node)
	await _fallen(t, door, node)
	await _shattered_while_lying(t, door, node)


## The flat standing leaf paints no handle (the 3D leaf's handle is a mesh).
func _flat_leaf(t: TestContext, door: Node2D) -> void:
	var size: Vector2 = door.leaf_size()
	var opts: Dictionary = door.look.art_opts()
	var flat := ObjectArt.flat("door", size, door.look.color, opts).get_image()
	var handle := ObjectArtDoorConfig.handle_color
	t.expect_eq(_count(flat, handle), 0, "the flat leaf paints no handle")


## How many pixels of `image` are `colour` (to the image's 8 bits).
func _count(image: Image, colour: Color) -> int:
	var n := 0
	for y in image.get_height():
		for x in image.get_width():
			n += 1 if _near(image.get_pixel(x, y), colour) else 0
	return n


## A glass door whose panes shattered is its two stiles alone: no sill, no rail over the empty panes
## (a clear texel would show white), and the leaf wears the broken art.
func _shattered_leaf(t: TestContext, door: Node2D, node: DoorMesh) -> void:
	var leaf := node.get_child(0) as MeshInstance3D
	var whole := _lowest_up_face(leaf.mesh)
	door.look.broken = true
	await t.frames(2)
	var size: Vector2 = door.leaf_size()
	var art := ObjectArt.flat("door", size, door.look.color, door.look.art_opts())
	t.check(_texture_of(leaf) == art, "the leaf wears the shattered art")
	t.expect_near(
		whole, ObjectStructureMeshConfig.door_sill, 0.01, "a whole glass leaf has its sill's top"
	)
	t.expect_near(
		_lowest_up_face(leaf.mesh),
		ObjectStructureMeshConfig.door_height,
		0.01,
		"a shattered one has no sill: its stiles' tops are all that is left",
	)
	var aabb := leaf.mesh.get_aabb()
	t.expect_near(aabb.size.x, size.x, 0.01, "the stiles still stand the leaf's length apart")
	t.check(_up_area(leaf.mesh) < size.x * size.y * 0.5, "the empty panes are open to the floor")


## A knocked-down door is the same leaf (its shattered art, no slab), lying as its free body does.
func _fallen(t: TestContext, door: Node2D, node: DoorMesh) -> void:
	door.take_damage(10_000.0)
	t.check(door.is_down(), "the door is knocked down")
	await Probe.settle(t, door, 12.0)
	await t.frames(3)
	var leaf := node.get_child(0) as MeshInstance3D
	var art := ObjectArt.flat("door", door.leaf_size(), door.look.color, door.look.art_opts())
	t.check(node.get_child_count() == 1 and leaf.visible, "it is still its one leaf, shown")
	t.check(_texture_of(leaf) == art, "wearing its art as before")
	var lead := TwinSpace.leader_of(door)
	if t.require(lead != null, "its free body leads it"):
		t.check(
			node.global_transform.is_equal_approx(lead.global_transform),
			"the leaf lies as that body does, tilt and all",
		)
		t.check(absf(node.global_transform.basis.y.y) < 0.3, "on its side")


## The panes shattering while the door lies lay the leaf's art and mesh again.
func _shattered_while_lying(t: TestContext, door: Node2D, node: DoorMesh) -> void:
	var leaf := node.get_child(0) as MeshInstance3D
	door.look.broken = false
	await t.frames(2)
	var whole_art := _texture_of(leaf)
	var size: Vector2 = door.leaf_size()
	t.check(_up_area(leaf.mesh) > size.x * size.y * 0.5, "whole panes: a whole leaf")
	door.look.broken = true
	await t.frames(2)
	t.check(_texture_of(leaf) != whole_art, "the leaf wears the shattered art after it shatters")
	t.check(_up_area(leaf.mesh) < size.x * size.y * 0.5, "and is open")


## The texture a textured mesh instance shows (null when it has none).
func _texture_of(node: MeshInstance3D) -> Texture2D:
	return null if node.material_override == null else MeshNodes.shown_texture(node)


## The height of the lowest up-facing face of `mesh` (px).
func _lowest_up_face(mesh: Mesh) -> float:
	var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var low := INF
	for i in vertices.size():
		if normals[i].dot(Vector3.UP) > 0.99:
			low = minf(low, vertices[i].y)
	return low


## The area of the up-facing triangles of `mesh` seen from above (what covers the floor, px
## squared).
func _up_area(mesh: Mesh) -> float:
	var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var area := 0.0
	for i in range(0, vertices.size() - 2, 3):
		if normals[i].dot(Vector3.UP) > 0.99:
			var a := vertices[i + 1] - vertices[i]
			var b := vertices[i + 2] - vertices[i]
			area += a.cross(b).length() * 0.5
	return area


## Whether two colours are one to the image's 8 bits.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.03
