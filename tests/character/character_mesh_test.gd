extends GameTest
## A character is shown by its own low-poly body, not the proxy capsule (#193 phase 2, Character,
## `domain-art/meshes.md`): Character's builder (`CharacterMeshes.register`, the `CHARACTER` hook
## key) gives the mirror a `BodyMesh` that follows the 2D body's own rig. Asserted at the seams the
## how-to names: the mirror shows a character by it (and two share their solids), a standing body is
## 74 px tall (the how-to's number, copied here) and half that at half the scale, it faces where the
## 2D body faces, a crouch lowers the hips by `CharacterPostureConfig`'s crouch height, the legs
## stride when the character walks and rest when it stands, the outfit's vest, plates and the
## style's colours reach the parts and a changed outfit re-dresses the body in place, a body seated
## (its riding) is hidden, a dead one stays shown (`character_ragdoll_mesh_test.gd`), and
## Main's 3D view registers the builder. What the body looks like is judged in a window,
## `character_mesh_windowed_test.gd`.

const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const MainProbe := preload("res://tests/_main/main_probe.gd")
const Style := preload("res://scenes/character/body/character_style.gd")
const BodyPainter := preload("res://scenes/character/body/art/body_painter.gd")
const HandPainter := preload("res://scenes/character/body/art/hand_painter.gd")
const SCRATCH := "user://settings_character_mesh_test.json"
## The how-to's standing character (`meshes.md` heights): px from the floor to the top of the head.
const STANDING_HEIGHT := 74.0
const MATCH := {
	"seed": 2,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}


