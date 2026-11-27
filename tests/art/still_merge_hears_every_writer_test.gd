extends GameTest
## Every writer of a mesh's look takes a merged mesh out of its chunk (`MeshNodes.changed`,
## interface 12) before the next picture, one table per writer: the mark of a moving thing, a
## character's figure mark, a texture put on and taken off, the darkening of a hit on a piece whose
## mesh is not built again, the wall fade's dither and its shadow, a glow, and the sun's caster
## layers. A mesh on an awake body is not taken at all. Each chunk's instance casts and is on the
## layers of every mesh in it.

const SunCasters := preload("res://scenes/lighting/sun_casters.gd")
const CASTS := &"instance_geometry_set_cast_shadows_setting"
const LAYERS := &"instance_set_layer_mask"
## A render layer no light or pass uses.
const SPARE_LAYER := 1 << 6
const TABLES := 16
## The first of the tables no earlier step has written.
const UNWRITTEN := 8

var _mirror: MeshCarrier


func describe() -> Dictionary:
	return {
		"name": "Every write of a merged mesh's look is heard the next frame",
		"description": "Each writer of a mesh's material, instance parameters, shadow setting or "
			+ "layers takes it out of its merged chunk; an awake piece is never taken; a chunk "
			+ "casts and is layered as its meshes are.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 620))
	for i in TABLES:
		var at := Vector2(90 + 140 * (i % 4), 100 + 130 * floorf(i / 4.0))
		s.object(StringName("table%d" % i), "table", at)
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	_mirror = MeshCarrier.new()
	ObjectMeshes.register(_mirror.builders)
	t.world.add_child(_mirror)
	_mirror.carry(t.world)
	await t.seconds(2.0)
	var rigs: Array[FurnitureRig] = []
	for i in TABLES:
		rigs.append(_mirror.mesh_of(t.object(StringName("table%d" % i))) as FurnitureRig)
	_mirror.merge.build_all()
	await _writers(t, rigs)
	await _suns(t, rigs)
	_awake(t, rigs)
	_chunks_as_members(t, rigs)


## One merged table to each writer.
func _writers(t: TestContext, rigs: Array[FurnitureRig]) -> void:
	var writers := _table()
	var at := 0
	for label: String in writers:
		var rig := rigs[at]
		at += 1
		if not t.require(_mirror.merge.shows(rig.body), "premise: %s: merged" % label):
			continue
		(writers[label] as Callable).call(rig)
		await _next_frame(t)
		t.check(not _mirror.merge.shows(rig.body), "%s: the mesh draws itself" % label)


## Writer name -> what it does to a table's rig.
func _table() -> Dictionary:
	return {
		"MeshNodes.moving": func(rig: FurnitureRig) -> void: MeshNodes.moving(rig.body),
		"MeshNodes.figure": func(rig: FurnitureRig) -> void: MeshNodes.figure(rig.body),
		"MeshNodes.textured": func(rig: FurnitureRig) -> void:
			var art := MeshNodes.shown_texture(rig.body)
			assert(art != null)
			MeshNodes.textured(rig.body, art, Rect2(0, 0, 10, 10)),
		"MeshNodes.textured, no art": func(rig: FurnitureRig) -> void:
			MeshNodes.textured(rig.body, null, Rect2()),
		"a hit's darkening": _darken,
		"MeshNodes.fade": func(rig: FurnitureRig) -> void: MeshNodes.fade(rig.body, 0.5),
		"the fade's shadow": func(rig: FurnitureRig) -> void:
			var parts: Array[GeometryInstance3D] = [rig.body]
			var shadow := FadeShadow.new()
			shadow.remember(parts)
			shadow.apply(parts, false),
		"MeshNodes.glow": func(rig: FurnitureRig) -> void:
			MeshNodes.glow(rig.body, Color.WHITE, 0.0),
	}


## The rig hears its piece's `Deformable` record damage, and only it: the piece is not built again,
## so the tint is the one thing that changes.
func _darken(rig: FurnitureRig) -> void:
	for connection: Dictionary in rig.deformable.changed.get_connections():
		var heard: Callable = connection["callable"]
		if heard.get_object() != rig:
			rig.deformable.changed.disconnect(heard)
	rig.deformable.damage_total += 5.0
	rig.deformable.changed.emit()
	assert(rig.tint() != Color.WHITE)


## The sun's pass moves every mesh whose shadow reaches no street to a layer of its own: with no
## street at all, each one.
func _suns(t: TestContext, rigs: Array[FurnitureRig]) -> void:
	_rebuild()
	var rig := rigs[TABLES - 1]
	if not t.require(_mirror.merge.shows(rig.body), "premise: the sun's caster layer: merged"):
		return
	var layers := rig.body.layers
	var sun := DirectionalLight3D.new()
	TwinSpace.of_world(t.world).add_child(sun)  # in the world the meshes are drawn in
	var casters := SunCasters.new()
	t.world.add_child(casters)
	var none: Array[Rect2] = []
	casters.watch(sun, none, none, Vector3(0.3, -1.0, 0.2))
	t.require(rig.body.layers != layers, "premise: the sun's pass moved the mesh")
	await _next_frame(t)
	t.check(not _mirror.merge.shows(rig.body), "the sun's caster layer: the mesh draws itself")
	casters.queue_free()
	sun.queue_free()
	await _next_frame(t)


## A piece whose body is awake is not taken, its sleeping neighbours are.
func _awake(t: TestContext, rigs: Array[FurnitureRig]) -> void:
	var woken := UNWRITTEN + 6
	_rebuild()
	if not t.require(
		_mirror.merge.shows(rigs[woken].body), "premise: asleep, the table is merged"
	):
		return
	_mirror.merge.release()
	var table := t.object(StringName("table%d" % woken))
	(TwinSpace.twin_for(table) as RigidBody3D).sleeping = false
	_offer_all()
	_mirror.merge.build_all()
	t.require(_mirror.merge.shows(rigs[UNWRITTEN].body), "premise: a sleeping table is merged")
	t.check(not _mirror.merge.shows(rigs[woken].body), "awake, it is not")


## Meshes that differ in how they cast and in their layers are in chunks set up the same way.
func _chunks_as_members(t: TestContext, rigs: Array[FurnitureRig]) -> void:
	_mirror.merge.release()
	for i in range(UNWRITTEN, UNWRITTEN + 3):
		rigs[i].body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rigs[i + 3].body.layers = SPARE_LAYER
	_offer_all()
	_mirror.merge.build_all()
	var casts := {}
	var layers := {}
	var apart := 0
	for chunk in _mirror.merge.chunks():
		casts[chunk.given.get(CASTS)] = true
		layers[chunk.given.get(LAYERS)] = true
		for member in chunk.members:
			if (
				chunk.given.get(CASTS) != member.node.cast_shadow
				or chunk.given.get(LAYERS) != member.node.layers
			):
				apart += 1
	t.require(
		casts.size() > 1 and layers.size() > 1,
		"premise: chunks of more than one casting and layering (%d, %d)"
			% [casts.size(), layers.size()],
	)
	t.expect_eq(apart, 0, "meshes in a chunk that casts or is layered unlike them")


## Build the chunks again from the meshes as they are now.
func _rebuild() -> void:
	_mirror.merge.release()
	_offer_all()
	_mirror.merge.build_all()


## Offer every carried mesh, as the carrier does one it has just made.
func _offer_all() -> void:
	for body: Node2D in TwinSpace.of_world(_mirror.get_parent()).bodies():
		var mesh := _mirror.mesh_of(body)
		if mesh != null:
			_mirror.merge.offer(mesh)


## Past the merger's own pass of the frame after this one.
func _next_frame(t: TestContext) -> void:
	await t.world.get_tree().process_frame
	await t.world.get_tree().process_frame
