extends GameTest
## Wear and decals in the 3D render (#193 phase 2, `domain-objects/meshes.md`): what Objects draws
## as wear in 2D is a decal in 3D, laid on its surface at the surface's own height, from the same
## textures, seeds and configs. A room's floor marks lie on its floor slab; its wall marks stand on
## the wall's face toward the room, at a height by kind, turn with the wall and fade with it (the
## wall fade: a mark is a part of its segment's fade unit, and a rebuilt segment takes them over); a
## street's marks lie at the pavement's height or on the road a kerb lower (not at the ground), the
## lane's dashes and the crossings left to the street's own mesh; a floor stencil lies on its
## floor, and a tower's shadow is not a decal (the 3D sun casts a real one). Marks share their quad
## mesh by size and their material by texture. Expected numbers are the spec's
## (`domain-objects/meshes.md`), not read back from the holders.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_wear_mesh_test.json"
const HOUSE_SEED := 2
## A room floor's top (clear of the pavement slab) and how far a decal floats over its surface.
const FLOOR_LIFT := 0.1
const DECAL_LIFT := 0.15
## A decal layer lifts it this much more (`MeshKitConfig.decal_layer_step`). The tiers, by kind,
## are the layers the 2D layer draws marks in: slab 0, chip 1, any other mark 2, glyph 3, a stencil
## 4; a mark of `n` in its surface's draw order lies `0.9 * index / n` of a tier over its tier.
const LAYER_STEP := 0.25
const TIERS := { &"slab": 0.0, &"chip": 1.0, &"glyph": 3.0 }
const TIER_MARK := 2.0
## A rug's top over the ground (`ObjectMeshDecorConfig.rug_height`): the 2D layer draws wear under
## it.
const RUG_TOP := 0.6
const TIER_STENCIL := 4.0
const ORDER_FRACTION := 0.9
## How far the road lies below the pavement.
const KERB := 3.0
## A wall mark's canvas height and the height of its middle, by kind.
const WALL_MARK := {
	"peel": { "at": 40.0, "height": 18.0 },
	"wall_stain": { "at": 62.0, "height": 16.0 },
	"wall_crack": { "at": 48.0, "height": 30.0 },
	"cable": { "at": 22.0, "height": 6.0 },
}
const MATCH := {
	"seed": 2,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}


