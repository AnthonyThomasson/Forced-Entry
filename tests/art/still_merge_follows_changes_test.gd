extends GameTest
## The still world's merged chunks (`StillMerge`, interface 27) let go of a mesh the moment it is
## not what they copied, before the next picture: the wall fade's write, a hidden piece, a hit's
## darkening and dent, a shove and a piece destroyed; a mesh whose look is the copied one again
## goes back to its chunk, and one that rested elsewhere joins anew. A mesh with a light's glow is
## never merged.

const IDS: Array[StringName] = [&"a", &"b", &"c", &"d", &"e"]
const LAMPS: Array[StringName] = [&"lamp", &"lamp2", &"lamp3"]

var _mirror: MeshCarrier


func describe() -> Dictionary:
	return {
		"name": "A merged mesh draws itself as soon as it changes",
		"description": "A fade, a hide, a hit, a shove and a destroyed piece take a mesh out of "
			+ "its merged chunk before the next picture; one restored goes back; glows stay out.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	for i in IDS.size():
		s.object(IDS[i], "table", Vector2(90 + 100 * i, 120))
	# three lamps: their glows would make a chunk of their own were they let in
	for i in LAMPS.size():
		s.object(LAMPS[i], "lamp", Vector2(120 + 90 * i, 300))
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	_mirror = MeshCarrier.new()
	ObjectMeshes.register(_mirror.builders)
	view.add_child(_mirror)
	_mirror.carry(t.world)
	await t.seconds(2.0)
	var merge := _mirror.merge
	merge.merge_now()
	var pieces: Array[MeshInstance3D] = []
	for id in IDS:
		var body: Node = t.object(id)
		pieces.append((_mirror.mesh_of(body) as FurnitureRig).body)
	if not t.require(pieces.all(merge.shows), "premise: a chunk draws each table"):
		return
	var wall := _wall_part()
	t.require(wall != null and merge.shows(wall), "premise: a chunk draws a wall segment")
	await _faded(t, merge, wall)
	await _relayered(t, merge, wall)
	await _hidden(t, merge, t.object(IDS[0]), pieces[0])
	await _darkened(t, merge, pieces[1])
	await _glows(t, merge)
	await _shoved(t, merge, t.object(IDS[2]), pieces[2])
	await _hit(t, merge, t.object(IDS[3]), pieces[3])
	await _destroyed(t, merge, t.object(IDS[4]))
	_released(t, merge)
	_offered_twice(t, merge)


## The wall fade thins a mesh and gives it back.
func _faded(t: TestContext, merge: StillMerge, wall: MeshInstance3D) -> void:
	MeshNodes.fade(wall, 0.25)
	await t.frames(1)
	t.check(not merge.shows(wall), "a fading wall segment draws itself")
	MeshNodes.fade(wall, 1.0)
	await t.frames(1)
	t.check(merge.shows(wall), "whole again, its chunk draws it")


## The sun's pass moves a mesh to another render layer: the chunk of the old layers lets it go.
func _relayered(t: TestContext, merge: StillMerge, wall: MeshInstance3D) -> void:
	var layers := wall.layers
	wall.layers = layers << 1
	MeshNodes.changed(wall)
	await t.frames(1)
	t.check(not merge.shows(wall), "a mesh on other render layers than its chunk draws itself")
	wall.layers = layers


func _hidden(t: TestContext, merge: StillMerge, body: Node, mesh: MeshInstance3D) -> void:
	(body as Node2D).visible = false
	await t.frames(2)
	t.check(not merge.shows(mesh), "a hidden piece leaves its chunk")
	(body as Node2D).visible = true
	await t.frames(2)
	t.check(merge.shows(mesh), "shown again, its chunk draws it")


func _darkened(t: TestContext, merge: StillMerge, mesh: MeshInstance3D) -> void:
	MeshNodes.base_color(mesh, Color(0.6, 0.6, 0.6))
	await t.frames(1)
	t.check(not merge.shows(mesh), "a piece tinted by damage draws itself")


## A lamp's glow flickers by its light's rhythm: its glow node is never merged.
func _glows(t: TestContext, merge: StillMerge) -> void:
	var rigs: Array[FurnitureRig] = []
	for id in LAMPS:
		rigs.append(_mirror.mesh_of(t.object(id)) as FurnitureRig)
	if not t.require(
		rigs.all(func(rig: FurnitureRig) -> bool: return rig != null and not rig.glows.is_empty()),
		"premise: the lamps glow",
	):
		return
	for rig in rigs:
		rig.set_glow_level(0.0)
		for glow in rig.glows:
			merge.offer(glow)
	await t.frames(1)
	merge.merge_now()
	for rig in rigs:
		t.check(
			rig.glows.all(func(glow: MeshInstance3D) -> bool: return not merge.shows(glow)),
			"a glow, even dimmed to nothing, is in no chunk",
		)
		t.check(merge.shows(rig.body), "premise: the lamp's body is merged")


## A shove takes the piece out; resting elsewhere, it joins again with company.
func _shoved(t: TestContext, merge: StillMerge, body: Node2D, mesh: MeshInstance3D) -> void:
	var from := body.global_position
	Knockback.push(body, Vector2(0.0, 4000.0))
	await t.frames(6)
	if not t.require(body.global_position.distance_to(from) > 2.0, "premise: the shove moved it"):
		return
	t.check(not merge.shows(mesh), "a shoved piece draws itself")


## A hit dents the piece and its mesh is built again: the old one is held by no chunk.
func _hit(t: TestContext, merge: StillMerge, body: Node, mesh: MeshInstance3D) -> void:
	var held := merge.held()
	var hit := HitInfo.new()
	hit.position = (body as Node2D).global_position
	hit.normal = Vector2.DOWN
	hit.direction = Vector2.UP
	hit.damage = 40.0
	hit.speed_factor = 1.0
	body.take_hit(hit)
	await t.frames(4)
	if not t.require(not is_instance_valid(mesh), "premise: the dent built the mesh again"):
		return
	t.check(merge.held() < held, "the old mesh is held no more")


func _destroyed(t: TestContext, merge: StillMerge, body: Node) -> void:
	var held := merge.held()
	body.queue_free()
	await t.frames(3)
	t.check(merge.held() < held, "a destroyed piece is held no more")
	for chunk in merge.chunks():
		t.check(
			chunk.members.all(
				func(m: MergeMember) -> bool: return is_instance_valid(m.node)
			),
			"no chunk keeps a freed mesh",
		)


## A released chunk is let go of: it and its members hold each other until then.
func _released(t: TestContext, merge: StillMerge) -> void:
	# chunks built anew, that no step of this test has had in hand
	merge.release()
	_offer_all(t, merge)
	merge.merge_now()
	if not t.require(not merge.chunks().is_empty(), "premise: there are chunks to release"):
		return
	var chunk := _first_chunk(merge)
	merge.release()
	t.check(chunk.get_ref() == null, "a released chunk is freed")


## A held mesh offered again is not copied into a second chunk.
func _offered_twice(t: TestContext, merge: StillMerge) -> void:
	for twice in 2:
		_offer_all(t, merge)
		merge.merge_now()
	var members := 0
	for chunk in merge.chunks():
		members += chunk.members.size()
	t.check(merge.held() > 0, "premise: meshes are merged")
	t.expect_eq(members, merge.held(), "each mesh is in one chunk")


## Offer every carried mesh, as the carrier does one it has just made.
func _offer_all(t: TestContext, merge: StillMerge) -> void:
	for body: Node2D in TwinSpace.of_world(t.world).bodies():
		var mesh := _mirror.mesh_of(body)
		if mesh != null:
			merge.offer(mesh)


## In a function of its own: a caller's temporaries would hold the chunk.
func _first_chunk(merge: StillMerge) -> WeakRef:
	return weakref(merge.chunks()[0])


## One segment of an arena wall's mesh.
func _wall_part() -> MeshInstance3D:
	for node: Node in NavTwins.walls_under(_mirror.get_parent().get_parent()):
		var mesh := _mirror.mesh_of(node)
		if mesh is WallMesh:
			var parts: Dictionary = (mesh as WallMesh).segments()
			if not parts.is_empty():
				return parts.values()[0]
	return null
