extends GameTest
## The commercial, shell and street kinds are shown by kit-built meshes (#193 phase 2,
## `domain-art/meshes.md`): Objects registers a builder per art id (tech, clinic, security, shop,
## noodle, stock, awning, street prop, podium, shell decor, decor, streetlight, car) under
## `MirrorProxy.furniture_key(art)` and the floor stencils by a group; the mirror shows a piece of
## each by its rig in place of its proxy box. Each mesh stands in the piece's own footprint (an
## overhead part beyond it, the footprint with the piece's overhang) and covers most of it,
## at the height the spec gives its class, in the colour its painter draws; pieces alike share the
## one `Mesh`; a part that gives light is a glow node of its own strength (no real light: phase 3);
## a resting piece costs nothing per frame; at `RenderConfig.unit = 0.5` every length halves.
## Expected numbers are the spec's (`domain-art/meshes.md`), not read back from the holders.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const ObjectArt := preload("res://scenes/objects/art/object_art.gd")
const SCRATCH := "user://settings_furniture_commercial_mesh_test.json"
const MATCH := {
	"seed": 2,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}
## Per catalogue piece: its art id, the height (px) its mesh stands to (`tol` of slack: loose pieces
## are scattered by chance), the height it starts at (`base`, 0), the least share of the footprint's
## width and depth it covers (`cover`; a piece that hangs thin on the wall at the back of its
## footprint says `wall`, one with an overhead part past its footprint `over`: it stands within the
## footprint merged with the part's rect (`look.overhang_rect()`) and covers no share of it), and
## the colour a face of it has (`colour`: the piece's painted one unless it says another: a share it
## is darkened by, the `ObjectArtShopConfig` colour it is drawn in, or `false` for a piece the
## painter colours by
## chance or from a palette of its own; `deep`: the least share of the depth it covers, for a thin
## one; `hangs`: its parts start at no set height, as streaks down a wall do). Heights are the
## spec's class heights; the few that rise past the class number are the part on top (a till's
## screen, a rack's LEDs, a scanner's emitter, a bin's lid).
const KINDS := {
	&"monitor_wall": { "art": "tech", "top": 62.0, "base": 0.0, "cover": 0.8, "colour": false },
	&"server_rack": { "art": "tech", "top": 83.0, "base": 0.0, "cover": 0.8 },
	&"tool_cart": { "art": "clinic", "top": 35.3, "base": 0.0, "cover": 0.8 },
	&"cyberware_shelf": { "art": "clinic", "top": 64.0, "base": 0.0, "cover": 0.8 },
	&"barricade": { "art": "security", "top": 36.3, "base": 0.0, "cover": 0.8 },
	&"scanner_post": { "art": "security", "top": 84.4, "base": 0.0, "cover": 0.5 },
	&"lockers": { "art": "security", "top": 72.0, "base": 0.0, "cover": 0.95 },
	&"shop_counter": { "art": "shop", "top": 48.8, "base": 0.0, "cover": 0.95 },
	&"shelf_aisle": { "art": "shop", "top": 58.4, "base": 0.0, "cover": 0.9 },
	&"drinks_fridge": { "art": "shop", "top": 70.4, "base": 0.0, "cover": 0.9 },
	&"snack_machine": { "art": "shop", "top": 66.0, "base": 0.0, "cover": 0.9 },
	&"noodle_counter": { "art": "noodle", "top": 45.2, "base": 0.0, "cover": 0.9 },
	&"bar_stool": { "art": "noodle", "top": 20.3, "base": 0.0, "cover": 0.5, "colour": 0.3 },
	&"noodle_booth": { "art": "noodle", "top": 34.0, "base": 0.0, "cover": 0.8 },
	&"menu_board": {
		"art": "noodle", "top": 80.0, "base": 46.0, "cover": 0.8, "wall": true, "colour": 0.35,
	},
	&"crate_stack": {
		"art": "stock", "top": 36.9, "base": 0.0, "cover": 0.8, "colour": "stock_wood_color",
	},
	&"wrapped_pallet": {
		"art": "stock", "top": 31.4, "base": 0.0, "cover": 0.8, "colour": "stock_cardboard_color",
	},
	&"wall_safe": { "art": "stock", "top": 40.0, "base": 0.0, "cover": 0.8 },
	&"vending_machine": { "art": "street_prop", "top": 70.0, "base": 0.0, "cover": 0.9 },
	&"street_bench": { "art": "street_prop", "top": 16.0, "base": 0.0, "cover": 0.8 },
	&"street_bin": { "art": "street_prop", "top": 32.2, "base": 0.0, "cover": 0.5, "colour": 0.3 },
	&"drain_grate": { "art": "street_prop", "top": 0.6, "base": 0.0, "cover": 0.8, "colour": 0.15 },
	&"litter": { "art": "street_prop", "top": 1.2, "tol": 0.5, "cover": 0.3, "colour": false },
	&"podium": { "art": "podium", "top": 64.0, "base": 0.0, "cover": 0.95, "colour": false },
	&"rebar": { "art": "shell_decor", "top": 5.6, "base": 0.0, "cover": 0.5, "colour": false },
	&"rubble": {
		"art": "shell_decor", "top": 7.0, "tol": 3.0, "cover": 0.5, "colour": false,
	},
	&"scaffold": { "art": "shell_decor", "top": 10.0, "base": 0.0, "cover": 0.8, "colour": false },
	&"cement_bags": {
		"art": "shell_decor", "top": 9.3, "base": 0.0, "cover": 0.5, "colour": false,
	},
	&"wall_stain": {
		"art": "shell_decor", "top": 88.0, "cover": 0.8, "deep": 0.0, "wall": true, "hangs": true,
		"colour": false,
	},
	&"trash": { "art": "decor", "top": 10.0, "tol": 4.0, "cover": 0.3, "colour": false },
	&"cables": { "art": "decor", "top": 1.6, "base": 0.0, "cover": 0.8, "colour": false },
	&"cable_nest": { "art": "decor", "top": 1.6, "base": 0.0, "cover": 0.5, "colour": false },
	&"cardboard": { "art": "decor", "top": 4.4, "base": 0.0, "cover": 0.8, "colour": false },
	&"puddle": { "art": "decor", "top": 0.25, "base": 0.0, "cover": 0.5, "colour": false },
	&"neon_tube": { "art": "decor", "top": 3.0, "cover": 0.8, "deep": 0.4, "colour": false },
	&"streetlight": { "art": "streetlight", "top": 130.0, "base": 0.0, "over": true },
	&"street_sign": { "art": "streetlight", "top": 130.0, "base": 0.0, "over": true },
	&"awning": { "art": "awning", "top": 96.0, "base": 67.4, "over": true, "colour": false },
	&"glyph_sign": { "art": "awning", "top": 86.0, "base": 58.0, "over": true, "colour": false },
	&"car": { "art": "car", "top": 52.0, "base": 0.0, "cover": 0.9, "colour": false },
}
## The glow nodes of a piece: how many at least and the strengths its glows may glow at (each
## part keeps the strength it was given).
const GLOWS := {
	&"monitor_wall": { "min": 2, "of": [0.6] },
	&"server_rack": { "min": 3, "of": [0.8] },
	&"scanner_post": { "min": 1, "of": [0.8] },
	&"shop_counter": { "min": 1, "of": [0.6] },
	&"drinks_fridge": { "min": 1, "of": [0.5] },
	&"snack_machine": { "min": 1, "of": [0.5] },
	&"menu_board": { "min": 2, "of": [1.0] },
	&"vending_machine": { "min": 1, "of": [0.5] },
	&"neon_tube": { "min": 1, "of": [1.0] },
	&"streetlight": { "min": 1, "of": [0.9] },
	&"street_sign": { "min": 1, "of": [1.0] },
	&"awning": { "min": 1, "of": [1.0] },
	&"glyph_sign": { "min": 2, "of": [1.0] },
}
## How far a glowing part stands proud of the face it lies on (px).
const PROUD := 0.7
const SHOP_HOLDER := "res://scenes/objects/art/object_art_shop_config.gd"
const CELL := Vector2(230.0, 270.0)
const PER_ROW := 11


