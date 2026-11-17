extends GameTest
## A character's shadow in the 3D render is a drop shadow, short and under it (#193 phase 3,
## Character, `domain-character/body-mesh.md`): a patch on the floor (`MeshNodes.shade`) a body
## radius and a bit across, shifted a little away from the art's light as the 2D body's is, and none
## of the body's parts casts a shadow from the lights: a light's shadow of a 74 tall body is as long
## as the light is low (a body 200 px from a ceiling fixture 400 up would throw 45 px, the sun at 68
## degrees 30), where the drop shadow reaches `radius x (shade_radius + shade_shift)` at most. A
## dead body has none, as the 2D one has none.
##
## It reads (`mirror.proxies_of`) the `BodyMesh` and its children, `DropShadow` and the parts.

const SCRATCH := "user://settings_character_drop_shadow_test.json"
## What a drop shadow must stay well under: a body's shadow from a ceiling fixture 200 px away.
const STANDING_REACH := 25.0


func describe() -> Dictionary:
	return {
		"name": "A character's shadow in 3D is a short drop shadow under it, cast by no light",
		"description": "The body mesh has a drop-shadow patch on the floor, within a body radius "
			+ "and a bit of it, away from the art's light, and no part of the body or the held "
			+ "item casts a shadow from a light; a dead body's patch is gone.",
		"tags": ["mirror", "3d", "render", "character", "lighting"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.actor(&"stander", &"puppet", Vector2(150, 200), { "facing": Vector2.RIGHT, "start_slot": 3 })
	s.actor(&"dying", &"puppet", Vector2(400, 200), { "max_health": 10.0 })
	s.von_script([])


func run(t: TestContext) -> void:
	await t.seconds(0.8)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	CharacterMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(3)
	var stander := _body_of(t, mirror, &"stander")
	var dying := _body_of(t, mirror, &"dying")
	if stander == null or dying == null:
		return
	_check_patch(t, stander, t.actor(&"stander"))
	_check_no_light_casts(t, stander)
	t.actor(&"dying").take_damage(1000.0)
	await t.seconds(0.5)
	var patch := dying.get_node("DropShadow") as MeshInstance3D
	t.check(not patch.visible, "a dead body's drop shadow is gone")


## The patch lies flat on the floor, near the body's own spot, away from the art's light, no wider
## than the config says.
func _check_patch(t: TestContext, body: BodyMesh, actor: Node2D) -> void:
	var patch := body.get_node_or_null("DropShadow") as MeshInstance3D
	if not t.require(patch != null, "the body has a drop shadow"):
		return
	var radius: float = actor.radius
	var shift := radius * CharacterShadowConfig.shade_shift
	var reach := radius * CharacterShadowConfig.shade_radius + shift
	var flat := Vector2(patch.position.x, patch.position.z)
	t.check(
		flat.length() <= shift + 0.01,
		"the patch is within %.1f px of the body's spot (%.1f)" % [shift, flat.length()],
	)
	t.check(
		flat.dot(-ArtCanvasConfig.light_from.normalized()) > 0.0,
		"and shifted away from the light, as the 2D shadow is",
	)
	var size := (patch.mesh as ArrayMesh).get_aabb().size
	t.expect_near(
		size.x * 0.5, radius * CharacterShadowConfig.shade_radius, 0.01,
		"the patch is the config's number of radii across",
	)
	t.check(
		reach < STANDING_REACH,
		"its far edge (%.1f px) is nowhere near a light's shadow" % reach,
	)
	t.expect_near(
		patch.position.y, CharacterShadowConfig.shade_lift, 0.01, "it lies on the floor"
	)
	t.check(
		patch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the patch is not cast by a light either",
	)


## No part of the body, the held item or the patch casts a shadow from a light: the drop shadow is
## the body's.
func _check_no_light_casts(t: TestContext, body: BodyMesh) -> void:
	var casting := 0
	var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for part: Node in body.get_children():
		if (part as GeometryInstance3D).cast_shadow != off:
			casting += 1
	t.expect_eq(casting, 0, "no part of the body casts a shadow from a light")


func _body_of(t: TestContext, mirror: WorldMirror, id: StringName) -> BodyMesh:
	var shown := mirror.proxies_of(t.actor(id))
	if not t.require(shown.size() == 1 and shown[0] is BodyMesh, "%s is shown by a body" % id):
		return null
	return shown[0] as BodyMesh
