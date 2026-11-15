extends GameTest
## A grenade let go is a mesh in the 3D world (#193 phase 2, Items): in the air it is as high as the
## 2D lob's arc and follows its node, lying before it bursts it is flat on the floor, and it is gone
## with the burst; the spoon it pops lies beside it. Asserted at the seams: the mesh the mirror
## shows each by (`ItemMeshes.register`), its world bounds (the frag's art is 10 px long, the
## spoon's 8, copied from the config rows and `SpoonArt`) and the mirror's write count. The look is
## judged in a window, `items_projectile_mesh_windowed_test.gd`.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const SCRATCH := "user://settings_thrown_grenade_mesh_test.json"
const AIM := Vector2(420, 300)
## The frag's art length (px, `GrenadeConfig`'s `art_size.y`) and the spoon's (`SpoonArt.SIZE.y`).
const FRAG := 10.0
const SPOON := 8.0
const SLACK := 1.5
## How high the lob must carry the grenade (px): well over a character's height.
const ARC := 50.0


func describe() -> Dictionary:
	return {
		"name": "A thrown grenade is a mesh that flies the lob and lies flat",
		"description": "A frag thrown across the room is a mesh without its lever, high along "
			+ "the 2D lob, following its node, flat on the floor once it lies, costing no write "
			+ "there and gone with the burst; its spoon lies beside it.",
		"tags": ["mirror", "3d", "render", "items", "grenade"],
		"timeout": 40.0,
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
	s.actor(&"thrower", &"puppet", Vector2(100, 300), { "max_health": 100_000.0 })
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	ItemMeshes.register(mirror)
	mirror.mirror(t.world)
	Probe.arm(t.actor(&"thrower"), 0, 1)
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(
		await t.until(func(): return not Probe.live(t).is_empty(), 2.0),
		"it is thrown",
	):
		return
	await t.frames(2)
	var grenade: ThrownGrenade = Probe.live(t)[0]
	var shown := _shown(t, mirror, grenade, "the grenade in the air")
	if shown == null:
		return
	await _check_flight(t, grenade, shown)
	await _check_lying(t, mirror, grenade, shown)
	await _check_spoon(t, mirror)
	await _check_gone_with_the_burst(t, mirror, shown)


## Through the lob the mesh follows the node, and is as high as the 2D height says.
func _check_flight(t: TestContext, grenade: ThrownGrenade, shown: MeshInstance3D) -> void:
	var held: Mesh = grenade.item.art.held_mesh()
	t.check(shown.mesh != held, "it is not the mesh held with the lever down")
	t.check(
		shown.mesh.get_aabb().size.y < held.get_aabb().size.y,
		"the lever is gone: it is lower than the held mesh",
	)
	t.expect_near(shown.mesh.get_aabb().size.z, FRAG, SLACK, "it is as long as its art")
	var highest := 0.0
	var worst := 0.0
	var apart := 0.0
	while not _at_rest(t) and is_instance_valid(grenade):
		var box := _bounds(shown)
		highest = maxf(highest, box.position.y)
		worst = maxf(worst, absf(box.get_center().x - grenade.global_position.x))
		worst = maxf(worst, absf(box.get_center().z - grenade.global_position.y))
		apart = maxf(apart, absf(box.position.y - grenade.altitude()))
		await t.frames(1)
	t.check(highest > ARC, "the lob lifts it high (%.0f px)" % highest)
	t.check(worst < SLACK, "it follows its node through the flight (off by up to %.1f px)" % worst)
	t.check(apart < 0.5, "its underside is the 2D height (off by up to %.1f px)" % apart)


## Lying, it is flat on the floor at its place, and nothing is written for it.
func _check_lying(
	t: TestContext, mirror: WorldMirror, grenade: ThrownGrenade, shown: MeshInstance3D
) -> void:
	await t.frames(3)
	# The spoon the throw popped may still skid: it writes for itself.
	await t.until(
		func():
			return t.world.get_tree().get_nodes_in_group(&"dropped_items").all(
				func(n): return not n.is_physics_processing()
			),
		8.0,
	)
	await t.frames(3)
	var box := _bounds(shown)
	t.expect_near(box.position.y, 0.0, 0.1, "lying, it rests on the floor")
	t.check(box.size.y < 12.0, "and is flat (%.1f px high)" % box.size.y)
	t.expect_near(box.get_center().x, grenade.global_position.x, SLACK, "at its 2D x")
	t.expect_near(box.get_center().z, grenade.global_position.y, SLACK, "and its 2D y")
	var before := _signature(shown)
	var written := 0
	for _i in 20:
		await t.frames(1)
		written += mirror.written
	t.check(written == 0, "the mirror writes nothing for it lying (%d writes)" % written)
	t.check(_signature(shown) == before, "its mesh keeps its transforms")


## The spoon the throw popped lies on the floor as a strip as long as its art.
func _check_spoon(t: TestContext, mirror: WorldMirror) -> void:
	var spoons := t.world.get_children().filter(
		func(n): return n is DroppedItem and n.item is GrenadeSpoon
	)
	if not t.require(not spoons.is_empty(), "the throw popped a spoon"):
		return
	var shown := _shown(t, mirror, spoons[0], "the spoon")
	if shown == null:
		return
	t.expect_near(shown.mesh.get_aabb().size.z, SPOON, SLACK, "the spoon is as long as its art")
	await t.until(func(): return not spoons[0].is_physics_processing(), 5.0)
	t.expect_near(_bounds(shown).position.y, 0.0, 0.1, "the spoon lies on the floor")


## The burst frees the grenade and its mesh with it.
func _check_gone_with_the_burst(
	t: TestContext, mirror: WorldMirror, shown: MeshInstance3D
) -> void:
	var count := mirror.count
	t.require(await Probe.wait_boom(t, &"frag", 5.0), "the grenade goes off")
	await t.frames(3)
	t.check(not is_instance_valid(shown), "its mesh is gone with it")
	t.check(mirror.count < count, "and no longer counted (%d -> %d)" % [count, mirror.count])


## Whether a grenade has come to rest (the `rest` event).
func _at_rest(t: TestContext) -> bool:
	return t.happened(&"grenade", func(d: Dictionary) -> bool: return d.get("stage") == &"rest")


## The mesh instance the mirror shows `node` by (null, and a failed requirement, when none).
func _shown(t: TestContext, mirror: WorldMirror, node: Node2D, what: String) -> MeshInstance3D:
	var proxies := mirror.proxies_of(node)
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


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