func describe() -> Dictionary:
	return {
		"name": "The commercial, shell and street kinds are shown by kit-built meshes",
		"description": "A builder is registered per art id; the mirror shows a piece of each "
			+ "by its rig: within its footprint (an overhead part with its overhang), at the "
			+ "spec's height, in the painter's colour, one shared mesh for pieces alike, each "
			+ "glow its own strength, nothing per frame, half size at half scale; floor "
			+ "stencils are decals; Main's 3D view registers them all.",
		"tags": ["mirror", "3d", "render", "meshkit", "furniture"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	var rows := ceili(float(KINDS.size() + 6) / PER_ROW)
	s.arena(Rect2(0, 0, CELL.x * PER_ROW, CELL.y * rows + 100.0))
	var at := Vector2(130.0, 150.0)
	for id: StringName in KINDS:
		var definition: Variant = String(id)
		if id == &"server_rack":
			definition = _rack()
		s.object(id, definition, at)
		at = _next(at)
	s.object(&"rack_b", _rack(), at)
	at = _next(at)
	s.object(&"awning_up", "awning", at, { "facing": Vector2.UP })
	at = _next(at)
	s.object(&"lamp_up", "streetlight", at, { "facing": Vector2.UP })
	at = _next(at)
	s.object(&"lamp_left", "streetlight", at, { "facing": Vector2.LEFT })
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


## The server rack's catalogue row with its neon fixed (a piece takes a random one by its place).
func _rack() -> Dictionary:
	var row := WorldGen.object_definition("server_rack").duplicate(true)
	row["art_opts"]["neon"] = "cyan"
	return row


func _next(at: Vector2) -> Vector2:
	at.x += CELL.x
	if at.x > CELL.x * PER_ROW - 100.0:
		return Vector2(130.0, at.y + CELL.y)
	return at


func run(t: TestContext) -> void:
	await t.frames(5)
	var mirror := _mirror(t)
	ObjectMeshes.register(mirror.builders)
	ObjectMeshes.track(mirror)
	_check_registered(t, mirror)
	mirror.mirror(t.world)
	await t.frames(3)
	for id: StringName in KINDS:
		var rig := _rig_of(mirror, t.object(id))
		if t.require(rig != null, "%s is shown by a rig of its own, not a proxy box" % id):
			_check_shape(t, id, rig, t.object(id), 1.0)
	_check_colours(t, mirror)
	_check_given_colours(t, mirror)
	_check_sharing(t, mirror)
	_check_static_pieces_cost_nothing(t, mirror)
	_check_glows(t, mirror)
	_check_facings(t, mirror)
	_check_overhang_field(t, mirror)
	await _check_stencil(t, mirror)
	await _check_dent_tint(t, mirror)
	await _check_half_scale(t)
	await _check_main(t)


## Every art id has a builder under its own hook key, and the stencil group is tracked.
func _check_registered(t: TestContext, mirror: WorldMirror) -> void:
	for id: StringName in KINDS:
		var key := MirrorProxy.furniture_key(KINDS[id]["art"])
		t.check(mirror.builders.has(key), "a builder is registered under %s" % key)
		t.check(mirror.builders[key].is_valid(), "the builder of %s is callable" % key)
	t.check(mirror.builders.has(MirrorProxy.furniture_key("sofa")), "the sofa's is still there")


## The rig of `body` when the mirror shows it by one (a `FurnitureRig`), else null (a proxy box).
func _rig_of(mirror: WorldMirror, body: Node) -> FurnitureRig:
	var shown := mirror.proxies_of(body)
	if shown.size() != 1 or not shown[0] is FurnitureRig:
		return null
	return shown[0] as FurnitureRig


## The area the piece's overhead part covers, in the piece's frame (an empty rect for a piece with
## none).
func _overhang_of(piece: Node) -> Rect2:
	return piece.look.overhang_rect()


## The mesh stands in the piece's footprint (in the body's frame: a turned piece is the turned
## mesh), covers most of it and runs from its base to the spec'd height, all times `factor`. A part
## that glows stands a little proud of the face it is on (`PROUD`), so the glows get that slack.
func _check_shape(
	t: TestContext, id: StringName, rig: FurnitureRig, piece: Node, factor: float
) -> void:
	var row: Dictionary = KINDS[id]
	var size: Vector2 = piece.get("size")
	var solids := rig.body.mesh.get_aabb()
	var box := _bounds(rig)
	var at := "%s (x%.1f)" % [id, factor]
	var tol: float = row.get("tol", 0.02)
	t.expect_near(box.end.y, float(row["top"]) * factor, tol * factor, "%s tops out" % at)
	if not row.has("hangs"):
		t.expect_near(box.position.y, float(row.get("base", 0.0)) * factor, 0.02, "%s starts" % at)
	if row.has("over"):
		var reach := Rect2(-size / 2.0, size).merge(_overhang_of(piece).abs())
		t.check(
			_within(box, reach, factor, PROUD),
			"%s stays within its footprint and overhang %s: %s" % [at, reach, box],
		)
		return
	t.check(
		_within(solids, Rect2(-size / 2.0, size), factor, 0.01)
		and _within(box, Rect2(-size / 2.0, size), factor, PROUD),
		"%s stays within its footprint %s: %s" % [at, size * factor, box.size],
	)
	var cover: float = row["cover"]
	var deep: float = row.get("deep", 0.2 if row.has("wall") else cover)
	t.check(
		solids.size.x >= size.x * factor * cover and solids.size.z >= size.y * factor * deep,
		"%s covers %.0f%% of its footprint %s: %s" % [
			at,
			cover * 100.0,
			size * factor,
			solids.size,
		],
	)
	t.expect_near(box.get_center().x, 0.0, size.x * factor * 0.3, "%s is centred (x)" % at)
	if row.has("wall"):
		t.check(box.get_center().z < 0.0, "%s hangs at the back of its footprint" % at)
	else:
		t.expect_near(box.get_center().z, 0.0, size.y * factor * 0.3, "%s is centred (z)" % at)


## Whether `box` lies in `area` (2D px, in the piece's frame) scaled by `factor`, `slack` over.
func _within(box: AABB, area: Rect2, factor: float, slack: float) -> bool:
	return (
		box.position.x >= area.position.x * factor - slack
		and box.end.x <= area.end.x * factor + slack
		and box.position.z >= area.position.y * factor - slack
		and box.end.z <= area.end.y * factor + slack
	)


## The bounds of the solids and the glows of `rig` in its frame.
func _bounds(rig: FurnitureRig) -> AABB:
	var box := rig.body.mesh.get_aabb()
	for glow in rig.glows:
		box = box.merge(glow.mesh.get_aabb())
	return box


## A face of the body carries the colour the painter draws the piece in.
func _check_colours(t: TestContext, mirror: WorldMirror) -> void:
	for id: StringName in KINDS:
		var row: Dictionary = KINDS[id]
		var piece := t.object(id)
		var rig := _rig_of(mirror, piece)
		if rig == null or row.get("colour", true) is bool and not row.get("colour", true):
			continue
		var want := ObjectArt.drawn_color(piece.get("color"))
		var drawn: Variant = row.get("colour", true)
		if drawn is float:
			want = want.darkened(drawn)
		elif drawn is String:
			want = (load(SHOP_HOLDER) as Object).get(drawn)
		t.check(
			_has_colour(rig.body.mesh as ArrayMesh, want),
			"%s has a face in its painted colour %s" % [id, want],
		)


## The painters that take their colours as given are drawn in them: the podium its concrete, the
## awning its stripes, the loose clutter and shell decor the colours of their own rows.
func _check_given_colours(t: TestContext, mirror: WorldMirror) -> void:
	var podium := _rig_of(mirror, t.object(&"podium"))
	if podium != null:
		var want := ObjectArtPodiumConfig.podium_color
		t.check(
			_has_colour(podium.body.mesh as ArrayMesh, want), "the podium is its concrete %s" % want
		)


## Two pieces of one look share the one mesh; one of another look does not.
func _check_sharing(t: TestContext, mirror: WorldMirror) -> void:
	var first := _rig_of(mirror, t.object(&"server_rack"))
	var second := _rig_of(mirror, t.object(&"rack_b"))
	t.check(
		first != null and second != null and first.body.mesh == second.body.mesh,
		"two racks alike share the one mesh",
	)
	t.check(
		first != null and second != null and first.glows.size() == second.glows.size(),
		"and the same glows",
	)
	for i in mini(first.glows.size(), second.glows.size()):
		t.check(first.glows[i].mesh == second.glows[i].mesh, "glow %d is one mesh" % i)
	var lockers := _rig_of(mirror, t.object(&"lockers"))
	t.check(
		first != null and lockers != null and first.body.mesh != lockers.body.mesh,
		"a rack and lockers do not",
	)


## A resting piece costs nothing per frame: no `mirror_update` and no `_process` on a rig.
func _check_static_pieces_cost_nothing(t: TestContext, mirror: WorldMirror) -> void:
	for id: StringName in KINDS:
		var rig := _rig_of(mirror, t.object(id))
		if rig == null:
			continue
		t.check(not rig.has_method(&"mirror_update"), "%s: no mirror_update" % id)
		t.check(not rig.is_processing(), "%s runs no _process" % id)


## A part that gives light is a glow node of its own strength, lit by default, dark when the rig
## is switched off and back at that strength when it is lit again, written only on change; a glow
## casts no shadow and each piece keeps the strengths of its own parts.
func _check_glows(t: TestContext, mirror: WorldMirror) -> void:
	for id: StringName in GLOWS:
		var rig := _rig_of(mirror, t.object(id))
		if rig == null:
			continue
		var row: Dictionary = GLOWS[id]
		t.check(
			rig.glows.size() >= int(row["min"]),
			"%s has glow nodes: %d" % [id, rig.glows.size()],
		)
		for glow in rig.glows:
			var strength := _strength(glow)
			t.check(
				_one_of(strength, row["of"]),
				"%s: a glow's strength %.2f is one the spec gives it %s" % [
					id,
					strength,
					row["of"],
				],
			)
			t.check(
				glow.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
				"%s: a glow casts no shadow" % id,
			)
		rig.set_lit(false)
		for glow in rig.glows:
			t.expect_near(_strength(glow), 0.0, 0.001, "%s: switched off, it does not glow" % id)
		rig.set_lit(true)
		for glow in rig.glows:
			t.check(_one_of(_strength(glow), row["of"]), "%s: lit again at its own strength" % id)
	var rack := _rig_of(mirror, t.object(&"server_rack"))
	if rack != null and not rack.glows.is_empty():
		rack.glows[0].set_instance_shader_parameter(&"emissive", Color(1, 2, 3, 4))
		rack.set_lit(true)
		t.expect_eq(
			rack.glows[0].get_instance_shader_parameter(&"emissive"),
			Color(1, 2, 3, 4),
			"lighting a lit rack writes nothing",
		)
		rack.glows[0].set_instance_shader_parameter(&"emissive", Color(0.5, 0.5, 0.5, 0.8))


func _one_of(value: float, allowed: Array) -> bool:
	for each: float in allowed:
		if absf(value - each) < 0.001:
			return true
	return false


## A piece turned another way is another mesh turned that way: an awning facing up hangs from the
## wall at the top of its footprint, a streetlight facing up or left leans out to that side.
func _check_facings(t: TestContext, mirror: WorldMirror) -> void:
	var down := _rig_of(mirror, t.object(&"awning"))
	var up := _rig_of(mirror, t.object(&"awning_up"))
	if t.require(down != null and up != null, "an awning facing down and one facing up"):
		t.check(down.body.mesh != up.body.mesh, "facing up is another mesh than facing down")
		var a := down.body.mesh.get_aabb()
		var b := up.body.mesh.get_aabb()
		t.check(a.get_center().z > 0.0, "an awning facing down reaches out toward +y")
		t.check(b.get_center().z < 0.0, "and facing up toward -y")
	var plain := _rig_of(mirror, t.object(&"streetlight"))
	var lamp_up := _rig_of(mirror, t.object(&"lamp_up"))
	var lamp_left := _rig_of(mirror, t.object(&"lamp_left"))
	if t.require(
		plain != null and lamp_up != null and lamp_left != null, "streetlights of three facings"
	):
		var d := plain.body.mesh.get_aabb().get_center()
		var u := lamp_up.body.mesh.get_aabb().get_center()
		var l := lamp_left.body.mesh.get_aabb().get_center()
		t.check(d.z > 0.0 and u.z < 0.0, "a streetlight leans out the way it faces (up, down)")
		t.check(l.x < 0.0, "and facing left to -x")


## The overhang is the piece's own field (`look.overhang`, the definition's), the same data the 2D
## `Overhang` node draws from: the meshes read it, not that node, so removing the node (the 2D
## render's deletion) changes no mesh.
func _check_overhang_field(t: TestContext, mirror: WorldMirror) -> void:
	for id: StringName in [&"streetlight", &"awning", &"glyph_sign", &"street_sign"]:
		var piece := t.object(id)
		var definition := WorldGen.object_definition(String(id))
		t.expect_eq(piece.look.overhang, definition["overhang"], "%s keeps its overhang" % id)
		var node := piece.get_node_or_null("Overhang")
		if not t.require(node != null, "%s has its 2D Overhang node" % id):
			continue
		t.expect_eq(
			piece.look.overhang_rect(), node.call(&"get_rect"), "%s: the field is drawn" % id
		)
		var shown := _rig_of(mirror, piece)
		piece.remove_child(node)
		var again: FurnitureRig = ObjectMeshes.BUILDERS[KINDS[id]["art"]].build(piece)
		t.check(
			shown != null and again.body.mesh == shown.body.mesh,
			"%s: without the node the mesh is the same" % id,
		)
		again.free()
		piece.add_child(node)
	t.expect_eq(
		t.object(&"server_rack").look.overhang_rect(), Rect2(), "a piece with none has no area"
	)


## A floor stencil is shown by a flat decal over the area its sprite covers.
func _check_stencil(t: TestContext, mirror: WorldMirror) -> void:
	var holder := Node2D.new()
	holder.position = Vector2(300.0, 300.0)
	t.world.add_child(holder)
	var sprite := DecalFactory.stencil(
		Rect2(20, 30, 120, 40),
		{ "text": "EXIT" },
		"Stencil",
		holder,
	)
	t.check(sprite.is_in_group(DecalFactory.STENCIL_GROUP), "a stencil joins the stencil group")
	await t.frames(3)
	var shown := mirror.proxies_of(sprite)
	t.check(shown.size() == 1, "a stencil is shown by one node: %d" % shown.size())
	if shown.size() == 1:
		var decals := shown[0].get_children()
		t.check(decals.size() == 1 and decals[0] is MeshInstance3D, "that holds the one decal")
		if decals.size() == 1:
			var box := (decals[0] as MeshInstance3D).get_aabb()
			t.expect_near(box.size.x, 120.0, 0.5, "the decal is as wide as the stencil")
			t.expect_near(box.size.z, 40.0, 0.5, "and as deep")
			t.expect_near(box.size.y, 0.0, 0.001, "and lies flat")
			var lift := (
				ObjectStructureMeshConfig.floor_lift
				+ MeshKitConfig.decal_lift
				+ ObjectWearMeshConfig.tier_stencil * MeshKitConfig.decal_layer_step
			)
			t.expect_near(
				(decals[0] as Node3D).position.y,
				lift * RenderConfig.unit,
				0.001,
				"on the floor's slab, a decal's lift and the stencil tier over it",
			)
			t.expect_near(
				(decals[0] as Node3D).position.x, 60.0, 0.5, "its middle is the stencil's middle"
			)
	t.check(
		not mirror.proxies_of(sprite).is_empty() and not shown[0].has_method(&"mirror_update"),
		"a stencil has no update of its own (the mirror only compares its transform)",
	)
	holder.free()


## A dent tints the solids as the 2D piece darkens, written only when the damage changes.
func _check_dent_tint(t: TestContext, mirror: WorldMirror) -> void:
	var piece := t.object(&"lockers")
	var rig := _rig_of(mirror, piece)
	if not t.require(rig != null, "the lockers have a rig"):
		return
	t.expect_eq(rig.tint(), Color.WHITE, "unhurt lockers are untinted")
	var deformable: Deformable = piece.physics.deformable
	deformable.damage_total = 80.0
	deformable.changed.emit()
	var darker := Color.WHITE.darkened(Deformation.darken(80.0))
	t.expect_eq(rig.tint(), darker, "damaged lockers are tinted as their 2D art darkens")
	rig.body.set_instance_shader_parameter(&"base_color", Color.RED)
	deformable.changed.emit()
	t.expect_eq(
		rig.body.get_instance_shader_parameter(&"base_color"),
		Color.RED,
		"a hit that changes nothing writes nothing",
	)
	await t.frames(1)


## At half scale every length of every mesh halves (the one conversion is the kit's).
func _check_half_scale(t: TestContext) -> void:
	RenderConfig.unit = 0.5
	var halved := _mirror(t)
	ObjectMeshes.register(halved.builders)
	halved.mirror(t.world)
	await t.frames(3)
	for id: StringName in KINDS:
		var rig := _rig_of(halved, t.object(id))
		if t.require(rig != null, "%s is shown at half scale" % id):
			_check_shape(t, id, rig, t.object(id), 0.5)
	RenderConfig.unit = 1.0


## Main's 3D view registers every kind's builder and tracks the stencils.
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
		for id: StringName in KINDS:
			t.check(
				view.mirror.builders.has(MirrorProxy.furniture_key(KINDS[id]["art"])),
				"Main's view registers the %s builder" % KINDS[id]["art"],
			)
		t.check(
			view.mirror._group_builders.has(DecalFactory.STENCIL_GROUP),
			"Main's view tracks the floor stencils",
		)
	await MainProbe.close(t, window)


## The strength a glow node glows with now.
func _strength(glow: GeometryInstance3D) -> float:
	return (glow.get_instance_shader_parameter(&"emissive") as Color).a


## Whether some vertex of `mesh` carries `want` (the vertex colour is linear).
func _has_colour(mesh: ArrayMesh, want: Color) -> bool:
	var colours: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for colour in colours:
		var c := colour.linear_to_srgb()
		if absf(c.r - want.r) + absf(c.g - want.g) + absf(c.b - want.b) < 0.04:
			return true
	return false


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
