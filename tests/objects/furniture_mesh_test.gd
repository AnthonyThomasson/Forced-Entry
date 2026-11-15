extends GameTest
## The domestic furniture kinds are shown by kit-built meshes (#193 phase 2,
## `domain-art/meshes.md`): Objects registers a builder per art id (sofa, chair, cabinet, shelf,
## counter, appliance, bed, office chair, toilet, bath, rug, plant, lamp, coat rack, recliner,
## fixture, hotplate) under `MirrorProxy.furniture_key(art)`, and the mirror shows a piece of each
## by its rig in place of its proxy box. Each mesh stands within the piece's own footprint and
## covers most of it, at the
## height the how-to's table gives its class, in the colour the painter draws; pieces of one look
## share the one `Mesh`; a piece with state that changes its look writes only on change (a lamp's
## glow, a bed's blanket, a dent's tint); at `RenderConfig.unit = 0.5` every length halves.
## Expected numbers are the spec's (`domain-art/meshes.md`), not read back from the holders.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const ObjectArt := preload("res://scenes/objects/art/object_art.gd")
const SCRATCH := "user://settings_furniture_mesh_test.json"
const MATCH := {
	"seed": 2,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}
## Per catalogue piece: its art id, the height (px) its mesh stands to (`tol` of slack, a leaning
## back or a curving leaf), the height it starts at (`base`, 0), the least share of the footprint's
## width and depth it covers, and `wall` for a piece that hangs thin against the wall at the back of
## its footprint. Heights are the how-to's class heights; the few that rise past the class number
## are the part on top: the toilet's flush button (cistern 30 + 1), the bath's tap (rim 20 + 6), the
## coat rack's hat (post 64 + 4), the rug's three medallion steps (border and field .9 + .9).
const KINDS := {
	&"sofa": { "art": "sofa", "top": 38.0, "base": 0.0, "cover": 0.95 },
	&"chair": { "art": "chair", "top": 36.0, "base": 0.0, "cover": 0.8 },
	&"wardrobe": { "art": "cabinet", "top": 78.0, "base": 0.0, "cover": 0.95 },
	&"bookshelf": { "art": "shelf", "top": 72.0, "base": 0.0, "cover": 0.95 },
	&"kitchen_counter": { "art": "counter", "top": 44.0, "base": 0.0, "cover": 0.95 },
	&"fridge": { "art": "appliance", "top": 70.0, "base": 0.0, "cover": 0.8 },
	&"bed": { "art": "bed", "top": 34.0, "base": 0.0, "cover": 0.8 },
	&"office_chair": { "art": "office_chair", "top": 42.0, "tol": 0.3, "cover": 0.5 },
	&"toilet": { "art": "toilet", "top": 31.0, "cover": 0.5 },
	&"bathtub": { "art": "bath", "top": 26.0, "cover": 0.95 },
	&"rug": { "art": "rug", "top": 1.8, "cover": 0.9 },
	&"plant": { "art": "plant", "top": 36.0, "tol": 0.3, "cover": 0.5 },
	&"lamp": { "art": "lamp", "top": 52.0, "base": 0.0, "cover": 0.5 },
	&"coat_rack": { "art": "coat_rack", "top": 68.0, "cover": 0.3 },
	&"recliner_rig": { "art": "recliner", "top": 30.0, "base": 0.0, "cover": 0.8 },
	&"mirror": { "art": "fixture", "top": 80.0, "base": 46.0, "cover": 0.8, "wall": true },
	&"hotplate": { "art": "hotplate", "top": 19.0, "base": 0.0, "cover": 0.8 },
}


func describe() -> Dictionary:
	return {
		"name": "The domestic furniture kinds are shown by kit-built meshes",
		"description": "A builder is registered per art id; the mirror shows a piece of each "
			+ "by its rig: within its footprint, at the spec's height, in the painter's "
			+ "colour, one shared mesh for pieces alike, state written only on change, half "
			+ "size at half scale; Main's 3D view registers them all.",
		"tags": ["mirror", "3d", "render", "meshkit", "furniture"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 2400, 700))
	var at := Vector2(140.0, 140.0)
	for id: StringName in KINDS:
		s.object(id, String(id), at)
		at.x += 190.0
		if at.x > 2300.0:
			at = Vector2(140.0, at.y + 250.0)
	s.object(&"sofa_b", "sofa", Vector2(140.0, 640.0))
	s.object(&"lamp_b", "lamp", Vector2(400.0, 640.0))
	s.actor(&"sleeper", &"puppet", Vector2(700.0, 640.0))
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	await t.frames(5)
	var mirror := _mirror(t)
	ObjectMeshes.register(mirror.builders)
	_check_registered(t, mirror)
	mirror.mirror(t.world)
	await t.frames(3)
	for id: StringName in KINDS:
		var rig := _rig_of(mirror, t.object(id))
		if t.require(rig != null, "%s is shown by a rig of its own, not a proxy box" % id):
			_check_shape(t, id, rig, t.object(id), 1.0)
	_check_colours(t, mirror)
	_check_sharing(t, mirror)
	_check_static_pieces_cost_nothing(t, mirror)
	await _check_lamp(t, mirror)
	await _check_dent_tint(t, mirror)
	await _check_bed(t, mirror)
	await _check_half_scale(t)
	await _check_main(t)


