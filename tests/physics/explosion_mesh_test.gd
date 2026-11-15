extends GameTest
## The look of a grenade's burst in a 3D match (#193 phase 2, Physics): a frag is a flash, a shock
## ring, a fireball and smoke standing at the burst's place over the floor, swelling and cooling
## through the 2D look's own life (`PhysicsExplosionConfig.looks`) and all gone, hidden, when it is
## over; a stun is smoke only. The pool of rigs is bounded under a burst of grenades, nothing is
## made as they go off, and when they are done nothing runs and nothing is written. Asserted at the
## seams: the layer `PhysicsMeshes.install` adds and `Physics.spawn_explosion`. The numbers are
## pinned here; the look is judged in a window, `physics_mesh_windowed_test.gd`.

const SCRATCH := "user://settings_explosion_mesh_test.json"
const AT := Vector2(400, 300)
const RIGS := 3


func describe() -> Dictionary:
	return {
		"name": "A grenade's burst is solid shapes that swell, cool and go out",
		"description": "A frag is a flash, a ring, a fireball and smoke at its place; a stun smoke "
			+ "only; each follows the 2D look's life; the pool of rigs is bounded and nothing runs "
			+ "once the bursts are over.",
		"tags": ["mirror", "3d", "render", "physics", "explosion"],
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
	s.set_static(PhysicsBlastMeshConfig, &"rigs", RIGS)
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	var layer := PhysicsMeshes.install(mirror)
	mirror.mirror(t.world)
	t.expect_eq(layer.blasts.shown(), 0, "no burst, no blast")
	t.check(not _any_visible(layer), "and no part showing")
	await _check_a_frag(t, layer)
	await _check_a_stun(t, layer)
	await _check_the_pool(t, layer)


## A frag: its parts at its place, swelling, cooling, then gone.
func _check_a_frag(t: TestContext, layer: FxLayer) -> void:
	var look: Dictionary = PhysicsExplosionConfig.looks[&"frag"]
	Physics.spawn_explosion(t.world, AT, &"frag")
	t.expect_eq(layer.blasts.shown(), 1, "a frag is one blast")
	t.check(layer.is_processing(), "and the layer runs")
	var rig := _live(layer)
	t.check(rig.flash[0].visible and rig.flash[1].visible, "the flash is lit at once")
	t.check(rig.ring.visible, "with its shock ring")
	t.check(rig.fire[0].visible and rig.fire[1].visible, "and a fireball, body and core")
	t.expect_near(_flat(rig.fire[0]).distance_to(AT), 0.0, 0.5, "the fireball is at the burst")
	t.expect_near(_flat(rig.flash[0]).distance_to(AT), 0.0, 0.5, "and so is the flash")
	var early := rig.fire[0].transform.basis.get_scale().x
	var first_tone: Color = rig.fire[0].get_meta(&"fx_tint")
	var glow: Variant = rig.fire[0].get_instance_shader_parameter(&"emissive")
	t.check(glow != null and glow.a > 0.0, "the fireball glows whatever the light")
	t.check(
		rig.fire[0].position.y > 0.0 and rig.fire[0].position.y < look["fireball_radius"],
		"it stands over the floor (%.1f)" % rig.fire[0].position.y,
	)
	await t.seconds(float(look["flash_time"]) + 0.05)
	t.check(not rig.flash[0].visible and not rig.flash[1].visible, "the flash is gone first")
	t.check(rig.fire[0].visible, "while the fireball burns")
	t.check(
		rig.fire[0].transform.basis.get_scale().x > early, "and has swollen (%.1f)" % early
	)
	await t.seconds(float(look["fireball_time"]))
	var late: Color = rig.fire[0].get_meta(&"fx_tint")
	t.check(late != first_tone, "the fireball cooled through its tones")
	t.check(not rig.fire[0].visible and not rig.ring.visible, "the fireball and ring are gone")
	t.check(_puffs(rig) > 0, "the smoke has begun and lingers (every puff has begun by now)")
	t.expect_eq(layer.blasts.shown(), 1, "so the blast is still on")
	await t.seconds(float(look["smoke_time"]))
	t.expect_eq(layer.blasts.shown(), 0, "within the smoke's life the blast is over")
	t.check(not _any_visible(layer), "every part is hidden")
	t.check(not layer.is_processing(), "and the layer rests")


## A stun: smoke only.
func _check_a_stun(t: TestContext, layer: FxLayer) -> void:
	var look: Dictionary = PhysicsExplosionConfig.looks[&"stun"]
	Physics.spawn_explosion(t.world, AT, &"stun")
	var rig := _live(layer)
	t.check(not rig.flash[0].visible and not rig.ring.visible, "a stun has no flash or ring")
	t.check(not rig.fire[0].visible, "and no fireball")
	await t.seconds(0.4)
	var puffs := _puffs(rig)
	t.check(puffs > 0 and puffs <= int(look["smoke_puffs"]), "thin smoke (%d puffs)" % puffs)
	await t.seconds(float(look["smoke_time"]))
	t.expect_eq(layer.blasts.shown(), 0, "it clears")


## A volley of grenades: no more rigs than the pool holds, nothing made, and a quiet end.
func _check_the_pool(t: TestContext, layer: FxLayer) -> void:
	var nodes := _blast_nodes(layer)
	var builds := MeshCache.builds
	for i in RIGS * 3:
		Physics.spawn_explosion(t.world, AT + Vector2(i * 20.0, 0.0), &"frag")
		await t.frames(2)
		t.check(layer.blasts.shown() <= RIGS, "never more blasts than rigs")
	t.expect_eq(layer.blasts.shown(), RIGS, "the pool is full")
	t.expect_eq(_blast_nodes(layer), nodes, "no part was made (a scorch may add a chunk)")
	t.expect_eq(MeshCache.builds, builds, "no mesh was made")
	await t.seconds(float(PhysicsExplosionConfig.looks[&"frag"]["smoke_time"]) + 0.3)
	t.expect_eq(layer.blasts.shown(), 0, "all gone")
	t.check(not layer.is_processing(), "and nothing runs")
	PhysicsExplosionConfig.fx_enabled = false
	Physics.spawn_explosion(t.world, AT, &"frag")
	t.expect_eq(layer.blasts.shown(), 0, "with the effects switched off none is shown")
	PhysicsExplosionConfig.fx_enabled = true


## How many nodes the layer has that are not the ink's chunks, which grow with each new scorch.
func _blast_nodes(layer: FxLayer) -> int:
	var count := 0
	for node in layer.get_children():
		count += 0 if node is InkChunk else 1
	return count


## How many of a rig's puffs of smoke are showing.
func _puffs(rig: BlastRig) -> int:
	var count := 0
	for puff in rig.puffs:
		count += 1 if puff.visible else 0
	return count


## The rig showing the blast.
func _live(layer: FxLayer) -> BlastRig:
	for rig in layer.blasts.rigs():
		if rig.live:
			return rig
	return null


## A part's place on the 2D plane (px).
func _flat(part: Node3D) -> Vector2:
	return Vector2(part.position.x, part.position.z)


## Whether any part of any rig is showing.
func _any_visible(layer: FxLayer) -> bool:
	for rig in layer.blasts.rigs():
		for part in rig.flash + rig.fire + rig.puffs:
			if part.visible:
				return true
		if rig.ring.visible:
			return true
	return false


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
