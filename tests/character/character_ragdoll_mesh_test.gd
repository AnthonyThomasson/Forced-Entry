extends GameTest
## A character that dies is shown by its 3D body lying where the 2D ragdoll lays it (#193 phase 2,
## Character, `domain-character/body-mesh.md`): the mirror keeps the body shown (`on_body_died`
## answers true), the parts follow the solver's joints through the fall, the settled body lies flat
## on the floor and costs no write until a blast wakes it, and what it held is gone (the 2D drops a
## gun as a `DroppedItem`, a grenade is not drawn). The look is judged in a window,
## `character_held_mesh_windowed_test.gd`.

const SCRATCH := "user://settings_character_ragdoll_mesh_test.json"
## A standing character is 58 px tall (`meshes.md`); a body on the floor is far under that: the
## thickest part resting on it (the trunk), copied from the how-to's proportions with room.
const LYING_HEIGHT := 24.0
## The parts worn on the body's back or the head's, which a body lying on its back lies on.
const WORN := [
	BodyMesh.PACK, BodyMesh.HAIR, BodyMesh.HEADWEAR, BodyMesh.PLATE, BodyMesh.PLATE + 1,
]


func describe() -> Dictionary:
	return {
		"name": "A dead character's body follows the 2D ragdoll and rests flat on the floor",
		"description": "The mirror keeps a dead body shown, its parts follow the ragdoll's joints "
			+ "as it falls, it lies flat when settled, writes nothing once the ragdoll sleeps and "
			+ "again when a blast wakes it, and the held item is not on it.",
		"tags": ["mirror", "3d", "render", "meshkit", "character", "ragdoll", "death"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.actor(&"dying", &"puppet", Vector2(300, 300), { "max_health": 10.0, "start_slot": 6 })
	s.actor(&"living", &"puppet", Vector2(600, 300), { "start_slot": 6 })
	s.von_script([])


func run(t: TestContext) -> void:
	var dying := t.actor(&"dying")
	t.puppet(&"dying").aim_at(Vector2(2000, 300))
	t.puppet(&"living").aim_at(Vector2(2000, 300))
	await t.seconds(1.0)
	var mirror := _mirror(t)
	CharacterMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(3)
	var shown := mirror.proxies_of(dying)
	if not t.require(shown.size() == 1 and shown[0] is BodyMesh, "the character has a body"):
		return
	var body := shown[0] as BodyMesh
	t.require(body.held().visible, "premise: it holds its rifle in the hand")
	dying.take_damage(1000.0)
	await t.frames(2)
	t.require(dying.is_dead and dying.anatomy.ragdoll != null, "premise: it fell as a ragdoll")
	t.check(body.visible, "a dead character's body stays shown")
	t.check(
		mirror.proxies_of(dying).size() == 1 and mirror.proxies_of(dying)[0] == body,
		"by the same body",
	)
	t.check(not body.held().visible, "and what it held is not on it")
	t.check(
		not t.world.find_children("*", "DroppedItem", true, false).is_empty(),
		"the rifle lay on the ground as a dropped item (the 2D's own)",
	)
	await t.seconds(0.25)
	_check_follows(t, body, dying, 4.0, "in the fall")
	if not t.require(
		await t.until(func(): return dying.anatomy.ragdoll.is_settled(), 8.0),
		"the ragdoll settles",
	):
		return
	await t.frames(3)
	_check_follows(t, body, dying, 0.5, "settled")
	_check_flat(t, body)
	await _check_rest(t, body, dying)
	t.check(
		(mirror.proxies_of(t.actor(&"living"))[0] as BodyMesh).held().visible,
		"a living character beside it still holds its rifle",
	)


## The head, the hands and the trunk of the body are where the ragdoll's joints are on the floor
## (the body's frame, px): within `tolerance`.
func _check_follows(
	t: TestContext,
	body: BodyMesh,
	dying: Node,
	tolerance: float,
	when: String,
) -> void:
	var ragdoll: Object = dying.anatomy.ragdoll
	var pairs := {
		BodyMesh.HEAD: ragdoll.point(0),
		BodyMesh.TORSO: ragdoll.point(2),
		BodyMesh.HAND: ragdoll.point(10),
		BodyMesh.SHIN: ragdoll.point(12),
	}
	for part: int in pairs:
		var joint: Vector3 = pairs[part]
		var at := (body.get_child(part) as Node3D).position
		var gap := Vector2(at.x - joint.x, at.z - joint.y).length()
		t.check(
			gap < tolerance,
			"%s: part %d is at the ragdoll's joint (%.1f px off)" % [when, part, gap],
		)
	var head := (body.get_child(BodyMesh.HEAD) as Node3D).position
	t.check(
		Vector2(head.x, head.z).length() > 12.0 or when == "in the fall",
		"the settled body has fallen from where it stood (head %.0f px over)" % head.length(),
	)


## A settled body lies on the floor: no part rises past the thickness of the trunk, not the 58 px
## of a standing one, and the body itself (trunk, head, limbs: not the pack, the plates or the hair
## worn on the side it lies on, which sink in the floor) is not in it.
func _check_flat(t: TestContext, body: BodyMesh) -> void:
	var top := 0.0
	var lowest := INF
	var lowest_part := -1
	for part: Node in body.get_children():
		var node := part as MeshInstance3D
		if node == null or not node.visible:
			continue
		var inside := body.global_transform.affine_inverse() * node.global_transform
		var box := inside * node.mesh.get_aabb()
		top = maxf(top, box.end.y)
		if WORN.has(part.get_index()):
			continue
		if box.position.y < lowest:
			lowest = box.position.y
			lowest_part = part.get_index()
	t.check(top < LYING_HEIGHT, "the body lies flat (%.1f px at its highest)" % top)
	t.check(
		lowest > -4.0,
		"and not in the floor (part %d is %.1f px at its lowest)" % [lowest_part, lowest],
	)


## A settled body is written no more; a blast that wakes the ragdoll moves it again.
func _check_rest(t: TestContext, body: BodyMesh, dying: Node) -> void:
	var trunk := body.get_child(BodyMesh.TORSO) as Node3D
	var mark := Transform3D(Basis(), Vector3(999.0, 0.0, 0.0))
	trunk.transform = mark
	await t.frames(30)
	t.check(trunk.transform == mark, "a settled body is not written again")
	dying.anatomy.ragdoll.blast(Vector2(500.0, 0.0))
	await t.frames(6)
	t.check(trunk.transform != mark, "a blast that wakes the ragdoll moves the body again")


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
