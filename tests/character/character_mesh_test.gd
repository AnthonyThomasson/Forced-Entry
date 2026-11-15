extends GameTest
## A character is shown by its own low-poly body, not the proxy capsule (#193 phase 2, Character,
## `domain-art/meshes.md`): Character's builder (`CharacterMeshes.register`, the `CHARACTER` hook
## key) gives the mirror a `BodyMesh` that follows the 2D body's own rig. Asserted at the seams the
## how-to names: the mirror shows a character by it (and two share their solids), a standing body is
## 58 px tall (the how-to's number, copied here) and half that at half the scale, it faces where the
## 2D body faces, a crouch lowers the hips by `CharacterPostureConfig`'s crouch height, the legs
## stride when the character walks and rest when it stands, the outfit's vest, plates and the
## style's colours reach the parts and a changed outfit re-dresses the body in place, a body seated
## (its shapes disabled) or dead is hidden, and Main's 3D view registers the builder. What the body
## looks like is judged in a window, `character_mesh_windowed_test.gd`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_character_mesh_test.json"
## The how-to's standing character (`meshes.md` heights): px from the floor to the top of the head.
const STANDING_HEIGHT := 58.0
const MATCH := {
	"seed": 2,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}


func describe() -> Dictionary:
	return {
		"name": "A character is shown by a low-poly body that follows its rig",
		"description": "Character's builder gives the mirror a body of kit solids: 58 px tall, "
			+ "facing the character's facing, folded by a crouch, striding with the gait, in the "
			+ "outfit's and the style's colours, hidden when seated or dead.",
		"tags": ["mirror", "3d", "render", "meshkit", "character", "posture"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.actor(&"east", &"puppet", Vector2(150, 100), { "facing": Vector2.RIGHT, "start_slot": 3 })
	s.actor(&"south", &"puppet", Vector2(350, 100), { "facing": Vector2.DOWN })
	s.actor(&"crouch", &"puppet", Vector2(150, 250), { "facing": Vector2.RIGHT })
	s.actor(&"walker", &"puppet", Vector2(150, 400), { "facing": Vector2.RIGHT })
	s.actor(&"dressed", &"puppet", Vector2(350, 250), { "facing": Vector2.RIGHT })
	s.actor(&"dying", &"puppet", Vector2(550, 250), { "max_health": 10.0 })
	s.von_script([])


func run(t: TestContext) -> void:
	t.puppet(&"east").aim_at(Vector2(2000, 100))
	t.puppet(&"south").aim_at(Vector2(350, 2000))
	t.puppet(&"crouch").aim_at(Vector2(2000, 250))
	t.puppet(&"crouch").set_posture(&"crouch")
	t.puppet(&"walker").aim_at(Vector2(2000, 400))
	t.puppet(&"dressed").aim_at(Vector2(2000, 250))
	await t.seconds(1.2)
	var mirror := _mirror(t)
	CharacterMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(3)
	var east := _body_of(t, mirror, &"east")
	var south := _body_of(t, mirror, &"south")
	var crouch := _body_of(t, mirror, &"crouch")
	if east == null or south == null or crouch == null:
		return
	_check_shape(t, east, south)
	_check_facing(t, east, south)
	_check_crouch(t, east, crouch)
	await _check_gait(t, mirror)
	await _check_dress(t, mirror)
	await _check_hidden(t, mirror, east)
	await _check_scale(t)
	await _check_main(t)


## The body the mirror shows the actor `id` by (a `BodyMesh`), or null: it ends the test.
func _body_of(t: TestContext, mirror: WorldMirror, id: StringName) -> BodyMesh:
	var shown := mirror.proxies_of(t.actor(id))
	if not t.require(
		shown.size() == 1 and shown[0] is BodyMesh,
		"%s is shown by a body of its own, not a capsule" % id,
	):
		return null
	return shown[0] as BodyMesh


## A standing body is as tall as the how-to says, on the floor, as wide as the character; two bodies
## share their solids.
func _check_shape(t: TestContext, east: BodyMesh, south: BodyMesh) -> void:
	var box := _bounds(east)
	t.expect_near(box.end.y, STANDING_HEIGHT, 2.5, "the head tops a standing body at 58 px")
	# The box is of each part's own box turned with it, so a tilted shin overshoots a little.
	t.expect_near(box.position.y, 0.0, 1.5, "it stands on the floor")
	t.check(
		box.size.x > 14.0 and box.size.x < 60.0,
		"it is about the body's width across (%.1f px)" % box.size.x,
	)
	t.check(
		east.get_child(BodyMesh.HEAD).mesh == south.get_child(BodyMesh.HEAD).mesh,
		"two bodies share one head solid",
	)
	t.check(
		(east.get_child(BodyMesh.HEAD) as MeshInstance3D).material_override
			== ToonMaterial.shared(),
		"it is drawn in the one shared toon material",
	)


## The body faces the character's facing: the nose stands out of the head toward it, and the
## character's hands are ahead of its shoulders along it.
func _check_facing(t: TestContext, east: BodyMesh, south: BodyMesh) -> void:
	var toward_east := _nose_direction(east)
	t.check(
		toward_east.dot(Vector2.RIGHT) > 0.9,
		"a character facing east has its nose east (%s)" % toward_east,
	)
	var toward_south := _nose_direction(south)
	t.check(
		toward_south.dot(Vector2.DOWN) > 0.9,
		"a character facing south has its nose south, 3D z (%s)" % toward_south,
	)
	var hand := _flat(east.get_child(BodyMesh.HAND) as Node3D)
	var chest := _flat(east.get_child(BodyMesh.TORSO) as Node3D)
	t.check(
		(hand - chest).dot(Vector2.RIGHT) > 4.0,
		"the arms reach out ahead of the trunk (%s)" % (hand - chest),
	)


## A crouch lowers the hips by the posture's crouch height and the head with them.
func _check_crouch(t: TestContext, east: BodyMesh, crouch: BodyMesh) -> void:
	var want: float = CharacterPostureConfig.postures[&"crouch"]["height"]
	var stood := (east.get_child(BodyMesh.THIGH) as Node3D).position.y
	var bent := (crouch.get_child(BodyMesh.THIGH) as Node3D).position.y
	t.expect_near(bent / stood, want, 0.03, "a crouch lowers the hips to its posture height")
	t.check(
		_bounds(crouch).end.y < _bounds(east).end.y * 0.9,
		"and the head with them (%.1f of %.1f px)" % [_bounds(crouch).end.y, _bounds(east).end.y],
	)
	var head := _flat(crouch.get_child(BodyMesh.HEAD) as Node3D)
	var pelvis := _flat(crouch.get_child(BodyMesh.TORSO) as Node3D)
	t.check(
		(head - pelvis).dot(Vector2.RIGHT) > 2.0,
		"a crouched body leans toward where it faces (%s)" % (head - pelvis),
	)


## The legs stride when the character walks and are still when it stands.
func _check_gait(t: TestContext, mirror: WorldMirror) -> void:
	var walker := _body_of(t, mirror, &"walker")
	var east := _body_of(t, mirror, &"east")
	if walker == null or east == null:
		return
	var rest := await _sample_feet(t, east)
	t.check(rest < 0.5, "a standing character's feet do not move (%.2f px)" % rest)
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.seconds(0.4)
	var stride := await _sample_feet(t, walker)
	t.check(stride > 4.0, "a walking character's feet stride fore and aft (%.1f px)" % stride)
	t.puppet(&"walker").stop()


## How far the first foot of `body` moves along the character's x over half a second of frames.
func _sample_feet(t: TestContext, body: BodyMesh) -> float:
	var low := INF
	var high := -INF
	var origin := (body.get_parent() as Node3D)
	for i in 30:
		await t.frames(1)
		var foot := body.get_child(BodyMesh.FOOT) as Node3D
		var x := foot.global_position.x - origin.global_position.x
		low = minf(low, x)
		high = maxf(high, x)
	return high - low


## The style's colours reach the parts, an outfit's vest and plates show (and are not there
## undressed), and a changed outfit re-dresses the same body in place.
func _check_dress(t: TestContext, mirror: WorldMirror) -> void:
	var body := _body_of(t, mirror, &"dressed")
	if body == null:
		return
	var dress: BodyDress = t.actor(&"dressed").get_node("Visuals").dress
	_check_colours(t, body, dress)
	await _check_outfit(t, mirror, body, dress)


## The parts are the colours the painters draw them in (`dress`).
func _check_colours(t: TestContext, body: BodyMesh, dress: BodyDress) -> void:
	t.check(
		_tint(body, BodyMesh.TORSO) == dress.shirt,
		"the trunk is the shirt's colour the painters draw (%s)" % dress.shirt,
	)
	t.check(_tint(body, BodyMesh.HEAD) == dress.skin, "the head is the skin's")
	t.check(
		_tint(body, BodyMesh.THIGH) == dress.pants,
		"the thigh is the trousers' colour",
	)
	t.check(_tint(body, BodyMesh.FOOT) == dress.shoes, "the shoe is the shoes' colour")
	t.check(
		(body.get_child(BodyMesh.HAND) as MeshInstance3D).visible
			and _tint(body, BodyMesh.HAND) == dress.hand_parts[0]["color"],
		"the fist is the glove's colour",
	)


## An outfit with no vest has none on the body, a plate carrier and its plate appear in their
## colours, on the same body.
func _check_outfit(
	t: TestContext,
	mirror: WorldMirror,
	body: BodyMesh,
	dress: BodyDress,
) -> void:
	var wardrobe: CharacterWardrobe = t.actor(&"dressed").wardrobe
	wardrobe.outfit.set_ids({})
	await t.frames(4)
	t.check(not _shown(body, BodyMesh.VEST), "with no vest worn there is none on the body")
	t.check(
		not _shown(body, BodyMesh.PLATE) and not _shown(body, BodyMesh.PLATE + 1),
		"and no plates",
	)
	var before := _tint(body, BodyMesh.TORSO)
	wardrobe.outfit.set_ids({
		"vest": &"plate_carrier", "front_plate": &"ceramic_iv", "body": &"shirt",
	})
	await t.frames(6)
	t.check(_shown(body, BodyMesh.VEST), "a worn plate carrier is on the body")
	t.check(
		_shown(body, BodyMesh.PLATE) and _shown(body, BodyMesh.PLATE + 1) == false,
		"with its front plate (and no back plate)",
	)
	var look := PixelArt.look_of(dress.head_opts)
	t.check(
		_tint(body, BodyMesh.VEST) == look["vest_col"],
		"the vest is the colour its look gives (%s)" % look["vest_col"],
	)
	t.check(
		_tint(body, BodyMesh.PLATE) == dress.shoulder_opts["front_plate"],
		"the plate is the plate's colour",
	)
	t.check(
		_tint(body, BodyMesh.TORSO) == dress.shirt,
		"the same body is dressed again, the trunk in the new shirt (%s)" % before,
	)
	t.check(
		mirror.proxies_of(t.actor(&"dressed"))[0] == body,
		"in place: the body was not rebuilt",
	)


## A body seated (its collision shapes disabled) is hidden and back when they are enabled; a dead
## one goes with its death.
func _check_hidden(t: TestContext, mirror: WorldMirror, east: BodyMesh) -> void:
	var shape := _shape_of(t.actor(&"east"))
	shape.set_deferred(&"disabled", true)
	await t.frames(3)
	t.check(not east.visible, "a character whose shapes are disabled (seated) has no body shown")
	shape.set_deferred(&"disabled", false)
	await t.frames(3)
	t.check(east.visible, "and it is back when they are enabled")
	var dying := _body_of(t, mirror, &"dying")
	if dying == null:
		return
	t.check(dying.visible, "premise: the living body shows")
	t.actor(&"dying").take_damage(1000.0)
	await t.frames(4)
	t.check(not dying.visible, "a dead character's body is hidden (the ragdoll is its own mirror)")


## At half the scale every length of the body halves: the unit conversion is the kit's.
func _check_scale(t: TestContext) -> void:
	RenderConfig.unit = 0.5
	var mirror := _mirror(t)
	CharacterMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(3)
	var body := _body_of(t, mirror, &"east")
	if body != null:
		t.expect_near(
			_bounds(body, 1.0).end.y,
			STANDING_HEIGHT * 0.5,
			1.5,
			"at half scale the body is half as tall",
		)
	RenderConfig.unit = 1.0


## Main's 3D view registers the character's builder: a match started in 3D shows its characters by
## the body.
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
		t.check(
			view.mirror.builders.has(MirrorProxy.CHARACTER),
			"Main's view registers the character's builder",
		)
		var character: Node = built["world"].find_children("*", "CharacterBody2D", true, false)[0]
		var shown: Array = view.mirror.proxies_of(character)
		t.check(
			shown.size() == 1 and shown[0] is BodyMesh,
			"a match's character is shown by the body",
		)
	await MainProbe.close(t, window)


## The box (px at the scale `unit`, in the body's frame) of every part of `body` that shows.
func _bounds(body: BodyMesh, unit := RenderConfig.unit) -> AABB:
	var box := AABB()
	var first := true
	for part: Node in body.get_children():
		var node := part as MeshInstance3D
		if node == null or not node.visible:
			continue
		var inside := body.global_transform.affine_inverse() * node.global_transform
		var scale := 1.0 / unit
		var local := (inside * node.mesh.get_aabb())
		local = AABB(local.position * scale, local.size * scale)
		box = local if first else box.merge(local)
		first = false
	return box


## Where the nose stands out of the head, as a flat direction (3D x, z).
func _nose_direction(body: BodyMesh) -> Vector2:
	var head := body.get_child(BodyMesh.HEAD) as Node3D
	var nose := body.get_child(BodyMesh.NOSE) as Node3D
	return (_flat(nose) - _flat(head)).normalized()


## `node`'s place on the ground (3D x, z), in the body's frame.
func _flat(node: Node3D) -> Vector2:
	return Vector2(node.position.x, node.position.z) / RenderConfig.unit


## The colour part `index` of `body` is tinted.
func _tint(body: BodyMesh, index: int) -> Color:
	var part := body.get_child(index) as MeshInstance3D
	return part.get_instance_shader_parameter(&"base_color")


## Whether part `index` of `body` shows.
func _shown(body: BodyMesh, index: int) -> bool:
	return (body.get_child(index) as Node3D).visible


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
