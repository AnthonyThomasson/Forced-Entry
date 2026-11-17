extends GameTest
## Where the 2D art lands on the 3D body (#193 phase 2b, Character, `body-textures.md`): the
## textured toon reads a part's art at `((x, z) - uv_rect.xy) / uv_rect.zw` of the model point, so a
## test can ask what a model point of a part reads and where in the body it stands, without a
## window:
## - the shoulders' art is the right way round: its -x end (side 0's sleeve end) stands nearest side
##   0's shoulder, the body facing each of the four ways;
## - a limb's strip starts at the joint nearer the body: the row behind its first end cap is at its
##   `from` joint and the row where its segment ends is at the next joint;
## - a fist's art front points where the hand points;
## - a dome (the head, a fist) is centred on its art's disc (the painters put it on the pixel
##   `int(w / 2)`, half an art pixel past the canvas's centre) and ends on opaque art at its poles;
## - a part with clear texels shows its own colour there (its vertex colour), not white;
## - the head's art lies flat over the crown as a cut-out sprite above every dome, and the face's
##   band is under it;
## - an arm's strip is its own side's: a sleeve recoloured on one side shows on that side only.
## A mirrored map, a moved strip start, a turned fist or swapped arms each fail one of them.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Rig := preload("res://scenes/character/body/character_rig.gd")
const LimbPainter := preload("res://scenes/character/body/art/limb_painter.gd")
const SETTINGS := "user://settings_character_body_map_test.json"
## The four facings, each a puppet.
const FACINGS := {
	&"east": Vector2.RIGHT,
	&"south": Vector2.DOWN,
	&"west": Vector2.LEFT,
	&"north": Vector2.UP,
}
## How far (px) a mapped point may be from the joint it should be at.
const NEAR := 1.6


