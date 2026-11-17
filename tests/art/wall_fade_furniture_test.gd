extends GameTest
## The wall fade over real furniture rigs (#193 rule 9, Art's `WallFade`, Objects' `FurnitureRig`):
## a tall piece (a wardrobe, a fridge) between the camera and a focus fades in all its instances
## (the rig's body and any glow node) through the mirror's `built` hook, and is whole again when the
## focus leaves; a low piece (a table, a dresser) is never looked at. The pieces are the catalogue's
## own (`s.object`), built by Objects' registered builders, so the heights are the meshes' own.

const SPOTS := {
	"wardrobe": Vector2(0, 0),
	"fridge": Vector2(400, 0),
	"dining_table": Vector2(800, 0),
	"dresser": Vector2(1200, 0),
	"shower": Vector2(1600, 0),
}
## Pieces under `WallFadeConfig.tall_height` (48 px): never looked at, so never faded. A dresser,
## a cabinet and a tool chest are 38 px (0.9 m) since the real-size retune (they were 56 and
## faded); the shower's glass is 80 (it was 38) and fades.
const LOW := ["dining_table", "dresser"]
## The gap between a piece's back face and the focus behind it: at the 80 degree pitch a piece
## hides only what stands within its height over tan 80 of it.
const GAP := 3.0
const STEP := 0.05


func describe() -> Dictionary:
	return {
		"name": "A tall furniture piece between the camera and a focus fades; a low one does not",
		"description": "Wardrobe and fridge meshes built by Objects fade in every instance when a "
			+ "focus stands behind them along the camera's line, and come back whole; a table "
			+ "is never faded.",
		"tags": ["mirror", "3d", "render", "wall-fade", "meshkit"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(-200, -200, 2000, 400))
	for id: String in SPOTS:
		s.object(StringName(id), id, SPOTS[id])
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(WallFadeConfig, &"faded_amount", 0.25)
	s.von_script([])


func run(t: TestContext) -> void:
	await t.frames(3)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	var fade := WallFade.new()
	view.add_child(mirror)
	view.add_child(fade)
	fade.set_process(false)
	fade.listen(mirror)
	ObjectMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(3)
	var back := Vector2(0, 1)  # at camera yaw 0 the camera is on +z, the screen's down
	for id: String in SPOTS:
		var parts := _parts_of(mirror, t.object(StringName(id)))
		if not t.require(not parts.is_empty(), "premise: %s is shown by a mesh" % id):
			return
		var focus: Vector2 = SPOTS[id] - back * (_half_depth(parts) + GAP)
		_run_fade(fade, [focus], 14)
		if id in LOW:
			t.check(
				parts.all(func(p: Node) -> bool: return _level(p) > 0.99),
				"%s is under the fade's tall height and is never faded" % id,
			)
			continue
		t.check(
			parts.all(func(p: Node) -> bool: return _level(p) < 0.5),
			"%s between the camera and a focus fades in all %d instances" % [id, parts.size()],
		)
		_run_fade(fade, [], 14)
		t.check(
			parts.all(func(p: Node) -> bool: return _level(p) > 0.99),
			"and %s is whole when the focus leaves" % id,
		)


func _run_fade(fade: WallFade, foci: Array, steps: int) -> void:
	for i in steps:
		fade.step(STEP, 0.0, PackedVector2Array(foci))


## Every geometry instance under the mesh shown for `body`.
func _parts_of(mirror: WorldMirror, body: Node) -> Array:
	var parts: Array = []
	for mesh: Node3D in mirror.proxies_of(body):
		if mesh is GeometryInstance3D:
			parts.append(mesh)
		parts.append_array(mesh.find_children("*", "GeometryInstance3D", true, false))
	return parts


## Half the depth (along the ground's z, the camera's line at yaw 0) of the pieces' instances
## together.
func _half_depth(parts: Array) -> float:
	var box := AABB()
	for i in parts.size():
		var part := parts[i] as GeometryInstance3D
		var world_box: AABB = part.global_transform * part.get_aabb()
		box = world_box if i == 0 else box.merge(world_box)
	return box.size.z * 0.5


func _level(part: Node) -> float:
	var value: Variant = (part as GeometryInstance3D).get_instance_shader_parameter(&"fade")
	return 1.0 if value == null else float(value)