## Every art id has a builder under its own hook key.
func _check_registered(t: TestContext, mirror: WorldMirror) -> void:
	for id: StringName in KINDS:
		var key := MirrorProxy.furniture_key(KINDS[id]["art"])
		t.check(mirror.builders.has(key), "a builder is registered under %s" % key)
		t.check(mirror.builders[key].is_valid(), "the builder of %s is callable" % key)
	t.check(mirror.builders.has(MirrorProxy.furniture_key("table")), "the table's is still there")


## The rig of `body` when the mirror shows it by one (a `FurnitureRig`), else null (a proxy box).
func _rig_of(mirror: WorldMirror, body: Node) -> FurnitureRig:
	var shown := mirror.proxies_of(body)
	if shown.size() != 1 or not shown[0] is FurnitureRig:
		return null
	return shown[0] as FurnitureRig


## The mesh stands in the piece's footprint (in the body's frame: a turned piece is the turned
## mesh), covers most of it and runs from its base to the spec'd height, all times `factor`.
func _check_shape(
	t: TestContext, id: StringName, rig: FurnitureRig, piece: Node, factor: float
) -> void:
	var row: Dictionary = KINDS[id]
	var size: Vector2 = piece.get("size") * factor
	var box := rig.body.mesh.get_aabb()
	var at := "%s (x%.1f)" % [id, factor]
	t.check(
		box.size.x <= size.x + 0.01 and box.size.z <= size.y + 0.01,
		"%s stays within its footprint %s: %s" % [at, size, box.size],
	)
	var cover: float = row["cover"]
	var deep := 0.2 if row.has("wall") else cover
	t.check(
		box.size.x >= size.x * cover and box.size.z >= size.y * deep,
		"%s covers %.0f%% of its footprint %s: %s" % [at, cover * 100.0, size, box.size],
	)
	var tol: float = row.get("tol", 0.02)
	t.expect_near(box.end.y, float(row["top"]) * factor, tol * factor, "%s tops out" % at)
	t.expect_near(box.position.y, float(row.get("base", 0.0)) * factor, 0.02, "%s starts" % at)
	t.expect_near(box.get_center().x, 0.0, size.x * 0.3, "%s is centred (x)" % at)
	if row.has("wall"):
		t.check(box.get_center().z < 0.0, "%s hangs at the back of its footprint" % at)
	else:
		t.expect_near(box.get_center().z, 0.0, size.y * 0.3, "%s is centred (z)" % at)


## A face of the body carries the colour the painter draws the piece in (the lamp's shade is its
## tin, the painter's own constant).
func _check_colours(t: TestContext, mirror: WorldMirror) -> void:
	for id: StringName in KINDS:
		var piece := t.object(id)
		var rig := _rig_of(mirror, piece)
		if rig == null:
			continue
		var want := ObjectArt.drawn_color(piece.get("color"))
		var mesh := rig.body.mesh as ArrayMesh
		if id == &"lamp":
			want = ObjectArtDecorConfig.lamp_tin_color  # the shade is tin, whatever the piece's
		elif id == &"plant":
			want = want.lerp(ObjectArtDecorConfig.plant_dead_color, ObjectArtDecorConfig.plant_wilt)
		elif id == &"bed":
			mesh = (rig as FurnitureBedRig).blanket.mesh as ArrayMesh  # its blanket is the colour
		t.check(_has_colour(mesh, want), "%s has a face in its painted colour %s" % [id, want])


## Two pieces of one look share the one mesh; one of another look does not.
func _check_sharing(t: TestContext, mirror: WorldMirror) -> void:
	var first := _rig_of(mirror, t.object(&"sofa"))
	var second := _rig_of(mirror, t.object(&"sofa_b"))
	t.check(
		first != null and second != null and first.body.mesh == second.body.mesh,
		"two sofas alike share the one mesh",
	)
	var lamp := _rig_of(mirror, t.object(&"lamp"))
	var lamp_b := _rig_of(mirror, t.object(&"lamp_b"))
	t.check(
		lamp != null and lamp_b != null and lamp.body.mesh == lamp_b.body.mesh,
		"two lamps alike share the one mesh",
	)
	t.check(
		lamp != null and lamp.glows[0].mesh == lamp_b.glows[0].mesh,
		"and the one glow mesh",
	)
	t.check(
		first != null and lamp != null and first.body.mesh != lamp.body.mesh,
		"a sofa and a lamp do not",
	)


