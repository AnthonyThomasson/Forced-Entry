extends GameTest
## The structure's 3D meshes wear the 2D art (#193 phase 2b, `domain-objects/structure-meshes.md`):
## a wall's cap tile, a floor's and the street's tile, a door's leaf, painted flat (no baked light)
## and laid by `MeshNodes.textured`. The wall tile runs along the wall as the 2D wall maps it
## (across the thickness flipped for a wall along +x, transposed for one
## along z, not rotated), from the segment's start, the floor tile from the floor's `tile_offset`.
## One texture serves every piece of its kind, so the materials are few. The wall painter's flat
## read drops the trim and the outline rows.

const ObjectArt := preload("res://scenes/objects/art/object_art.gd")
const SCRATCH := "user://settings_structure_skin_test.json"
const THICKNESS := 12.0
const TILE := Vector2(48, 12)


func describe() -> Dictionary:
	return {
		"name": "Walls, doors, floors and the street wear the 2D art in 3D",
		"description": "The structure meshes are textured with the painters' flat tiles: a wall's "
			+ "cap tile along the wall (turned for a wall along z), a floor's repeated from its "
			+ "tile offset, a door's leaf with a plain handle, a few shared materials; the wall "
			+ "painter's flat read drops its trim and outline rows.",
		"tags": ["mirror", "3d", "render", "walls", "doors", "floors", "art"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 300) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 300) },
	], [{
		"pos": Vector2(400, 100), "width": 52.0,
		"door": {
			"name": "front", "material": "hollow", "style": "panelled",
			"hinge": Vector2(400, 80), "swing_into": Vector2.RIGHT,
		},
	}], { "thickness": THICKNESS })
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
	_wall_painter(t)
	await t.frames(5)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	ObjectMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(3)
	_walls(t, mirror)
	_floors(t, mirror)
	_door(t, mirror)
	_grout(t)
	_prewarm(t)


## A flat wall tile has no trim or outline rows (its edge rows are the cap's own plaster or brick).
func _wall_painter(t: TestContext) -> void:
	var colour := Color(0.87, 0.81, 0.49)
	for pattern: String in ["plaster", "brick"]:
		var flat := ObjectArt.flat("wall", TILE, colour, { "pattern": pattern }).get_image()
		var tones := ArtSurfaceConfig.tones(ObjectArt.drawn_color(colour))
		var last := flat.get_height() - 1
		var flat_outlined := 0
		for x in flat.get_width():
			flat_outlined += 1 if _near(flat.get_pixel(x, 0), tones.outline) else 0
			flat_outlined += 1 if _near(flat.get_pixel(x, last), tones.outline) else 0
		t.expect_eq(flat_outlined, 0, "the flat %s tile has no outline row" % pattern)


## Every wall segment wears the cap tile, along its length: a wall along z the tile turned a
## quarter; the segments of a direction share one material.
func _walls(t: TestContext, mirror: WorldMirror) -> void:
	var materials := {}
	var checked := 0
	for wall in t.world.find_children("*", "StaticBody2D", true, false):
		if not wall.has_method(&"segment_shapes"):
			continue
		var node := mirror.proxies_of(wall)[0] as WallMesh
		var parts := node.segments()
		for index: int in parts:
			var seg: PackedVector2Array = wall.wall_segments()[index]
			var material := _segment(t, wall, parts[index], seg)
			materials[material] = true
			checked += 1
	t.check(checked > 4, "the layout's walls were checked (%d)" % checked)
	t.check(
		materials.size() <= 2,
		"the walls share one material a direction (%d)" % materials.size(),
	)


