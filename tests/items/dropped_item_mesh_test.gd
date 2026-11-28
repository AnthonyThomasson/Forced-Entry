extends GameTest
## A dropped item is a mesh on the 3D floor (#193 phase 2, Items): the gun a dead hand let go of is
## its side profile lifted, lying flat at its 2D place and turn, falling from the hand while it
## falls, following its 2D node as it skids, and gone with its node. Asserted at the seams: the mesh
## the mirror shows a `DroppedItem` by (`ItemMeshes.register`), its world bounds (the spec numbers
## are copied here: a rifle's art is 36 px long, a pistol's 13) and the mirror's write count. What
## it looks like is judged in a window, `items_projectile_mesh_windowed_test.gd`.

const SCRATCH := "user://settings_dropped_item_mesh_test.json"
## The rifle's and the pistol's length lying (px), `GunConfig`'s `flat_size.y`, copied.
const RIFLE := 38.0
const PISTOL := 14.0
## The slack (px) of a position or an extent: a mesh is a low-poly solid.
const SLACK := 1.5


func describe() -> Dictionary:
	return {
		"name": "A dropped item is its flat-art mesh lying on the 3D floor",
		"description": "A dropped rifle is its side profile lifted, flat on the floor at its 2D "
			+ "place along its 2D angle, high while it falls, following its node as it skids, "
			+ "costing no write once it lies still and gone with its node.",
		"tags": ["mirror", "3d", "render", "items", "dropped"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	ItemMeshes.register(mirror)
	mirror.follow(t.world)
	await _check_falls_then_lies(t, mirror)
	await _check_follows_a_skid(t, mirror)
	await _check_still_costs_nothing(t, mirror)
	await _check_gone_with_its_node(t, mirror)


## From the hand it is high and falling; on the floor it is flat, on it, at its place, its muzzle
## along its angle (it spins as it lands, so the angle is read from the node).
func _check_falls_then_lies(t: TestContext, mirror: MeshFollower) -> void:
	var rifle := _drop(t, 6, Vector2(300, 300), 0.0, Vector2.ZERO)
	var item: Item = rifle.item
	await t.frames(2)
	var shown := _shown(t, mirror, rifle, "the dropped rifle")
	if shown == null:
		return
	var rifle_mesh := shown.mesh
	t.check(rifle_mesh == item.art.dropped_mesh(rifle.flipped()), "it is the rifle's lying mesh")
	t.check(_bounds(shown).position.y > 10.0, "falling from the hand it is well off the floor")
	await _rest(t, rifle)
	var box := _bounds(shown)
	t.expect_near(box.position.y, 0.0, 0.1, "lying, it rests on the floor")
	t.check(box.size.y < 12.0, "lying, it is flat (%.1f px high)" % box.size.y)
	t.expect_near(rifle_mesh.get_aabb().size.z, RIFLE, SLACK, "it is as long as its art")
	_check_points_along(t, shown, rifle, "the rifle")
	t.expect_near(box.get_center().x, rifle.global_position.x, SLACK, "centred on its 2D x")
	t.expect_near(box.get_center().z, rifle.global_position.y, SLACK, "centred on its 2D y")
	rifle.queue_free()
	var south := _drop(t, 3, Vector2(500, 300), PI * 0.5, Vector2.ZERO)
	await t.frames(2)
	var pistol := _shown(t, mirror, south, "the dropped pistol")
	if pistol == null:
		return
	await _rest(t, south)
	t.expect_near(pistol.mesh.get_aabb().size.z, PISTOL, SLACK, "a pistol is as long as its art")
	_check_points_along(t, pistol, south, "the pistol")
	var turned := _bounds(pistol)
	t.check(turned.size.y < 8.0, "lying on its side it is flat (%.1f px high)" % turned.size.y)
	t.check(pistol.mesh != rifle_mesh, "a pistol is not the rifle's mesh")


## The mesh's muzzle (its +z) points along the node's 2D angle: 2D `(cos a, sin a)` is 3D
## `(cos a, 0, sin a)`.
func _check_points_along(
	t: TestContext, shown: MeshInstance3D, node: DroppedItem, what: String
) -> void:
	var muzzle := shown.global_transform.basis * Vector3.BACK
	var angle := node.heading()
	var off := Vector2(muzzle.x, muzzle.z).angle_to(Vector2.from_angle(angle))
	t.expect_near(off, 0.0, 0.05, "%s's muzzle points along its 2D angle" % what)


## Thrown off at a speed it skids across the floor, and its mesh stays on its node.
func _check_follows_a_skid(t: TestContext, mirror: MeshFollower) -> void:
	var smg := _drop(t, 5, Vector2(200, 500), 0.0, Vector2(260, 0))
	await t.frames(2)
	var shown := _shown(t, mirror, smg, "the skidding SMG")
	if shown == null:
		return
	var worst := 0.0
	var start := smg.global_position.x
	for _i in 600:
		await t.frames(1)
		worst = maxf(worst, absf(_bounds(shown).get_center().x - smg.global_position.x))
		if not smg.is_physics_processing():
			break
	t.check(smg.global_position.x > start + 40.0, "the SMG skidded across the floor")
	t.check(worst < SLACK, "its mesh followed it all the way (off by up to %.1f px)" % worst)


## A still item is neither written nor updated: the mirror writes nothing and the mesh keeps its
## transform.
func _check_still_costs_nothing(t: TestContext, mirror: MeshFollower) -> void:
	var rifle := _drop(t, 6, Vector2(700, 200), 0.3, Vector2.ZERO)
	await _rest(t, rifle)
	await t.frames(3)
	var shown := _shown(t, mirror, rifle, "the resting rifle")
	if shown == null:
		return
	var before := _signature(shown)
	var written := 0
	for _i in 20:
		await t.frames(1)
		written += mirror.written
	t.check(written == 0, "the mirror writes nothing for a lying item (%d writes)" % written)
	t.check(_signature(shown) == before, "its mesh keeps its transforms")


## When the node goes, its mesh goes; a hidden node's mesh is hidden.
func _check_gone_with_its_node(t: TestContext, mirror: MeshFollower) -> void:
	var gun := _drop(t, 3, Vector2(800, 500), 0.0, Vector2.ZERO)
	await _rest(t, gun)
	await t.frames(2)
	var shown := _shown(t, mirror, gun, "the pistol to be removed")
	if shown == null:
		return
	var count := mirror.count
	gun.visible = false
	await t.frames(2)
	t.check(not shown.is_visible_in_tree(), "a hidden item's mesh is hidden")
	gun.visible = true
	gun.queue_free()
	await t.frames(3)
	t.check(not is_instance_valid(shown), "a freed item's mesh is freed")
	t.check(mirror.count == count - 1, "and no longer counted (%d -> %d)" % [count, mirror.count])


## A `DroppedItem` of the item in `slot` let go at `at` pointing along `angle` with `velocity`.
func _drop(t: TestContext, slot: int, at: Vector2, angle: float, velocity: Vector2) -> DroppedItem:
	var node := DroppedItem.spawn(ItemRegistry.create(slot), angle, velocity)
	node.place(t.world, at, at)
	return node


## The mesh instance the mirror shows `node` by (null, and a failed requirement, when none).
func _shown(t: TestContext, mirror: MeshFollower, node: Node2D, what: String) -> MeshInstance3D:
	var proxies: Array[Node3D] = []
	if mirror.mesh_of(node) != null:
		proxies.append(mirror.mesh_of(node))
	if not t.require(proxies.size() == 1, "%s is shown by one mesh" % what):
		return null
	var found := proxies[0].find_children("*", "MeshInstance3D", true, false)
	if not t.require(not found.is_empty(), "%s's mesh holds a mesh instance" % what):
		return null
	return found[0] as MeshInstance3D


## The world bounds of `shown`'s mesh (3D units, which are px here).
func _bounds(shown: MeshInstance3D) -> AABB:
	return shown.global_transform * shown.mesh.get_aabb()


## Every transform from `shown` up to the mirror, to see whether anything moved.
func _signature(shown: Node3D) -> Array:
	var out := []
	var node: Node = shown
	while node is Node3D:
		out.append((node as Node3D).transform)
		node = node.get_parent()
	return out


## Wait until `node` has come to rest.
func _rest(t: TestContext, node: DroppedItem) -> void:
	await t.until(func(): return not node.is_physics_processing(), 10.0)


func _mirror(t: TestContext) -> MeshFollower:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshFollower.new()
	view.add_child(mirror)
	return mirror