func describe() -> Dictionary:
	return {
		"name": "The 2D art lands the right way round on the 3D body",
		"description": "A model point of a part reads the art it should and stands where it "
			+ "should: side 0's sleeve end by side 0's shoulder at four facings, a strip's "
			+ "start at its joint, a fist's front where the hand points, a dome ending on art, "
			+ "clear texels in the part's own colour, the head's sprite over the crown.",
		"tags": ["mirror", "3d", "render", "character", "texture"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SETTINGS)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	var at := 100.0
	for id: StringName in FACINGS:
		s.actor(id, &"puppet", Vector2(at, 150), { "facing": FACINGS[id] })
		at += 200.0
	s.von_script([])


func run(t: TestContext) -> void:
	for id: StringName in FACINGS:
		var actor: Node2D = t.actor(id)
		t.puppet(id).aim_at(actor.global_position + FACINGS[id] * 2000.0)
	await t.seconds(1.2)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	CharacterMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(3)
	var bodies := {}
	for id: StringName in FACINGS:
		var shown := mirror.proxies_of(t.actor(id))
		if not t.require(shown.size() == 1 and shown[0] is BodyMesh, "%s has a body" % id):
			return
		bodies[id] = shown[0]
	for id: StringName in FACINGS:
		var body: BodyMesh = bodies[id]
		_check_shoulders(t, body, String(id))
		_check_strips(t, body, String(id))
		_check_fists(t, body, String(id))
	var east: BodyMesh = bodies[&"east"]
	var dress: BodyDress = east.look_worn()
	_check_domes(t, east)
	_check_colours(t, east, dress)
	_check_crown(t, east)
	_check_sides(t, east, dress)


## The shoulders' art -x end (u 0.1, the middle of it) is nearer side 0's shoulder than side 1's.
func _check_shoulders(t: TestContext, body: BodyMesh, facing: String) -> void:
	var last: PackedVector3Array = body.get("_last")
	for index in [BodyMesh.TORSO, BodyMesh.VEST]:
		var node := body.get_child(index) as MeshInstance3D
		if not node.visible:
			continue  # a part not shown is not placed
		var end := _local(node, Vector2(0.1, 0.5), 0.5)
		var s0: Vector3 = last[Rig.SHOULDER[0]] * RenderConfig.unit
		var s1: Vector3 = last[Rig.SHOULDER[1]] * RenderConfig.unit
		t.check(
			_flat(end - s0).length() < _flat(end - s1).length(),
			"facing %s, the art's -x end (side 0's sleeve) is by side 0's shoulder (part %d)"
				% [facing, index],
		)


## Each arm's and leg's strip: the row behind the first end cap is at the segment's `from` joint
## and the row where the segment ends is at its `to` joint.
func _check_strips(t: TestContext, body: BodyMesh, facing: String) -> void:
	var last: PackedVector3Array = body.get("_last")
	var r: float = body.get("_r")
	var cap: float = CharacterArtConfig.body_arm_widths[0] * r * 0.5
	var length: float = CharacterBodyConfig.upper_arm * r
	for i in 2:
		var upper := body.get_child(BodyMesh.UPPER + i) as MeshInstance3D
		var from: Vector3 = last[Rig.SHOULDER[i]] * RenderConfig.unit
		var to: Vector3 = last[Rig.ELBOW[i]] * RenderConfig.unit
		var height := float(_texture(upper).get_height())
		var row0 := _local(upper, Vector2(0.5, cap / height), 0.0)
		var row1 := _local(upper, Vector2(0.5, (cap + length) / height), 0.0)
		t.check(
			(row0 - from).length() < NEAR,
			"facing %s, side %d's upper arm strip starts at its shoulder (%.1f px off)"
				% [facing, i, (row0 - from).length()],
		)
		t.check(
			(row1 - to).length() < NEAR,
			"facing %s, side %d's upper arm strip ends at its elbow (%.1f px off)"
				% [facing, i, (row1 - to).length()],
		)


## A fist's art front (the middle of its lower half, the art's front being +y) is on the side of the
## hand its fist points to, and the art's +x is where it is in the art when the front points down
## the picture (to the left of the way the fist points).
func _check_fists(t: TestContext, body: BodyMesh, facing: String) -> void:
	var last: PackedVector3Array = body.get("_last")
	for i in 2:
		var hand := body.get_child(BodyMesh.HAND + i) as MeshInstance3D
		var centre := _local(hand, Vector2(0.5, 0.5), 0.0)
		var front := _flat(_local(hand, Vector2(0.5, 0.9), 0.0) - centre)
		var right := _flat(_local(hand, Vector2(0.9, 0.5), 0.0) - centre)
		var points := Vector2(last[BodyMesh.FISTS + i].x, last[BodyMesh.FISTS + i].z)
		t.check(
			front.normalized().dot(points.normalized()) > 0.95,
			"facing %s, fist %d's art front points along the fist (%.2f)"
				% [facing, i, front.normalized().dot(points.normalized())],
		)
		t.check(
			points.normalized().cross(right.normalized()) < -0.9,
			"and its art's +x is where the art has it (not mirrored)",
		)


## A dome is centred on its art's disc and its poles (the four ends of its equator across and along
## the art) are opaque art.
func _check_domes(t: TestContext, body: BodyMesh) -> void:
	var domes := [BodyMesh.HEAD, BodyMesh.HAIR, BodyMesh.HEADWEAR, BodyMesh.HAND, BodyMesh.HAND + 1]
	for index: int in domes:
		var node := body.get_child(index) as MeshInstance3D
		var image := _texture(node).get_image()
		var size := Vector2(image.get_size())
		var centre := _uv(node, Vector2.ZERO) * size
		var disc := Vector2(int(size.x / 2.0) + 0.5, int(size.y / 2.0) + 0.5)
		t.check(
			centre.distance_to(disc) < 0.05,
			"part %d is centred on its art's disc (texel %s, the disc's %s)" % [
				index,
				centre,
				disc,
			],
		)
		var clear := 0
		for pole in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			var texel := Vector2i(_uv(node, pole * 0.97) * size)
			if image.get_pixelv(texel).a < 0.5:
				clear += 1
		t.expect_eq(clear, 0, "part %d's poles are on opaque art" % index)


## Where the art is clear a part shows its vertex colour, which is the part's own colour (the mesh
## keeps it linear in 8 bits, so it is compared to within a few of them).
func _check_colours(t: TestContext, body: BodyMesh, dress: BodyDress) -> void:
	var look := PixelArt.look_of(dress.head_opts)
	var expected := {
		BodyMesh.TORSO: dress.shirt,
		BodyMesh.HEAD: dress.skin,
		BodyMesh.PACK: look.get("pack_col", Color.GRAY),
		BodyMesh.HAIR: look.get("hair", Color.GRAY),
		BodyMesh.THIGH: dress.pants,
		BodyMesh.FOOT: dress.shoes,
		BodyMesh.HAND: dress.hand_parts[0]["color"],
		BodyMesh.UPPER: dress.arm_parts[0]["upper"]["color"],
	}
	for index: int in expected:
		var colours: PackedColorArray = (
			((body.get_child(index) as MeshInstance3D).mesh as ArrayMesh)
				.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		)
		var want: Color = expected[index]
		var got := Color.WHITE if colours.is_empty() else colours[0]
		var linear := want.srgb_to_linear()
		t.check(
			Vector3(got.r - linear.r, got.g - linear.g, got.b - linear.b).length() < 0.012,
			"part %d's vertex colour is its own colour %s, not white (%s)" % [index, want, got],
		)


## The head's sprite: a flat cut-out over the crown, higher than the domes and than the face's band,
## wearing the head's art over the whole canvas.
func _check_crown(t: TestContext, body: BodyMesh) -> void:
	var crown := body.get_child(BodyMesh.CROWN) as MeshInstance3D
	var head := body.get_child(BodyMesh.HEAD) as MeshInstance3D
	var material := crown.material_override as ShaderMaterial
	t.check(
		material != null and material.get_shader_parameter(&"cutout") == true,
		"the head's sprite is a cut-out: its clear texels draw nothing",
	)
	t.check(_texture(crown) == _texture(head), "it wears the head's own art")
	t.check(
		crown.transform.basis.y.normalized().dot(Vector3.UP) > 0.99,
		"it lies flat",
	)
	var top := head.position.y + head.transform.basis.get_scale().y * 1.1
	t.check(crown.position.y > top, "it lies over the head's crown (%.1f over %.1f)"
		% [crown.position.y, top])
	var face := body.get_child(BodyMesh.FACE) as MeshInstance3D
	var band := face.position.y + face.transform.basis.get_scale().y
	t.check(crown.position.y > band, "and over the face's band, which it does not hide from above")
	t.check(
		not crown.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"it casts no shadow of its own",
	)


## An arm's strip is its own side's: with side 1's sleeve recoloured, side 1's strip is that colour
## and side 0's is not.
func _check_sides(t: TestContext, body: BodyMesh, dress: BodyDress) -> void:
	var was: Color = dress.arm_parts[1]["upper"]["color"]
	var other := Color(
		0.9,
		0.1,
		0.8,
	) if not was.is_equal_approx(Color(0.9, 0.1, 0.8)) else Color.RED
	dress.arm_parts[1]["upper"]["color"] = other
	var parts: Array[MeshInstance3D] = []
	for index in BodyMesh.CROWN + 1:
		parts.append(body.get_child(index) as MeshInstance3D)
	BodyTextures.apply(parts, dress, body.get("_r"), body.get("_hand_radius"))
	t.check(
		_share(_texture(parts[BodyMesh.UPPER + 1]), other) > 0.2
			and _share(_texture(parts[BodyMesh.UPPER]), other) < 0.01,
		"side 1's upper arm wears side 1's sleeve, side 0's does not",
	)
	dress.arm_parts[1]["upper"]["color"] = was
	BodyTextures.apply(parts, dress, body.get("_r"), body.get("_hand_radius"))


## The share of the opaque texels of `texture` that are `colour` (to within 8 bits).
func _share(texture: Texture2D, colour: Color) -> float:
	var image := texture.get_image()
	var opaque := 0
	var match_count := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.5:
				continue
			opaque += 1
			var off := Vector3(pixel.r - colour.r, pixel.g - colour.g, pixel.b - colour.b)
			if off.length() < 0.03:
				match_count += 1
	return float(match_count) / maxf(opaque, 1.0)


## The texture part `node` wears.
func _texture(node: MeshInstance3D) -> Texture2D:
	return (node.material_override as ShaderMaterial).get_shader_parameter(&"albedo_texture")


## The art coordinate (0..1 across and down) the model point `xz` of `node` reads: the textured
## toon's own rule.
func _uv(node: MeshInstance3D, xz: Vector2) -> Vector2:
	var rect: Vector4 = node.get_instance_shader_parameter(&"uv_rect")
	return Vector2((xz.x - rect.x) / rect.z, (xz.y - rect.y) / rect.w)


## The model point of `node` that reads the art coordinate `uv` (0..1 across and down), at model
## height `y`, in the body's own space.
func _local(node: MeshInstance3D, uv: Vector2, y: float) -> Vector3:
	var rect: Vector4 = node.get_instance_shader_parameter(&"uv_rect")
	return node.transform * Vector3(rect.x + uv.x * rect.z, y, rect.y + uv.y * rect.w)


## A 3D point or direction on the ground plane (x, z).
func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)