## One wall segment `part` (`seg` of `wall`) wears a tile of the right size, oriented as the 2D wall
## maps it, laid from the segment's start; its material.
func _segment(
	t: TestContext,
	wall: Node,
	part: MeshInstance3D,
	seg: PackedVector2Array,
) -> ShaderMaterial:
	var material := part.material_override as ShaderMaterial
	if not t.require(material != null, "%s is textured" % part.name):
		return null
	var tile := material.get_shader_parameter(&"albedo_texture") as Texture2D
	var along_x := absf(seg[1].x - seg[0].x) >= absf(seg[1].y - seg[0].y)
	var along := Vector2(ObjectArtWallConfig.tile_px, THICKNESS)
	var wanted := along if along_x else Vector2(along.y, along.x)
	t.expect_eq(
		tile.get_size(), wanted / ArtCanvasConfig.pixel_size, "%s: the tile's size" % part.name
	)
	_phase(t, part, seg, wanted, along_x)
	_oriented(t, wall, tile, seg, along_x)
	return material


## The rect a tile is laid over: one tile big, its corner at the segment's start (x walls: the
## start's x, the centre line less half the thickness; z walls: the centre line less half, the
## start's z), in the part's own frame (its origin the collider's centre).
func _phase(
	t: TestContext,
	part: MeshInstance3D,
	seg: PackedVector2Array,
	wanted: Vector2,
	along_x: bool,
) -> void:
	var rect: Vector4 = part.get_instance_shader_parameter(&"uv_rect")
	var half := THICKNESS * 0.5
	var corner := Vector2(
		seg[0].x,
		seg[0].y - half,
	) if along_x else Vector2(seg[0].x - half, seg[0].y)
	var at := corner - Vector2(part.position.x, part.position.z)
	t.expect_near(rect.x, at.x, 0.001, "%s: the tile starts at the segment's start (x)" % part.name)
	t.expect_near(rect.y, at.y, 0.001, "%s: and its edge (z)" % part.name)
	t.expect_near(rect.z, wanted.x, 0.001, "%s: one tile covers the tile's width" % part.name)
	t.expect_near(rect.w, wanted.y, 0.001, "%s: and its depth" % part.name)


## The pixel (x, y) of a tile oriented for a segment: `base`'s as the 2D wall maps it.
func _expected(base: Image, x: int, y: int, along_x: bool, forward: bool) -> Color:
	var last := Vector2i(base.get_width() - 1, base.get_height() - 1)
	if along_x:
		return base.get_pixel(x, last.y - y) if forward else base.get_pixel(last.x - x, y)
	return base.get_pixel(y, x) if forward else base.get_pixel(last.x - y, last.y - x)


## The pixels of `tile` are the wall's flat tile as the 2D wall maps it: a segment running +x flips
## it across, -x along; +z transposes it, -z transposes and turns it half round (never a rotation).
func _oriented(
	t: TestContext,
	wall: Node,
	tile: Texture2D,
	seg: PackedVector2Array,
	along_x: bool,
) -> void:
	var base := ObjectArt.flat(
		"wall", Vector2(ObjectArtWallConfig.tile_px, THICKNESS), wall.art_color, wall.art_opts
	).get_image()
	var got := tile.get_image()
	var forward := (seg[1].x - seg[0].x if along_x else seg[1].y - seg[0].y) >= 0.0
	var wrong := 0
	for y in got.get_height():
		for x in got.get_width():
			wrong += 0 if got.get_pixel(x, y) == _expected(base, x, y, along_x, forward) else 1
	t.expect_eq(
		wrong,
		0,
		"%s: the tile's pixels are the 2D wall's (along x: %s)" % [wall.name, along_x],
	)


