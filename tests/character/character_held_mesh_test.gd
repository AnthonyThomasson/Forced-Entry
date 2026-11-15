extends GameTest
## What a character holds is drawn on its 3D body (#193 phase 2, Character and Items): the guns,
## grenades and nothing for a fist or an empty hand. Asserted at the seams: each gun is a mesh as
## long as its config row's art (the spec numbers are copied here), two guns of a kind share one
## mesh and another kind has its own, the mesh sits in the weapon hand and points where the 2D
## weapon is drawn (along the weapon's facing, up when the gun is raised off a wall), it follows the
## hand through a grenade's wind-up, it swaps with the held slot and is gone with nothing held, it
## goes with a seated body and costs no write while the character holds still. What it looks like
## is judged in a window, `character_held_mesh_windowed_test.gd`.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const SCRATCH := "user://settings_character_held_mesh_test.json"
## The held art's length (px, butt to muzzle), by item: the config rows' `art_size.y`, copied.
const LENGTH := { 3: 13.0, 5: 28.0, 6: 36.0, 7: 11.0, 8: 10.0 }
const ALL := [3, 5, 6, 7, 8]


func describe() -> Dictionary:
	return {
		"name": "A character's held item is a mesh in its hand that follows the 2D hold pose",
		"description": "Each gun and grenade is a mesh sized by its config row, shared per kind, "
			+ "in the weapon hand along the weapon's facing, raised off a wall, following a "
			+ "grenade's wind-up, swapped with the slot, gone for fists, hidden when seated, "
			+ "written only on change.",
		"tags": ["mirror", "3d", "render", "meshkit", "character", "items", "held"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	var x := 150.0
	for slot: int in ALL:
		s.actor(StringName("slot%d" % slot), &"puppet", Vector2(x, 200), { "start_slot": slot })
		x += 130.0
	s.actor(&"pistol2", &"puppet", Vector2(150, 350), { "start_slot": 3 })
	s.actor(&"fists", &"puppet", Vector2(280, 350), { "start_slot": 2 })
	s.actor(&"empty", &"puppet", Vector2(410, 350), { "start_slot": 1 })
	s.actor(&"swapper", &"puppet", Vector2(540, 350), { "start_slot": 3 })
	s.actor(&"thrower", &"puppet", Vector2(670, 350), { "start_slot": 8 })
	s.actor(&"south", &"puppet", Vector2(800, 350), { "start_slot": 3 })
	s.actor(&"walled", &"puppet", Vector2(30, 500), { "start_slot": 6 })
	s.actor(&"seated", &"puppet", Vector2(300, 500), { "start_slot": 6 })
	s.von_script([])


func run(t: TestContext) -> void:
	var east: Array[StringName] = [
		&"pistol2", &"fists", &"empty", &"swapper", &"thrower", &"seated",
	]
	for slot: int in ALL:
		east.append(StringName("slot%d" % slot))
	for id: StringName in east:
		t.puppet(id).aim_at(t.actor(id).global_position + Vector2(1000, 0))
	t.puppet(&"south").aim_at(t.actor(&"south").global_position + Vector2(0, 1000))
	t.puppet(&"walled").aim_at(t.actor(&"walled").global_position + Vector2(-1000, 0))
	Probe.arm(t.actor(&"slot7"), 1, 0)
	Probe.arm(t.actor(&"slot8"), 0, 1)
	Probe.arm(t.actor(&"thrower"), 0, 3)
	for id: StringName in [&"slot7", &"slot8", &"thrower"]:
		t.puppet(id).select_slot(7 if id == &"slot7" else 8)
	await t.seconds(1.2)
	var mirror := _mirror(t)
	CharacterMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(4)
	_check_each_item(t, mirror)
	_check_shared(t, mirror)
	_check_in_the_hand(t, mirror)
	_check_raised(t, mirror)
	await _check_thrown(t, mirror)
	await _check_swap(t, mirror)
	await _check_idle(t, mirror)
	await _check_seated(t, mirror)


## Every gun and grenade is a mesh of its row's length; fists and an empty hand show none; the mesh
## is lit and tinted as the figure's other parts are (a figure, no shadow).
func _check_each_item(t: TestContext, mirror: WorldMirror) -> void:
	for slot: int in ALL:
		var held := _held(t, mirror, StringName("slot%d" % slot))
		if not t.require(
			held != null and held.visible,
			"slot %d's item is shown in the hand" % slot,
		):
			continue
		var length := held.mesh.get_aabb().size.z
		t.expect_near(length, LENGTH[slot], 1.0, "slot %d: the mesh is its art's length" % slot)
		t.check(
			held.get_instance_shader_parameter(&"figure") == 1.0,
			"slot %d: the item is a figure for the pixel post" % slot,
		)
		_check_wears_its_art(t, held, t.actor(StringName("slot%d" % slot)).inventory.current_item())
		t.check(
			held.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"slot %d: a held item is too small to cast a shadow" % slot,
		)
	for id: StringName in [&"fists", &"empty"]:
		var held := _held(t, mirror, id)
		t.check(held == null or not held.visible, "%s: nothing is drawn in the hand" % id)


## The held node wears the item's flat art: the textured toon of `held_texture()`, its rect in
## units.
func _check_wears_its_art(t: TestContext, held: MeshInstance3D, item: Item) -> void:
	var texture := item.art.held_texture()
	t.check(
		held.material_override == ToonMaterial.textured(texture),
		"%s: the node wears its flat art" % item.display_name,
	)
	var rect := item.art.held_rect()
	var got: Variant = held.get_instance_shader_parameter(&"uv_rect")
	t.check(
		got is Vector4 and (got as Vector4).is_equal_approx(
			Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y) * RenderConfig.unit
		),
		"%s: over the art's footprint in the hand's frame" % item.display_name,
	)


## Two pistols share one mesh; a rifle has its own.
func _check_shared(t: TestContext, mirror: WorldMirror) -> void:
	var a := _held(t, mirror, &"slot3")
	var b := _held(t, mirror, &"pistol2")
	var rifle := _held(t, mirror, &"slot6")
	if a == null or b == null or rifle == null:
		return
	t.check(a.mesh == b.mesh, "two pistols of one look share one mesh")
	t.check(a.mesh != rifle.mesh, "a rifle is not the pistol's mesh")


## The mesh sits at the weapon hand and its muzzle leads along the weapon's facing: east for the
## ones aimed east, south (3D +z) for the south one.
func _check_in_the_hand(t: TestContext, mirror: WorldMirror) -> void:
	for id: StringName in [&"slot3", &"slot5", &"slot6", &"south"]:
		var body := _body_of(t, mirror, id)
		var held := body.held() if body != null else null
		if held == null:
			continue
		var item: Item = t.actor(id).inventory.current_item()
		var hand := body.get_child(BodyMesh.HAND + item.weapon_hand()) as Node3D
		t.check(
			held.position.distance_to(hand.position) < 1.0,
			"%s: the item sits in the weapon hand (%.1f px off)" % [
				id,
				held.position.distance_to(hand.position),
			],
		)
	var east := _held(t, mirror, &"slot6")
	var south := _held(t, mirror, &"south")
	if east != null:
		t.check(
			east.basis.z.normalized().dot(Vector3.RIGHT) > 0.95,
			"a rifle aimed east points its muzzle east (%s)" % east.basis.z,
		)
	if south != null:
		t.check(
			south.basis.z.normalized().dot(Vector3.BACK) > 0.95,
			"a pistol aimed south points its muzzle south (%s)" % south.basis.z,
		)


## A long gun raised off a wall points up (the 2D art foreshortens it, from above a barrel pointing
## up), as the one in the open stays level.
func _check_raised(t: TestContext, mirror: WorldMirror) -> void:
	var walled := _held(t, mirror, &"walled")
	var open := _held(t, mirror, &"slot6")
	if walled == null or open == null:
		return
	t.require(t.actor(&"walled").weapon.raise() > 0.95, "premise: the rifle is raised off the wall")
	t.check(
		walled.basis.z.normalized().y > 0.7,
		"a raised rifle points its muzzle up (%s)" % walled.basis.z,
	)
	t.check(open.basis.z.normalized().y < 0.1, "a rifle held to the aim stays level")


## A grenade follows the hand as it winds up to throw: the hand moves, the mesh with it.
func _check_thrown(t: TestContext, mirror: WorldMirror) -> void:
	var body := _body_of(t, mirror, &"thrower")
	if body == null:
		return
	var held := body.held()
	var item: Item = t.actor(&"thrower").inventory.current_item()
	var hand := body.get_child(BodyMesh.HAND + item.weapon_hand()) as Node3D
	var before := hand.position
	t.puppet(&"thrower").shoot()
	var moved := 0.0
	var worst := 0.0
	for i in 18:
		await t.frames(1)
		moved = maxf(moved, hand.position.distance_to(before))
		worst = maxf(worst, held.position.distance_to(hand.position))
	t.check(moved > 3.0, "premise: the hand winds back for the throw (%.1f px)" % moved)
	t.check(worst < 1.0, "the grenade stays in the hand through the wind-up (%.1f px)" % worst)


## A slot change swaps the mesh: the pistol's for the rifle's, and nothing for the empty hand.
func _check_swap(t: TestContext, mirror: WorldMirror) -> void:
	var body := _body_of(t, mirror, &"swapper")
	if body == null:
		return
	var held := body.held()
	t.expect_near(held.mesh.get_aabb().size.z, 13.0, 1.0, "the swapper starts with a pistol")
	t.puppet(&"swapper").select_slot(6)
	await t.frames(4)
	t.check(held.visible, "the rifle is shown after the swap")
	t.expect_near(held.mesh.get_aabb().size.z, 36.0, 1.0, "the mesh is now the rifle's")
	_check_wears_its_art(t, held, t.actor(&"swapper").inventory.current_item())
	t.puppet(&"swapper").select_slot(1)
	await t.frames(4)
	t.check(not held.visible, "an empty hand shows nothing")
	t.puppet(&"swapper").select_slot(5)
	await t.frames(4)
	t.check(held.visible, "and the item is back when one is held again")
	t.expect_near(held.mesh.get_aabb().size.z, 28.0, 1.0, "as the SMG's mesh")
	_check_wears_its_art(t, held, t.actor(&"swapper").inventory.current_item())


## A gun held still (the rifle and the pistol) is written on few frames: a mark put on the mesh is
## overwritten only when the hand drifts (breath), under one frame in ten.
func _check_idle(t: TestContext, mirror: WorldMirror) -> void:
	for id: StringName in [&"slot6", &"slot3"]:
		var held := _held(t, mirror, id)
		if held == null:
			continue
		var mark := Transform3D(Basis(), Vector3(999.0, 0.0, 0.0))
		var frames := ceili(CharacterPoseHeadConfig.breath_period * 60.0) + 30
		var writes := 0
		for i in frames:
			held.transform = mark
			await t.frames(1)
			if held.transform != mark:
				writes += 1
		t.check(
			writes * 10 < frames,
			"%s: a held gun is placed on %d of %d frames (under one in ten)" % [id, writes, frames],
		)


## A seated body (shapes disabled) has no item shown, and it is back when the shapes are.
func _check_seated(t: TestContext, mirror: WorldMirror) -> void:
	var held := _held(t, mirror, &"seated")
	if held == null:
		return
	var shape := _shape_of(t.actor(&"seated"))
	shape.set_deferred(&"disabled", true)
	await t.frames(3)
	t.check(not held.is_visible_in_tree(), "a seated character's item is not shown")
	shape.set_deferred(&"disabled", false)
	await t.frames(3)
	t.check(held.is_visible_in_tree(), "and it is back when the shapes are enabled")


## The body the mirror shows the actor `id` by, or null (it ends the test).
func _body_of(t: TestContext, mirror: WorldMirror, id: StringName) -> BodyMesh:
	var shown := mirror.proxies_of(t.actor(id))
	if not t.require(shown.size() == 1 and shown[0] is BodyMesh, "%s is shown by a body" % id):
		return null
	return shown[0] as BodyMesh


## The held-item node of the body of `id`, or null.
func _held(t: TestContext, mirror: WorldMirror, id: StringName) -> MeshInstance3D:
	var body := _body_of(t, mirror, id)
	return body.held() if body != null else null


## The first collision shape of `body`.
func _shape_of(body: Node) -> CollisionShape2D:
	for child in body.get_children():
		if child is CollisionShape2D:
			return child
	return null


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
