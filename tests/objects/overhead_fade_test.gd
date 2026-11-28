extends GameTest
## An overhead part of a street piece fades through the wall fade (#193 rule 9, Art's `WallFade`,
## Objects' `FurnitureRig`): an awning or a hanging sign between the camera and a character (in
## front of a door under it) thins out in all its instances, as 2D's `fade_under` did, and is whole
## again when the character leaves; a streetlight's post, a thin pole, is looked at too and a
## focus beside the awning leaves it whole.

const STEP := 0.05
## The pieces (an id, its catalogue row, the way it faces) at their places: an awning and a hanging
## sign on each of the four walls of a block, at spots 400 px apart.
const FACINGS := {
	&"down": Vector2.DOWN,
	&"left": Vector2.LEFT,
	&"up": Vector2.UP,
	&"right": Vector2.RIGHT,
}
## Camera yaws (degrees) the character stands under each piece at.
const YAWS := [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]
## How far out from the wall, in px along the facing, the character stands: in front of the door,
## and under the awning's lip.
const STANDS := [8.0, 24.0]


func describe() -> Dictionary:
	return {
		"name": "An awning or hanging sign between the camera and a character fades",
		"description": "A focus under an awning, or under a hanging sign, in front of its wall "
			+ "fades every instance of the piece's mesh through the mirror's built hook, and "
			+ "whole again when it leaves; a focus beside it leaves it whole.",
		"tags": ["mirror", "3d", "render", "wall-fade", "meshkit", "overhang"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 700))
	var at := Vector2(300, 200)
	for facing in FACINGS:
		for row: String in ["awning", "glyph_sign"]:
			s.object(StringName("%s_%s" % [row, facing]), row, at, { "facing": FACINGS[facing] })
			at.x += 400.0
		at = Vector2(300, at.y + 300.0)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(WallFadeConfig, &"faded_amount", 0.25)
	s.von_script([])


func run(t: TestContext) -> void:
	await t.frames(3)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	var fade := WallFade.new()
	view.add_child(mirror)
	view.add_child(fade)
	fade.set_process(false)
	fade.listen(mirror)
	ObjectMeshes.register(mirror.builders)
	mirror.carry(t.world)
	await t.frames(3)
	for facing in FACINGS:
		for row: String in ["awning", "glyph_sign"]:
			var id := StringName("%s_%s" % [row, facing])
			_check_piece(t, fade, mirror, id)


## `id` fades whole while a character stands out of its way, and from every camera yaw fades when
## one stands in front of its wall under it (as 2D's `fade_under` did), then comes back.
func _check_piece(t: TestContext, fade: WallFade, mirror: MeshCarrier, id: StringName) -> void:
	var piece := t.object(id)
	var parts := _parts_of(mirror, piece)
	if not t.require(not parts.is_empty(), "premise: %s is shown by a mesh" % id):
		return
	_run_fade(fade, [piece.global_position + Vector2(0, 900)], 14, 0.0)
	t.check(
		parts.all(func(p: Node) -> bool: return _level(p) > 0.99),
		"%s is whole while a character is far from it" % id,
	)
	for yaw: float in YAWS:
		for out: float in STANDS:
			var focus: Vector2 = piece.global_position + piece.look.facing * out
			_run_fade(fade, [focus], 14, yaw)
			t.check(
				parts.all(func(p: Node) -> bool: return _level(p) < 0.5),
				"%s fades when a character stands %d px out, camera yaw %d" % [id, out, yaw],
			)
			_run_fade(fade, [], 14, yaw)
			t.check(
				parts.all(func(p: Node) -> bool: return _level(p) > 0.99),
				"and %s is whole again when it leaves" % id,
			)


func _run_fade(fade: WallFade, foci: Array, steps: int, yaw: float) -> void:
	for i in steps:
		fade.step(STEP, yaw, PackedVector2Array(foci))


## Every geometry instance under the mesh shown for `body`.
func _parts_of(mirror: MeshCarrier, body: Node) -> Array:
	var parts: Array = []
	for mesh: Node3D in mirror.proxies_of(body):
		if mesh is GeometryInstance3D:
			parts.append(mesh)
		parts.append_array(mesh.find_children("*", "GeometryInstance3D", true, false))
	return parts


func _level(part: Node) -> float:
	var value: Variant = (part as GeometryInstance3D).get_instance_shader_parameter(&"fade")
	return 1.0 if value == null else float(value)