func describe() -> Dictionary:
	return {
		"name": "A character is shown by a low-poly body that follows its rig",
		"description": "Character's builder gives the mirror a body of kit solids: 74 px tall, "
			+ "facing the character's facing, folded by a crouch, striding with the gait, in the "
			+ "outfit's and the style's colours, hidden when seated, lying when dead.",
		"tags": ["mirror", "3d", "render", "meshkit", "character", "posture"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 900, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.actor(&"east", &"puppet", Vector2(150, 100), { "facing": Vector2.RIGHT, "start_slot": 3 })
	s.actor(&"south", &"puppet", Vector2(350, 100), { "facing": Vector2.DOWN })
	s.actor(&"crouch", &"puppet", Vector2(150, 250), { "facing": Vector2.RIGHT })
	s.actor(&"walker", &"puppet", Vector2(150, 400), { "facing": Vector2.RIGHT })
	s.actor(&"dressed", &"puppet", Vector2(350, 250), { "facing": Vector2.RIGHT })
	s.actor(&"dying", &"puppet", Vector2(550, 250), { "max_health": 10.0 })
	s.actor(&"culled", &"puppet", Vector2(550, 100), { "facing": Vector2.RIGHT })
	s.actor(&"looks", &"puppet", Vector2(750, 250), { "facing": Vector2.RIGHT })
	s.von_script([])


func run(t: TestContext) -> void:
	t.puppet(&"east").aim_at(Vector2(2000, 100))
	t.puppet(&"south").aim_at(Vector2(350, 2000))
	t.puppet(&"crouch").aim_at(Vector2(2000, 250))
	t.puppet(&"crouch").set_posture(&"crouch")
	t.puppet(&"walker").aim_at(Vector2(2000, 400))
	t.puppet(&"dressed").aim_at(Vector2(2000, 250))
	t.puppet(&"culled").aim_at(Vector2(2000, 100))
	t.puppet(&"looks").aim_at(Vector2(2000, 250))
	await t.seconds(1.2)
	var mirror := _mirror(t)
	CharacterMeshes.register(mirror.builders)
	mirror.carry(t.world)
	await t.frames(3)
	var east := _body_of(t, mirror, &"east")
	var south := _body_of(t, mirror, &"south")
	var crouch := _body_of(t, mirror, &"crouch")
	if east == null or south == null or crouch == null:
		return
	_check_shape(t, east, south)
	_check_facing(t, east, south)
	_check_crouch(t, east, crouch)
	_check_figure(t, east)
	_check_proportions(t, east, south)
	await _check_gait(t, mirror)
	await _check_dress(t, mirror)
	await _check_idle(t, mirror)
	await _check_hidden_parts(t, mirror)
	await _check_looks(t, mirror)
	await _check_culled(t, mirror)
	await _check_hidden(t, mirror, east)
	await _check_scale(t)
	await _check_main(t)


## The body the mirror shows the actor `id` by (a `BodyMesh`), or null: it ends the test.
func _body_of(t: TestContext, mirror: MeshCarrier, id: StringName) -> BodyMesh:
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
	t.expect_near(box.end.y, STANDING_HEIGHT, 2.5, "the head tops a standing body at 74 px")
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
		(east.get_child(BodyMesh.NECK) as MeshInstance3D).material_override
			== ToonMaterial.shared(),
		"a part with no art of its own (the neck) is drawn in the one shared toon material",
	)
	for index in [BodyMesh.HEAD, BodyMesh.TORSO, BodyMesh.UPPER, BodyMesh.THIGH, BodyMesh.FOOT]:
		t.check(
			_art(east, index) != null,
			"the part %d is drawn in the textured toon, with its 2D art" % index,
		)


## A natural body, not a blocky one: three quarters of a wall tall, a trunk narrower than the
## collider, a neck between the trunk and the head, limbs that taper (a different shape for each
## segment, not one box or cylinder), a head near the drawing's own size and an upright head over
## the shoulders.
func _check_proportions(t: TestContext, east: BodyMesh, south: BodyMesh) -> void:
	t.expect_near(
		_bounds(east).end.y,
		ObjectStructureMeshConfig.wall_height * 0.75,
		4.0,
		"a standing body is about three quarters of a wall tall",
	)
	var trunk := east.get_child(BodyMesh.TORSO) as Node3D
	t.check(
		trunk.transform.basis.get_scale().x < t.actor(&"east").radius,
		"the trunk is narrower than the 28 px collider (half width under the body's radius)",
	)
	var neck := east.get_child(BodyMesh.NECK) as MeshInstance3D
	var head := east.get_child(BodyMesh.HEAD) as Node3D
	t.check(
		neck.visible and neck.position.y < head.position.y and neck.position.y > 0.0,
		"a neck runs from the shoulders up to the head",
	)
	var shapes := {}
	for index in [BodyMesh.UPPER, BodyMesh.FORE, BodyMesh.THIGH, BodyMesh.SHIN, BodyMesh.NECK]:
		shapes[(east.get_child(index) as MeshInstance3D).mesh] = true
	t.expect_eq(
		shapes.size(),
		5,
		"the arm's, the leg's and the neck's segments are shaped each their own",
	)
	t.check(
		(south.get_child(BodyMesh.THIGH) as MeshInstance3D).mesh
			== (east.get_child(BodyMesh.THIGH) as MeshInstance3D).mesh,
		"two bodies share one thigh solid",
	)
	var drawn: float = 2.0 * CharacterArtConfig.head_size * t.actor(&"east").radius
	t.check(
		head.transform.basis.get_scale().x < drawn * 1.2,
		"the head is the drawing's own size, not an inflated one",
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


## A crouch lowers the hips to the duck's height (`BodyHeights`) and the head with them.
func _check_crouch(t: TestContext, east: BodyMesh, crouch: BodyMesh) -> void:
	var want := BodyHeights.height_share(BodyHeights.DUCK)
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
func _check_gait(t: TestContext, mirror: MeshCarrier) -> void:
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
func _check_dress(t: TestContext, mirror: MeshCarrier) -> void:
	var body := _body_of(t, mirror, &"dressed")
	if body == null:
		return
	var dress: BodyDress = body.look_worn()
	_check_colours(t, body, dress)
	var made := ToonMaterial.textured_count()
	await t.frames(30)
	t.expect_eq(
		ToonMaterial.textured_count(),
		made,
		"the art is made once per look: no textured material is made as the bodies move",
	)
	await _check_outfit(t, mirror, body, dress)


## Every part is a figure for the pixel post (outlined by its silhouette only, no crease on its
## facets: the outline job), vest, pack and head-wear included; a wall's mesh is not.
func _check_figure(t: TestContext, body: BodyMesh) -> void:
	var unmarked := 0
	for part: Node in body.get_children():
		if part.name == &"DropShadow":
			continue  # the patch on the floor is not a part of the figure
		if (part as MeshInstance3D).get_instance_shader_parameter(&"figure") != 1.0:
			unmarked += 1
	t.expect_eq(
		unmarked,
		0,
		"every part of the body is marked a figure (the post draws no creases)",
	)


## The parts are the art the painters draw them in (`dress`): the flat render of the painter, as
## `PixelArt` caches it, tinted white so it shows as painted; the neck stays the skin's colour.
func _check_colours(t: TestContext, body: BodyMesh, dress: BodyDress) -> void:
	var actor: Node = t.actor(&"dressed")
	var r: float = actor.radius
	t.check(
		_art(body, BodyMesh.TORSO)
			== PixelArt.render_flat(
				BodyPainter,
				Vector2(r * 2.0, r * 2.0),
				dress.shirt,
				dress.shoulder_opts,
			),
		"the trunk wears the shoulders' flat art in the shirt's colour (%s)" % dress.shirt,
	)
	t.check(_art(body, BodyMesh.VEST) == _art(body, BodyMesh.TORSO), "the vest wears it too")
	t.check(_tint(body, BodyMesh.TORSO) == Color.WHITE, "the art is not tinted again")
	t.check(_tint(body, BodyMesh.NECK) == dress.skin, "the neck is the skin's")
	var hand: Dictionary = dress.hand_parts[0]
	var diameter: float = 2.0 * actor.get_node("Hands").hand_radius + 2.0
	t.check(
		_art(body, BodyMesh.HAND)
			== PixelArt.render_flat(
				HandPainter,
				Vector2(diameter, diameter),
				hand["color"],
				hand["opts"],
			),
		"the fist wears the hand's flat art in the glove's colour",
	)
	t.check(
		_art(body, BodyMesh.HEAD) == _art(body, BodyMesh.HAIR)
			and _art(body, BodyMesh.HEAD) == _art(body, BodyMesh.HEADWEAR),
		"the head's art is on the head and on what covers it",
	)


## An outfit with no vest has none on the body, a plate carrier and its plate appear in their
## colours, on the same body.
func _check_outfit(
	t: TestContext,
	mirror: MeshCarrier,
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
	var before := _art(body, BodyMesh.TORSO)
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
		_art(body, BodyMesh.VEST) != null and _art(body, BodyMesh.VEST) != before,
		"the vest wears the shoulders' art with the vest on it (%s)" % look["vest_col"],
	)
	t.check(
		_tint(body, BodyMesh.PLATE) == dress.shoulder_opts["front_plate"],
		"the plate is the plate's colour",
	)
	t.check(
		_art(body, BodyMesh.TORSO) != before,
		"the same body is dressed again: the trunk wears the art of the new look",
	)
	t.check(
		mirror.proxies_of(t.actor(&"dressed"))[0] == body,
		"in place: the body was not rebuilt",
	)


## A body standing still, breathing as the game has it, is posed again on few frames: a mark put on
## a
## part is overwritten only when the head's breath has drifted past `BodyMesh.MOVED`, so over a
## full breath period (3.8 s) fewer than one frame in ten writes.
func _check_idle(t: TestContext, mirror: MeshCarrier) -> void:
	var body := _body_of(t, mirror, &"east")
	if body == null:
		return
	var trunk := body.get_child(BodyMesh.TORSO) as Node3D
	var mark := Transform3D(Basis(), Vector3(999.0, 0.0, 0.0))
	var frames := ceili(CharacterPoseHeadConfig.breath_period * 60.0) + 30
	var writes := 0
	for i in frames:
		trunk.transform = mark
		await t.frames(1)
		if trunk.transform != mark:
			writes += 1
	t.check(
		writes * 10 < frames,
		"a standing, breathing body is posed on %d of %d frames (under one in ten)" % [
			writes,
			frames,
		],
	)


## A part that is not shown is not placed, and is placed when a look shows it: a walker's hidden
## vest keeps its mark while its fists move, and the vest is on the trunk once an outfit shows it.
func _check_hidden_parts(t: TestContext, mirror: MeshCarrier) -> void:
	var body := _body_of(t, mirror, &"walker")
	if body == null:
		return
	var wardrobe: CharacterWardrobe = t.actor(&"walker").wardrobe
	wardrobe.outfit.set_ids({})
	await t.frames(3)
	var vest := body.get_child(BodyMesh.VEST) as Node3D
	var hand := body.get_child(BodyMesh.HAND) as Node3D
	var mark := Transform3D(Basis(), Vector3(999.0, 0.0, 0.0))
	vest.transform = mark
	var hand_before := hand.transform
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.seconds(0.5)
	t.check(hand.transform != hand_before, "premise: the walker's parts move")
	t.check(not vest.visible and vest.transform == mark, "a hidden vest is not placed")
	t.puppet(&"walker").stop()
	wardrobe.outfit.set_ids({ "vest": &"tactical_vest", "body": &"shirt" })
	await t.frames(4)
	t.check(vest.visible and vest.transform != mark, "a look that shows the vest places it")


## A look change swaps a cap for a helmet (a bigger covering), hides the hair under headwear, shows
## and hides a boot's shaft and a pack, on the same body.
func _check_looks(t: TestContext, mirror: MeshCarrier) -> void:
	var body := _body_of(t, mirror, &"looks")
	if body == null:
		return
	var wardrobe: CharacterWardrobe = t.actor(&"looks").wardrobe
	var base := { "body": &"shirt", "pants": &"jeans" }
	var wear := func(extra: Dictionary) -> void:
		wardrobe.outfit.set_ids(base.merged(extra))
	wardrobe.set_style(&"merc", _seed_with(&"hair_style", "short"))
	wear.call({ "feet": &"shoes" })
	await t.frames(4)
	var headwear := body.get_child(BodyMesh.HEADWEAR) as Node3D
	var hair := body.get_child(BodyMesh.HAIR) as Node3D
	t.check(hair.visible and not headwear.visible, "a bare head shows its hair")
	t.check(not _shown(body, BodyMesh.BOOT), "shoes have no boot shaft")
	wear.call({ "head": &"hat", "feet": &"boots" })
	await t.frames(4)
	t.check(headwear.visible and not hair.visible, "a cap hides the hair under it")
	t.check(_shown(body, BodyMesh.BOOT) and _shown(body, BodyMesh.BOOT + 1), "boots show a shaft")
	var cap := headwear.transform.basis.get_scale().x
	wear.call({ "head": &"helmet", "feet": &"boots" })
	await t.frames(4)
	var helmet := headwear.transform.basis.get_scale().x
	t.check(
		helmet > cap * 1.05,
		"a helmet covers more of the head than a cap (%.2f > %.2f)" % [helmet, cap],
	)
	t.check(_tint(body, BodyMesh.HEADWEAR) != Color.GRAY, "and is in its own colour")
	wear.call({ "feet": &"shoes" })
	await t.frames(4)
	t.check(hair.visible and not headwear.visible, "the hair is back with the headwear gone")
	t.check(not _shown(body, BodyMesh.BOOT), "and the boot shaft with the shoes")
	wardrobe.set_style(&"merc", _seed_with(&"pack", true))
	await t.frames(4)
	t.check(_shown(body, BodyMesh.PACK), "a look with a pack shows it on the back")
	wardrobe.set_style(&"merc", _seed_with(&"pack", false))
	await t.frames(4)
	t.check(not _shown(body, BodyMesh.PACK), "and one without hides it")


## The first look seed of the `merc` style whose resolved look has `key` equal to `value`.
func _seed_with(key: StringName, value: Variant) -> int:
	for seed_value in 200:
		var look: Dictionary = Style.resolve(&"merc", seed_value, 0, {})
		if look[key] == value:
			return seed_value
	return 0


## A body far from the player: an outfit change still reaches the mesh (the mesh refreshes its own
## dress).
func _check_culled(t: TestContext, mirror: MeshCarrier) -> void:
	var body := _body_of(t, mirror, &"culled")
	if body == null:
		return
	var actor := t.actor(&"culled")
	actor.wardrobe.outfit.set_ids({})
	await t.frames(3)
	t.check(not _shown(body, BodyMesh.VEST), "premise: no vest on the unseen body")
	actor.wardrobe.outfit.set_ids({ "vest": &"tactical_vest", "body": &"shirt" })
	await t.frames(4)
	t.check(_shown(body, BodyMesh.VEST), "an outfit change re-dresses a body away from the player")


## A body seated (its collision riding) is hidden and back when they are enabled; a dead
## one stays shown.
func _check_hidden(t: TestContext, mirror: MeshCarrier, east: BodyMesh) -> void:
	var rider: Node2D = t.actor(&"east")
	rider.use.set_ride_pose(rider.global_position, Vector2.RIGHT, 0.0)
	await t.frames(3)
	t.check(not east.visible, "a character riding a vehicle has no body shown")
	rider.use.end_ride()
	await t.frames(3)
	t.check(east.visible, "and it is back when the ride is over")
	var dying := _body_of(t, mirror, &"dying")
	if dying == null:
		return
	t.check(dying.visible, "premise: the living body shows")
	t.actor(&"dying").take_damage(1000.0)
	await t.frames(4)
	t.check(dying.visible, "a dead character's body stays shown, lying where the ragdoll lays it")


## At half the scale every length of the body halves: the unit conversion is the kit's.
func _check_scale(t: TestContext) -> void:
	RenderConfig.unit = 0.5
	var mirror := _mirror(t)
	CharacterMeshes.register(mirror.builders)
	mirror.carry(t.world)
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
			view.carrier.builders.has(MeshKinds.CHARACTER),
			"Main's view registers the character's builder",
		)
		var character: Node = PlanProbe.characters_under(built["world"])[0]
		var shown: Array = view.carrier.proxies_of(character)
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
	var nose := body.get_child(BodyMesh.FACE) as Node3D
	return (_flat(nose) - _flat(head)).normalized()


## `node`'s place on the ground (3D x, z), in the body's frame.
func _flat(node: Node3D) -> Vector2:
	return Vector2(node.position.x, node.position.z) / RenderConfig.unit


## The colour part `index` of `body` is tinted.
func _tint(body: BodyMesh, index: int) -> Color:
	var part := body.get_child(index) as MeshInstance3D
	return part.get_instance_shader_parameter(&"base_color")


## The texture part `index` of `body` wears (null for the shared toon material).
func _art(body: BodyMesh, index: int) -> Texture2D:
	var material := (body.get_child(index) as MeshInstance3D).material_override
	if material is ShaderMaterial:
		return (material as ShaderMaterial).get_shader_parameter(&"albedo_texture")
	return null


## Whether part `index` of `body` shows.
func _shown(body: BodyMesh, index: int) -> bool:
	return (body.get_child(index) as Node3D).visible


func _mirror(t: TestContext) -> MeshCarrier:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	view.add_child(mirror)
	return mirror
