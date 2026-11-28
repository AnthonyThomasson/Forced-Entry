extends GameTest
## A piece hung on a wall fades with the wall it hangs on (#193 rule 9, Art's `WallFade`, Objects'
## `FurnitureRig.hangs_on_wall`): a shell's wall stain, a menu board and a wall mirror hang on the
## inside face of a long wall; a character stood behind the wall far from them makes the wall's
## segment fade (the segment is one unit) and the piece fades with it, never left floating on a
## faded wall, and both are whole again when the character leaves. A free-standing piece with no
## wall behind it is its own unit, as any tall piece is.

const Probe := preload("res://tests/_art/art_wall_fade_probe.gd")
const STEP := 0.05
## The pieces: id, catalogue row and the x along the wall's segment they hang at (from its start).
const HUNG := [
	[&"stain", "wall_stain", 40.0],
	[&"menu", "menu_board", 150.0],
	[&"mirror", "mirror", 260.0],
]
## Where the free-standing piece stands, well off any wall.
const FREE := Vector2(700, 350)
## How far behind a wall's face (or a piece's middle) the character stands: at the 80 degree pitch
## a piece hides only what stands within its height over tan 80 of it.
const BEHIND := 3.0
## The free menu board's middle is 7.75 px north of FREE and it is 4.5 deep: the same gap behind it.
const FREE_BEHIND := 13.0

var _mirror: MeshCarrier
var _fade: WallFade


func describe() -> Dictionary:
	return {
		"name": "A wall-hung piece fades with the wall it hangs on",
		"description": "A wall stain, a menu board and a mirror on a long wall fade with the "
			+ "wall's segment when a character stands behind it, even far from them along "
			+ "it, and come back with it; a piece standing free is its own unit.",
		"tags": ["mirror", "3d", "render", "wall-fade", "meshkit"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 700))
	s.object(&"free_menu", "menu_board", FREE)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(WallFadeConfig, &"faded_amount", 0.25)
	s.von_script([])


func run(t: TestContext) -> void:
	await t.frames(3)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	_mirror = MeshCarrier.new()
	_fade = WallFade.new()
	view.add_child(_mirror)
	view.add_child(_fade)
	_fade.set_process(false)
	_fade.listen(_mirror)
	ObjectMeshes.register(_mirror.builders)
	_mirror.carry(t.world)
	await t.frames(3)
	var walls := Probe.walls(_mirror, t.world, 400.0)
	if not t.require(not walls.is_empty(), "premise: the arena has a long wall"):
		return
	var box: AABB = (walls[0]["part"] as MeshInstance3D).get_aabb()
	box = (walls[0]["part"] as MeshInstance3D).global_transform * box
	var top_wall := box.size.x > box.size.z and box.get_center().z < 350.0
	if not t.require(top_wall, "premise: it is the arena's top wall"):
		return
	var pieces := {}
	for row: Array in HUNG:
		pieces[row[0]] = _hang(t, row, box)
	await t.frames(4)
	_hung_pieces_fade_with_the_wall(t, walls[0], pieces, box)
	_a_free_piece_fades_alone(t)


## A character behind the wall's far end makes the wall fade, the camera's line meeting the wall
## and not the pieces; they fade with it and come back with it.
func _hung_pieces_fade_with_the_wall(
	t: TestContext, wall: Dictionary, pieces: Dictionary, box: AABB
) -> void:
	var back := Probe.back_of(0.0)
	var far := Vector2(box.end.x - 40.0, box.position.z) - back * BEHIND
	_run_fade([far], 20)
	t.check(Probe.level(wall["part"]) < 0.5, "premise: the wall segment fades for that character")
	for id: StringName in pieces:
		var parts := _parts_of(pieces[id])
		if t.require(not parts.is_empty(), "premise: %s is shown by a mesh" % id):
			t.check(
				parts.all(func(p: Node) -> bool: return Probe.level(p) < 0.5),
				"%s fades with the wall it hangs on (%d instances)" % [id, parts.size()],
			)
	# a hit rebuilds the segment; the pieces hung on it stay faded with the new one
	wall["mesh"].call(&"rebuild_segment", wall["index"])
	_run_fade([far], 1)
	for id: StringName in pieces:
		t.check(
			_parts_of(pieces[id]).all(func(p: Node) -> bool: return Probe.level(p) < 0.5),
			"%s stays faded when its wall's segment is rebuilt" % id,
		)
	_run_fade([], 20)
	var rebuilt: MeshInstance3D = wall["mesh"].call(&"segments")[wall["index"]]
	t.check(Probe.level(rebuilt) > 0.99, "the wall is whole when the character leaves")
	for id: StringName in pieces:
		t.check(
			_parts_of(pieces[id]).all(func(p: Node) -> bool: return Probe.level(p) > 0.99),
			"and %s is whole with it" % id,
		)


## A menu board with no wall behind it is a unit of its own once it has looked for a wall for
## `WallFadeConfig.hang_frames` frames, faded where it stands in the way.
func _a_free_piece_fades_alone(t: TestContext) -> void:
	var free := _parts_of(t.object(&"free_menu"))
	_run_fade([], WallFadeConfig.hang_frames + 2)  # it looks for a wall that is not there
	_run_fade([FREE - Probe.back_of(0.0) * FREE_BEHIND], 20)
	t.check(
		free.all(func(p: Node) -> bool: return Probe.level(p) < 0.5),
		"a menu board with no wall behind it fades by its own place, as a tall piece does",
	)


## Hang the piece of `row` on the inside face of the wall segment `box`, facing into the arena, at
## `row[2]` px along it.
func _hang(t: TestContext, row: Array, box: AABB) -> Node2D:
	var definition := WorldGen.object_definition(row[1])
	var size: Vector2 = definition["size"]
	var inner := Vector2(box.position.x + row[2] + size.x * 0.5, box.end.z + size.y * 0.5)
	var piece := ObjectFactory.spawn(definition, inner, t.world, { "name": String(row[0]) })
	return piece as Node2D


func _run_fade(foci: Array, steps: int) -> void:
	for i in steps:
		_fade.step(STEP, 0.0, PackedVector2Array(foci))


## Every geometry instance under the mesh shown for `body`.
func _parts_of(body: Node) -> Array:
	var parts: Array = []
	for mesh: Node3D in _mirror.proxies_of(body):
		if mesh is GeometryInstance3D:
			parts.append(mesh)
		parts.append_array(mesh.find_children("*", "GeometryInstance3D", true, false))
	return parts