## A resting piece costs nothing per frame: no `mirror_update` and no `_process` on a rig, except a
## bed's, which looks every few frames.
func _check_static_pieces_cost_nothing(t: TestContext, mirror: WorldMirror) -> void:
	for id: StringName in KINDS:
		var rig := _rig_of(mirror, t.object(id))
		if rig == null:
			continue
		t.expect_eq(rig.has_method(&"mirror_update"), id == &"bed", "%s: mirror_update" % id)
		t.check(not rig.is_processing(), "%s runs no _process" % id)


## A lamp's glow node is lit by default, goes dark and lights again, and is written only when its
## state changes (a stale value left in the uniform shows a repeat write).
func _check_lamp(t: TestContext, mirror: WorldMirror) -> void:
	var rig := _rig_of(mirror, t.object(&"lamp"))
	if not t.require(rig != null and rig.glows.size() == 1, "the lamp has one glow node"):
		return
	var glow := rig.glows[0]
	t.check(rig.lit, "a lamp is lit to begin with")
	t.expect_near(_strength(glow), 1.0, 0.001, "its glow is on")
	rig.set_lit(false)
	t.expect_near(_strength(glow), 0.0, 0.001, "switched off, it does not glow")
	glow.set_instance_shader_parameter(&"emissive", Color(1, 2, 3, 4))
	rig.set_lit(false)
	t.expect_eq(
		glow.get_instance_shader_parameter(&"emissive"),
		Color(1, 2, 3, 4),
		"switching off a dark lamp writes nothing",
	)
	rig.set_lit(true)
	t.expect_near(_strength(glow), 1.0, 0.001, "lit again, it glows")
	var stove := _rig_of(mirror, t.object(&"hotplate"))
	t.check(stove != null and stove.glows.size() == 1, "the hotplate glows too (its hot ring)")
	t.check(
		glow.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "a glow casts no shadow"
	)
	await t.frames(1)


## A dent tints the solids as the 2D piece darkens, written only when the damage changes.
func _check_dent_tint(t: TestContext, mirror: WorldMirror) -> void:
	var piece := t.object(&"sofa")
	var rig := _rig_of(mirror, piece)
	if not t.require(rig != null, "the sofa has a rig"):
		return
	t.expect_eq(rig.tint(), Color.WHITE, "an unhurt sofa is untinted")
	var deformable: Deformable = piece.physics.deformable
	deformable.damage_total = 80.0
	deformable.changed.emit()
	var darker := Color.WHITE.darkened(Deformation.darken(80.0))
	t.expect_eq(rig.tint(), darker, "a damaged sofa is tinted as its 2D art darkens")
	t.expect_eq(
		rig.body.get_instance_shader_parameter(&"base_color"), darker, "the tint is in the solid"
	)
	rig.body.set_instance_shader_parameter(&"base_color", Color.RED)
	deformable.changed.emit()
	t.expect_eq(
		rig.body.get_instance_shader_parameter(&"base_color"),
		Color.RED,
		"a hit that changes nothing writes nothing",
	)
	await t.frames(1)


## A bed's blanket lies flat while a character lies on the bed and rises when they get up.
func _check_bed(t: TestContext, mirror: WorldMirror) -> void:
	var bed := t.object(&"bed")
	var rig := _rig_of(mirror, bed) as FurnitureBedRig
	if not t.require(rig != null and rig.blanket != null, "the bed has a blanket part"):
		return
	t.check(not rig.occupied, "an empty bed is not occupied")
	t.expect_near(rig.blanket.scale.y, 1.0, 0.001, "its blanket is raised")
	var sleeper := t.actor(&"sleeper")
	var puppet := t.puppet(&"sleeper")
	sleeper.global_position = bed.global_position + Vector2(0.0, 30.0)
	await t.frames(2)
	puppet.interact(bed, "lie")
	var lying: bool = await t.until(
		func() -> bool: return rig.occupied, 3.0, "someone lying on the bed flattens the blanket"
	)
	if lying:
		t.expect_near(
			rig.blanket.scale.y, 0.25, 0.001, "the blanket is flat while someone lies on it"
		)
	puppet.end_interaction()
	await t.until(
		func() -> bool: return not rig.occupied, 3.0, "the blanket rises when they get up"
	)
	t.expect_near(rig.blanket.scale.y, 1.0, 0.001, "and is raised again")


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


## Main's 3D view registers every kind's builder.
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