## A floor wears its painter's flat tile repeated from its `tile_offset`; floors of one look
## share the material.
func _floors(t: TestContext, mirror: WorldMirror) -> void:
	var materials := {}
	for floor_node in t.world.get_tree().get_nodes_in_group(&"floors"):
		if not t.world.is_ancestor_of(floor_node):
			continue
		var node := mirror.proxies_of(floor_node)[0] as MeshInstance3D
		var material := node.material_override as ShaderMaterial
		var tile := ObjectArt.tile_flat(
			floor_node.art, floor_node.color, floor_node.floor_material, floor_node.art_opts
		)
		t.check(
			material.get_shader_parameter(&"albedo_texture") == tile,
			"%s wears its flat tile" % floor_node.name,
		)
		var rect: Vector4 = node.get_instance_shader_parameter(&"uv_rect")
		var offset: Vector2 = floor_node.tile_offset
		t.expect_near(
			rect.x,
			-offset.x,
			0.001,
			"%s: the tile's grid starts at its offset" % floor_node.name,
		)
		t.expect_near(rect.y, -offset.y, 0.001, "%s: (y)" % floor_node.name)
		var one: Vector2 = tile.get_size() * ArtCanvasConfig.pixel_size
		t.expect_near(rect.z, one.x, 0.001, "%s: one tile wide" % floor_node.name)
		materials[material] = true
	t.check(
		materials.size() >= 1 and materials.size() <= 2,
		"the floors share their tiles' materials",
	)


## The door's leaf wears the door painter's flat art over the leaf; the handle is a plain mesh.
func _door(t: TestContext, mirror: WorldMirror) -> void:
	var door := t.object(&"front")
	var node := mirror.proxies_of(door)[0] as DoorMesh
	var leaf := node.get_child(0) as MeshInstance3D
	var size: Vector2 = door.leaf_size()
	var art := ObjectArt.flat("door", size, door.look.color, door.look.art_opts())
	var material := leaf.material_override as ShaderMaterial
	t.check(
		material != null and material.get_shader_parameter(&"albedo_texture") == art,
		"the leaf wears the flat door art",
	)
	var rect: Vector4 = leaf.get_instance_shader_parameter(&"uv_rect")
	t.expect_near(rect.x, -size.x * 0.5, 0.001, "the art starts at the hinge end")
	t.expect_near(rect.z, size.x, 0.001, "and covers the leaf")
	t.expect_eq(leaf.get_child_count(), 1, "the handle is the leaf's one child")
	var handle := leaf.get_child(0) as MeshInstance3D
	t.check(handle.material_override == ToonMaterial.shared(), "the handle is a plain toon mesh")


## A flat parquet tile keeps its strip seams: the first row of the tile (a strip's border) is darker
## than the row just inside it, as the lit tile's is (`outline` on a flat canvas must not wash it
## out).
func _grout(t: TestContext) -> void:
	var opts := { "pattern": "parquet" }
	var flat := ObjectArt.tile_flat("floor", Color(0.55, 0.4, 0.28), "wood", opts).get_image()
	t.check(_row_light(flat, 0) < _row_light(flat, 2) - 0.01, "the flat parquet keeps its seams")


## The mean lightness of row `y` of `image`.
func _row_light(image: Image, y: int) -> float:
	var sum := 0.0
	for x in image.get_width():
		sum += image.get_pixel(x, y).get_luminance()
	return sum / image.get_width()


## The district pre-warm paints the structure's flat tiles: every catalogue floor, both street
## tiles and the wall cap, as flat requests.
func _prewarm(t: TestContext) -> void:
	var requests := DistrictPrewarm.structure_requests()
	var flat := requests.filter(func(r: Dictionary) -> bool: return r.get("flat", false))
	t.expect_eq(flat.size(), requests.size(), "every structure request is a flat one")
	var floors := GeneralCatalog.FLOORS.size() + GeneralCatalog.STREET.size()
	t.check(requests.size() > floors, "a request for each floor, street tile and wall cap")
	var wall := ObjectArt.flat_request(
		"wall", Vector2(ObjectArtWallConfig.tile_px, THICKNESS),
		GeneralCatalog.WALL["color"], GeneralCatalog.WALL["art_opts"],
	)
	t.check(requests.any(func(r: Dictionary) -> bool: return r == wall), "the house wall's tile")
	t.check(DistrictPrewarm.requests().size() >= requests.size(), "the district warm takes them")


## Whether two colours are one to the image's 8 bits.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.03