func describe() -> Dictionary:
	return {
		"name": "Wear and decals are laid on their surfaces in 3D",
		"description": "A room's floor marks lie on its floor, its wall marks stand on the wall's "
			+ "face at a height by kind and fade with the wall (also a rebuilt segment's), the "
			+ "street's marks lie at the pavement's or the road's own height with the lane and "
			+ "crossings left to the street mesh, a floor stencil lies on its floor and a tower's "
			+ "shadow is not drawn; quads and materials are shared; Main registers it.",
		"tags": ["mirror", "3d", "render", "meshkit", "wear", "decals", "walls", "street"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.house(HOUSE_SEED)
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	await t.frames(5)
	var fade := WallFade.new()
	var mirror := _mirror(t, fade)
	ObjectMeshes.register(mirror.builders)
	ObjectMeshes.track(mirror)
	mirror.mirror(t.world)
	await t.frames(3)
	var worn := _worn_rooms(t)
	t.check(worn.size() >= 2, "the house has worn rooms (%d)" % worn.size())
	_floor_wear(t, mirror, worn)
	_wall_wear(t, mirror, worn)
	await _wall_wear_fades(t, mirror, fade, worn)
	await _street_wear(t, mirror)
	await _street_stacking(t, mirror)
	await _street_under_a_room(t, mirror)
	await _stencil_and_shadow(t, mirror)
	await _check_main(t)


## The house's wear nodes, with the floor and wall of their room: `[{ wear, floor, wall }]`.
func _worn_rooms(t: TestContext) -> Array:
	var out: Array = []
	var seen := {}
	for entry: Dictionary in WorldGen.get_wear(t.world.house):
		var wear: Node2D = entry["layer"]
		if seen.has(wear):
			continue
		seen[wear] = true
		var floor_node: Node2D = null
		var wall: Node2D = null
		for node in wear.get_parent().get_children():
			if not node is Node2D or node == wear:
				continue
			if (node as Node2D).position != wear.position:
				continue
			if node.is_in_group(&"floors"):
				floor_node = node
			elif node.has_method(&"wall_segments"):
				wall = node
		out.append({ "wear": wear, "floor": floor_node, "wall": wall })
	return out


# --- Floor
# ------------------------------------------------------------------------------------------


## A room's floor marks are decals on its floor's mesh: one per 2D mark, at its rect, the floor's
## top plus the decal's lift, showing the very texture the 2D mark draws.
func _floor_wear(t: TestContext, mirror: WorldMirror, worn: Array) -> void:
	var marks_seen := 0
	for room: Dictionary in worn:
		var wear: Node2D = room["wear"]
		var node := _floor_mesh(mirror, room["floor"])
		if not t.require(node != null, "%s's floor is shown by a mesh" % wear.name):
			continue
		var marks: Array = wear.floor_marks()
		var decals := _decals(node)
		t.expect_eq(decals.size(), marks.size(), "%s: one decal per floor mark" % wear.name)
		for i in mini(decals.size(), marks.size()):
			_floor_mark(
				t,
				"%s floor mark %d" % [wear.name, i],
				decals[i],
				marks[i],
				_order(i, marks.size()),
			)
		_stacked(t, "%s floor" % wear.name, decals, true)
		marks_seen += marks.size()
	t.check(marks_seen > 0, "the house has floor marks (%d)" % marks_seen)


## One floor mark `mark` (`[texture, rect, kind]`) and its `decal`.
func _floor_mark(
	t: TestContext,
	what: String,
	decal: MeshInstance3D,
	mark: Array,
	order: float,
) -> void:
	var rect: Rect2 = mark[1]
	var size := decal.mesh.get_aabb().size
	t.check(
		decal.position.y < RUG_TOP,
		"%s: below a rug's top, which covers it as in 2D (%.3f < %.1f)" % [
			what,
			decal.position.y,
			RUG_TOP,
		],
	)
	t.expect_near(decal.position.x, rect.get_center().x, 0.01, "%s: at its x" % what)
	t.expect_near(decal.position.z, rect.get_center().y, 0.01, "%s: at its z" % what)
	t.expect_near(
		decal.position.y, FLOOR_LIFT + DECAL_LIFT + order * LAYER_STEP, 0.0001,
		"%s: on the floor's top, a lift over it and its order's step" % what,
	)
	t.expect_near(size.x, rect.size.x, 0.01, "%s: as wide" % what)
	t.expect_near(size.z, rect.size.y, 0.01, "%s: as deep" % what)
	t.check(_texture_of(decal) == mark[0], "%s shows the 2D mark's texture" % what)
	t.check(decal.basis.is_equal_approx(Basis.IDENTITY), "%s lies flat, unturned" % what)
	t.expect_eq(
		decal.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"%s casts no shadow" % what,
	)


# --- Walls
# ------------------------------------------------------------------------------------------


## A room's wall marks stand on the wall's face toward the room, at their kind's height, turned
## with the wall, each a child of the segment it lies on.
func _wall_wear(t: TestContext, mirror: WorldMirror, worn: Array) -> void:
	var marks_seen := 0
	for room: Dictionary in worn:
		var wear: Node2D = room["wear"]
		var wall_mesh := _wall_mesh(mirror, room["wall"])
		if not t.require(wall_mesh != null, "%s's wall is shown by a mesh" % wear.name):
			continue
		var placed := _wall_decals(wall_mesh)
		var marks: Array = wear.wall_marks()
		t.expect_eq(placed.size(), marks.size(), "%s: one decal per wall mark" % wear.name)
		for i in marks.size():
			_wall_mark(t, room["wall"], marks[i], placed, _order(i, marks.size()))
		_stacked(t, "%s wall" % wear.name, placed, false)
		marks_seen += marks.size()
	t.check(marks_seen > 0, "the house has wall marks (%d)" % marks_seen)


## One wall mark of `wall`: some decal of `placed` (its position in the wall's
## frame) is on the face at its kind's height, as long and as tall as the spec says.
func _wall_mark(
	t: TestContext,
	wall: Node2D,
	mark: Dictionary,
	placed: Array,
	order: float,
) -> void:
	var thickness: float = wall.get("wall_thickness")
	var what := "%s wall mark %s at %v" % [wall.name, mark["kind"], mark["at"]]
	var normal: Vector2 = mark["normal"]
	var up := Vector3(normal.x, 0.0, normal.y)
	var centre: Vector2 = (mark["at"] as Vector2) + normal * thickness * 0.5
	var want := Vector3(
		centre.x,
		WALL_MARK[mark["kind"]]["at"],
		centre.y,
	) + up * (DECAL_LIFT + order * LAYER_STEP)
	var found: MeshInstance3D = null
	for decal: MeshInstance3D in placed:
		var in_wall := (decal.get_parent() as Node3D).position + decal.position
		if (in_wall - want).length() < 0.0001 and decal.basis.y.is_equal_approx(up):
			found = decal
	if not t.require(found != null, "%s stands on the wall's face, at its height" % what):
		return
	var size := found.mesh.get_aabb().size
	t.expect_near(size.x, mark["length"], 0.01, "%s: its length" % what)
	t.expect_near(size.z, WALL_MARK[mark["kind"]]["height"], 0.01, "%s: its height" % what)
	var along := found.basis.x.dot(Vector3(mark["dir"].x, 0.0, mark["dir"].y))
	t.expect_near(absf(along), 1.0, 0.001, "%s runs along the wall" % what)
	t.check(_texture_of(found) != null, "%s shows a texture" % what)


## A wall mark is one of its segment's fade unit: fading the segment fades the mark, and a segment
## rebuilt by a hit takes its marks (and their fade) over.
func _wall_wear_fades(
	t: TestContext,
	mirror: WorldMirror,
	fade: WallFade,
	worn: Array,
) -> void:
	var wall := _worn_wall(worn)
	if not t.require(wall != null, "a room has a wall mark to fade"):
		return
	var wall_mesh := _wall_mesh(mirror, wall)
	fade.step(0.0, 0.0, PackedVector2Array())
	var decal := _wall_decals(wall_mesh)[0] as MeshInstance3D
	var part := decal.get_parent() as MeshInstance3D
	var index := int(String(part.name).trim_prefix("Segment"))
	var unit := fade.unit_of(wall.get_instance_id(), index)
	if not t.require(unit != null, "the segment carrying the mark is a fade unit"):
		return
	t.check(unit.parts.has(decal), "the mark is a part of its segment's fade unit")
	unit.faded = 1.0
	unit.apply()
	var level := float(part.get_instance_shader_parameter(&"fade"))
	t.check(level < 1.0, "the segment fades (%.2f)" % level)
	t.expect_near(
		float(decal.get_instance_shader_parameter(&"fade")), level, 0.001,
		"the mark fades with its segment",
	)
	await _rebuilt(t, wall_mesh, wall, decal)


## The wall of the first room with a wall mark, or null.
func _worn_wall(worn: Array) -> Node2D:
	for room: Dictionary in worn:
		if not (room["wear"] as Node2D).wall_marks().is_empty():
			return room["wall"]
	return null


## A hit on the segment `decal` stands on rebuilds it: the mark moves onto the new segment, where
## it was on the wall, faded as the segment is.
func _rebuilt(t: TestContext, wall_mesh: WallMesh, wall: Node2D, decal: MeshInstance3D) -> void:
	var part := decal.get_parent() as MeshInstance3D
	var index := int(String(part.name).trim_prefix("Segment"))
	var local := (part.position + decal.position) / RenderConfig.unit
	var hit := HitInfo.new()
	hit.position = wall.to_global(Vector2(local.x, local.z))
	hit.normal = Vector2(decal.basis.y.x, decal.basis.y.z)
	hit.direction = -hit.normal
	hit.damage = 60.0
	hit.speed_factor = 1.0
	wall.take_hit(hit)
	await t.frames(8)
	var after := wall_mesh.segments()[index] as MeshInstance3D
	t.check(after != part, "premise: the struck segment was meshed again")
	t.check(decal.get_parent() == after, "the mark is a child of the new segment")
	t.check(
		(after.position + decal.position).is_equal_approx(local * RenderConfig.unit),
		"the mark stays where it was on the wall",
	)
	var segment_fade: Variant = after.get_instance_shader_parameter(&"fade")
	t.check(
		segment_fade == decal.get_instance_shader_parameter(&"fade"),
		"the new segment and the mark are faded alike",
	)


# --- Street
# -----------------------------------------------------------------------------------------


## The street's marks lie on the pavement at its height and on the road a kerb lower; the lane's
## dashes and the crossings (the street mesh draws them) are not decals; a glyph is.
func _street_wear(t: TestContext, mirror: WorldMirror) -> void:
	var road_def: Dictionary = GeneralCatalog.STREET["asphalt"].duplicate(true)
	road_def["marks"] = {
		"seed": 7, "lane": true, "edges": [Vector2.DOWN],
		"crossings": [{ "side": Vector2.RIGHT, "reach": 70.0 }],
		"glyphs": [{ "side": Vector2.RIGHT, "from": 80.0, "length": 60.0, "text": "4" }],
	}
	var walk_def: Dictionary = GeneralCatalog.STREET["sidewalk"].duplicate(true)
	walk_def["marks"] = { "seed": 9, "edges": [Vector2.DOWN] }
	var road := FloorFactory.spawn(Rect2(3000, 0, 1400, 160), road_def, "Road", t.world)
	var walk := FloorFactory.spawn(Rect2(3000, 160, 1400, 50), walk_def, "Pavement", t.world)
	await t.frames(3)
	var road_node := _floor_mesh(mirror, road)
	var walk_node := _floor_mesh(mirror, walk)
	if not t.require(road_node != null and walk_node != null, "the street is shown by meshes"):
		return
	var kept := _piece_marks(t, road, road_node, -KERB) + _piece_marks(t, walk, walk_node, 0.0)
	t.check(kept > 0, "the street has wear marks (%d)" % kept)
	_glyph_and_crossing(t, road, road_node)
	_batched(t, road_node, walk_node)


## A pavement that runs under a room's floor lays no mark there (the 2D draws the room over it, so
## none shows): the marks that lie under the room are skipped, the rest are laid.
func _street_under_a_room(t: TestContext, mirror: WorldMirror) -> void:
	var room_rect := Rect2(3000, 900, 2400, 60)
	var room_def := {
		"art": "floor",
		"color": Color(0.5, 0.4, 0.3),
		"art_opts": { "pattern": "planks" },
	}
	FloorFactory.spawn(room_rect, room_def, "Room", t.world)
	var walk_def: Dictionary = GeneralCatalog.STREET["sidewalk"].duplicate(true)
	walk_def["marks"] = { "seed": 4, "edges": [Vector2.DOWN] }
	var walk := FloorFactory.spawn(Rect2(2800, 910, 3000, 50), walk_def, "WalkUnder", t.world)
	await t.frames(3)
	var node := _floor_mesh(mirror, walk)
	if not t.require(node != null, "the pavement under a room is shown by a mesh"):
		return
	var marks: Array = walk.find_child("StreetMarks", true, false).decals()
	var drawn := [&"dash", &"crossing"]
	var kept := 0
	for mark: Array in marks:
		var rect: Rect2 = mark[1]
		var centre: Vector2 = walk.position + rect.get_center()
		if not (mark[2] in drawn) and not room_rect.has_point(centre):
			kept += 1
	t.check(
		kept < marks.size(),
		"premise: some mark lies under the room (%d of %d)" % [kept, marks.size()],
	)
	t.expect_eq(_decals(node).size(), kept, "only the marks the room leaves bare are laid")


## Long pavements of several seeds, whose marks overlap (a chip on a slab, a crack over both): none
## of the overlapping marks shares a height, and some overlap.
func _street_stacking(t: TestContext, mirror: WorldMirror) -> void:
	var overlapping := 0
	var pieces: Array[Node2D] = []
	for seed_value in 8:
		var walk_def: Dictionary = GeneralCatalog.STREET["sidewalk"].duplicate(true)
		walk_def["marks"] = { "seed": seed_value, "edges": [Vector2.DOWN] }
		var rect := Rect2(3000, 400 + seed_value * 60, 3000, 50)
		pieces.append(FloorFactory.spawn(rect, walk_def, "Walk%d" % seed_value, t.world) as Node2D)
	await t.frames(3)
	for piece in pieces:
		var node := _floor_mesh(mirror, piece)
		if t.require(node != null, "%s is shown by a mesh" % piece.name):
			overlapping += _stacked(t, piece.name, _decals(node), true)
			await _stencil_over(t, mirror, piece, _decals(node))
	t.check(overlapping > 0, "premise: some street marks overlap (%d pairs)" % overlapping)


## A stencil laid over `piece` (its lot) lies above every mark of the piece and never at the
## height of one, and is drawn once: one node of the mirror shows it, one decal holds its texture.
func _stencil_over(
	t: TestContext, mirror: WorldMirror, piece: Node2D, decals: Array
) -> void:
	var rect := Rect2(piece.position + Vector2(40, 5), Vector2(160, 40))
	var stencil := DecalFactory.stencil(
		rect,
		{ "text": piece.name.to_upper() },
		"Lot Stencil %s" % piece.name,
		t.world,
	)
	await t.frames(3)
	var shown := mirror.proxies_of(stencil)
	if not t.require(shown.size() == 1, "%s: a stencil is shown once" % piece.name):
		return
	var held := _decals(shown[0])
	t.expect_eq(held.size(), 1, "%s: the stencil is one decal" % piece.name)
	var texture := (stencil as Sprite2D).texture
	var copies := mirror.find_children("*", "MeshInstance3D", true, false).filter(
		func(n: MeshInstance3D) -> bool: return (
			n.material_override is ShaderMaterial and _texture_of(n) == texture
		)
	)
	t.expect_eq(copies.size(), 1, "%s: the stencil's texture is drawn once" % piece.name)
	if held.size() != 1:
		return
	var at: float = shown[0].position.y + held[0].position.y
	var top := -INF
	for decal: MeshInstance3D in decals:
		top = maxf(top, decal.position.y)
		t.check(
			absf(decal.position.y - at) > 0.0001,
			"%s: a mark never shares the stencil's height" % piece.name,
		)
	t.check(
		at > top,
		"%s: the stencil is above every mark (%.3f over %.3f)" % [piece.name, at, top],
	)


## The decals of street piece `piece` (shown by `node`, its surface `top` px over the ground): one
## per mark but the dashes and crossings, each a lift over the surface. Their number.
func _piece_marks(t: TestContext, piece: Node2D, node: Node3D, top: float) -> int:
	var marks: Array = piece.find_child("StreetMarks", true, false).decals()
	var drawn := [&"dash", &"crossing"]
	var expected := marks.filter(func(m: Array) -> bool: return not (m[2] in drawn))
	var decals := _decals(node)
	t.expect_eq(
		decals.size(), expected.size(), "%s: a decal per mark but dashes and crossings" % piece.name
	)
	for i in decals.size():
		var over: float = decals[i].position.y - top
		t.expect_near(
			over, DECAL_LIFT + _layer(expected, i) * LAYER_STEP, 0.0001,
			"%s: mark %d a lift and its layer's over the surface at %.1f" % [
				piece.name,
				i,
				top,
			],
		)
	_stacked(t, piece.name, decals, true)
	return decals.size()


## The road's lane glyph is a decal (the street mesh does not draw it); its crossing is not.
func _glyph_and_crossing(t: TestContext, road: Node2D, road_node: Node3D) -> void:
	var layer := road.find_child("StreetMarks", true, false)
	var glyphs: Array = layer.laid("glyph")
	t.expect_eq(glyphs.size(), 1, "premise: the road has a lane glyph")
	var decals := _decals(road_node)
	var on_glyph := decals.filter(func(d: MeshInstance3D) -> bool: return _centred_on(d, glyphs[0]))
	t.expect_eq(on_glyph.size(), 1, "the lane glyph is one decal, the street mesh does not draw it")
	var crossing: Rect2 = layer.laid("crossing")[0]
	t.check(
		not decals.any(func(d: MeshInstance3D) -> bool: return _centred_on(d, crossing)),
		"the crossing is the street mesh's, not a decal",
	)


## Whether `decal` is centred on `rect` (the piece's frame).
func _centred_on(decal: MeshInstance3D, rect: Rect2) -> bool:
	return rect.get_center().is_equal_approx(Vector2(decal.position.x, decal.position.z))


## Marks of one size share a quad mesh, marks of one texture a material.
func _batched(t: TestContext, road_node: Node3D, walk_node: Node3D) -> void:
	var meshes := {}
	var materials := {}
	var textures := {}
	var decals := _decals(road_node) + _decals(walk_node)
	for decal: MeshInstance3D in decals:
		meshes[decal.mesh] = true
		materials[decal.material_override] = true
		textures[_texture_of(decal)] = true
	t.check(decals.size() > 0, "premise: decals to batch")
	t.check(
		meshes.size() <= decals.size(),
		"quads are shared by size (%d meshes for %d decals)" % [meshes.size(), decals.size()],
	)
	t.expect_eq(materials.size(), textures.size(), "one material per texture")


# --- Stencils and shadows
# ---------------------------------------------------------------------------


## A floor stencil lies on its floor at the floor's top, its rect; a tower's shadow is not shown.
func _stencil_and_shadow(t: TestContext, mirror: WorldMirror) -> void:
	var rect := Rect2(5000, 0, 160, 90)
	var stencil := DecalFactory.stencil(rect, { "text": "LOBBY" }, "Test Stencil", t.world)
	var shadow := DecalFactory.shadow(
		Rect2(5400, 0, 60, 60), { "length": 40 }, "Test Shadow", t.world
	)
	await t.frames(3)
	var shown := mirror.proxies_of(stencil)
	if t.require(shown.size() == 1, "the stencil is shown"):
		var decals := _decals(shown[0])
		t.expect_eq(decals.size(), 1, "the stencil is one decal")
		if decals.size() == 1:
			var decal: MeshInstance3D = decals[0]
			var size := (stencil as Sprite2D).texture.get_size()
			t.expect_near(
				shown[0].position.y + decal.position.y,
				FLOOR_LIFT + DECAL_LIFT + TIER_STENCIL * LAYER_STEP,
				0.0001, "the stencil lies on its floor, on the stencil tier",
			)
			t.expect_near(decal.mesh.get_aabb().size.x, size.x, 0.01, "as wide as the stencil")
			t.expect_near(decal.mesh.get_aabb().size.z, size.y, 0.01, "as deep as the stencil")
			t.check(_texture_of(decal) == (stencil as Sprite2D).texture, "its 2D texture")
			t.expect_near(
				shown[0].global_position.x + decal.position.x, rect.get_center().x, 0.01,
				"centred on the stencil's area",
			)
	t.expect_eq(
		mirror.proxies_of(shadow).size(),
		0,
		"the tower's shadow is not drawn (the sun's is)",
	)


## Main's 3D view registers the decals with the mirror: a stencil of the match is shown.
func _check_main(t: TestContext) -> void:
	var window := MainProbe.viewport(t)
	var main := MainProbe.open(window)
	MainProbe.setup_menu(main).queue_free()
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	main.add_child(camera)
	var built: Dictionary = await main.start_match(MATCH.duplicate(true))
	if t.require(not built.is_empty(), "a 3D match started"):
		await t.frames(4)
		var view: Node = main.get_node("View3D")
		var rect := Rect2(-300, -300, 80, 40)
		var stencil := DecalFactory.stencil(rect, { "text": "X" }, "Main Stencil", built["world"])
		await t.frames(3)
		var shown: Array = view.mirror.proxies_of(stencil)
		t.expect_eq(shown.size(), 1, "Main's view shows a floor stencil by a decal")
	await MainProbe.close(t, window)


# --- Stacking
# ---------------------------------------------------------------------------


## The layer of mark `index` of `marks` (`[texture, rect, kind]`, in draw order): its kind's tier
## and its place in the draw order, a fraction of a tier.
func _layer(marks: Array, index: int) -> float:
	return float(TIERS.get(marks[index][2], TIER_MARK)) + _order(index, marks.size())


## The fraction of a tier mark `index` of `count` lies up.
func _order(index: int, count: int) -> float:
	return ORDER_FRACTION * index / maxf(count, 1.0)


## Overlapping decals of one surface never share a height: of `decals` (flat on the floor when
## `flat`, else standing on a wall face, `get_parent()` the segment), no two that overlap lie on
## one level. Returns how many pairs overlap.
func _stacked(t: TestContext, what: String, decals: Array, flat: bool) -> int:
	var overlapping := 0
	var sharing := 0
	for i in decals.size():
		for j in range(i + 1, decals.size()):
			var a: MeshInstance3D = decals[i]
			var b: MeshInstance3D = decals[j]
			if not _overlap(a, b, flat):
				continue
			overlapping += 1
			if absf((_at(a, flat) - _at(b, flat)).dot(a.basis.y)) < 0.0001:
				sharing += 1
	t.expect_eq(
		sharing, 0, "%s: no two overlapping decals share a height (%d overlap)" % [
			what,
			overlapping,
		]
	)
	return overlapping


## Where `decal` is in its surface's frame.
func _at(decal: MeshInstance3D, flat: bool) -> Vector3:
	return decal.position if flat else (decal.get_parent() as Node3D).position + decal.position


## Whether two decals on parallel planes cover a common patch (their sizes along their own axes).
func _overlap(a: MeshInstance3D, b: MeshInstance3D, flat: bool) -> bool:
	if not a.basis.y.is_equal_approx(b.basis.y):
		return false
	var d := _at(a, flat) - _at(b, flat)
	var sa := a.mesh.get_aabb().size
	var sb := b.mesh.get_aabb().size
	var same := b.basis.x.is_equal_approx(a.basis.x)
	var reach_u := (sa.x + sb.x) * 0.5 if same else (sa.x + sb.z) * 0.5
	var reach_v := (sa.z + sb.z) * 0.5 if same else (sa.z + sb.x) * 0.5
	return absf(d.dot(a.basis.x)) < reach_u and absf(d.dot(a.basis.z)) < reach_v


# --- Helpers
# ----------------------------------------------------------------------------------------


## The decal children of `node` (a floor's mesh), in order: not a street's `Paint` mesh.
func _decals(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if (child is MeshInstance3D and child.name != &"Paint"
				and child.material_override is ShaderMaterial):
			out.append(child)
	return out


## Every decal on `wall_mesh`'s segments.
func _wall_decals(wall_mesh: Node3D) -> Array:
	var out: Array = []
	for part in (wall_mesh as WallMesh).segments().values():
		out.append_array(_decals(part))
	return out


func _texture_of(decal: MeshInstance3D) -> Texture2D:
	return (decal.material_override as ShaderMaterial).get_shader_parameter(&"albedo_texture")


## The mesh `mirror` shows `floor_node` by (a kit mesh, not a proxy box).
func _floor_mesh(mirror: WorldMirror, floor_node: Node) -> MeshInstance3D:
	var shown := mirror.proxies_of(floor_node)
	if shown.size() != 1 or not shown[0] is MeshInstance3D:
		return null
	var node := shown[0] as MeshInstance3D
	return null if node.mesh is BoxMesh else node


func _wall_mesh(mirror: WorldMirror, wall: Node) -> WallMesh:
	var shown := mirror.proxies_of(wall)
	return shown[0] as WallMesh if shown.size() == 1 and shown[0] is WallMesh else null


func _mirror(t: TestContext, fade: WallFade) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	view.add_child(fade)
	fade.set_process(false)
	fade.listen(mirror)
	return mirror
