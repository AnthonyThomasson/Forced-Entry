extends GameTest
## The wall fade's rules (#193 rule 9, Art's `WallFade`, interface 27), on a stand-in wall of
## separable segments and a few pieces of furniture stepped by hand: a wall between the camera and
## a focus fades, one behind it does not, turning the camera swaps them, one past the radius (or too
## far for its height to hide anyone, at the 80 degree pitch a wall 17 px away) stays whole, a tall
## piece fades but a low one is never looked at, spectating fades around every focus, a fade comes
## and goes over `WallFadeConfig.fade_time` without a pop, a rebuilt segment or a piece built again
## keeps its fade, and a still view writes nothing. The camera's back direction at yaw 0 is +z (the
## screen's down), at 180 it is -z; the expected numbers are the spec's (reach `radius` px, a wall's
## height over the camera's tangent: 96 over tan 80 is 16.9 px; a wall must overlap the character's
## 28 px width to fade), not the fade's own arithmetic.

const WALL_HEIGHT := 96.0
const STEP := 0.05
## One segment of the stand-in wall: where it stands (x, z), how long (along x) and how thick.
const SEGMENTS := [
	{ "name": "near", "at": Vector2(0, 12), "len": 200.0 },
	{ "name": "behind", "at": Vector2(0, -12), "len": 200.0 },
	{ "name": "past_radius", "at": Vector2(0, 200), "len": 200.0 },
	{ "name": "too_far_to_hide", "at": Vector2(0, 24), "len": 200.0 },
	{ "name": "beside", "at": Vector2(150, 12), "len": 40.0 },
	{ "name": "near_second", "at": Vector2(600, 12), "len": 200.0 },
	{ "name": "between", "at": Vector2(300, 12), "len": 40.0 },
	{ "name": "clips_shoulder", "at": Vector2(25, 12), "len": 30.0 },
	{ "name": "clears_shoulder", "at": Vector2(46, 12), "len": 30.0 },
]
const THICK := 8.0

var _fade: WallFade
var _wall: StandInWall
var _tall: Node3D
var _low: Node3D


func describe() -> Dictionary:
	return {
		"name": "Walls and tall pieces between the camera and a focus fade, the rest stay whole",
		"description": "A wall in the line to the camera fades within the radius, one behind or "
			+ "beside or too far does not, turning the camera swaps them, a tall piece fades and a "
			+ "low one is not looked at, every focus counts, a fade never pops, a rebuilt segment "
			+ "and a piece built again keep theirs, and a still view writes nothing.",
		"tags": ["mirror", "3d", "render", "wall-fade"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(RenderConfig, &"pitch_degrees", 80.0)
	s.set_static(WallFadeConfig, &"radius", 40.0)
	s.set_static(WallFadeConfig, &"fade_time", 0.25)
	s.set_static(WallFadeConfig, &"faded_amount", 0.25)


func run(t: TestContext) -> void:
	_build(t)
	step(0.0, 0.0, [Vector2.ZERO])
	t.expect_eq(
		_fade.count(),
		SEGMENTS.size() + 1,
		"every wall segment and the tall piece is known",
	)
	_one_focus_one_yaw(t)
	_a_fade_never_pops(t)
	_a_still_view_writes_nothing(t)
	_turning_swaps(t)
	_spectating(t)
	_radius_is_tunable(t)
	_rebuilt_segment_keeps_its_fade(t)
	_piece_built_again_keeps_its_fade(t)
	_far_pieces_are_not_looked_at(t)
	_a_moved_piece_is_found_where_it_went(t)
	_a_forgotten_wall_leaves_no_trace(t)
	_a_faded_unit_casts_no_shadow(t)


## The stand-in wall, a tall piece and a low one in a world of their own, the fade stepped by hand.
func _build(t: TestContext) -> void:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	_fade = WallFade.new()
	view.add_child(_fade)
	_fade.set_process(false)
	_wall = StandInWall.new()
	_wall.specs = SEGMENTS
	view.add_child(_wall)
	for i in SEGMENTS.size():
		_wall.put(i)
	_fade.watch(_wall, 1, false)
	_tall = _piece(view, "tall", Vector3(0, 0, 28), Vector3(40, 70, 40))
	_low = _piece(view, "low", Vector3(0, 0, 28), Vector3(40, 30, 40))
	_fade.watch(_tall, 2, true)
	_fade.watch(_low, 3, true)


## A piece of furniture: a mesh node at `at` holding one box instance of `size` standing on it.
func _piece(parent: Node, piece_name: String, at: Vector3, size: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = piece_name
	node.position = at
	parent.add_child(node)
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	part.mesh = box
	part.position = Vector3(0, size.y * 0.5, 0)
	node.add_child(part)
	return node


## Step the fade `seconds` long in small steps with the camera at `yaw` degrees and `foci`.
func settle(seconds: float, yaw: float, foci: Array) -> void:
	for i in roundi(seconds / STEP):
		step(STEP, yaw, foci)


func step(delta: float, yaw: float, foci: Array) -> void:
	_fade.step(delta, yaw, PackedVector2Array(foci))


## How whole an instance is drawn now: what the shader is told (1 when nothing was ever written).
func shown(part: Node) -> float:
	var value: Variant = (part as GeometryInstance3D).get_instance_shader_parameter(&"fade")
	return 1.0 if value == null else float(value)


func segment(index: int) -> MeshInstance3D:
	return _wall.get_node("Segment%d" % index) as MeshInstance3D


func _segment_named(piece_name: String) -> MeshInstance3D:
	for i in SEGMENTS.size():
		if SEGMENTS[i]["name"] == piece_name:
			return segment(i)
	return null


func _faded_level() -> float:
	return WallFadeConfig.faded_amount


## A wall in the way fades to `faded_amount`, a tall piece with it; everything else stays whole.
func _one_focus_one_yaw(t: TestContext) -> void:
	settle(0.6, 0.0, [Vector2.ZERO])
	t.expect_near(shown(_segment_named("near")), _faded_level(), 0.07, "the wall in the way fades")
	t.expect_near(
		shown(_segment_named("clips_shoulder")),
		_faded_level(),
		0.07,
		"a wall at the shoulder fades",
	)
	for piece_name in [
		"behind", "past_radius", "too_far_to_hide", "beside", "between", "clears_shoulder",
	]:
		t.expect_near(shown(_segment_named(piece_name)), 1.0, 0.001, "%s stays whole" % piece_name)
	t.expect_near(shown(_tall.get_child(0)), _faded_level(), 0.07, "a tall piece in the way fades")
	t.expect_near(shown(_low.get_child(0)), 1.0, 0.001, "a low piece is never looked at")
	t.expect_eq(_fade.fading, 3, "three units are not whole")


## It goes from whole to faded over the fade time: partway after a step, there after the time, and
## the same way back, in steps that are never the whole range at once.
func _a_fade_never_pops(t: TestContext) -> void:
	var part := _segment_named("near")
	settle(0.6, 0.0, [])
	t.expect_near(shown(part), 1.0, 0.001, "premise: no focus, whole again")
	var seen: Array[float] = []
	for i in 8:
		step(STEP, 0.0, [Vector2.ZERO])
		seen.append(shown(part))
	t.check(seen[0] < 1.0 and seen[0] > _faded_level(), "one step in it is partway: %f" % seen[0])
	t.check(seen[3] > _faded_level() or seen[4] > _faded_level(), "it takes about the fade time")
	t.expect_near(seen[7], _faded_level(), 0.07, "and is faded after it")
	var jump := 0.0
	for i in range(1, seen.size()):
		t.check(seen[i] <= seen[i - 1] + 0.0001, "it only thins while it is in the way")
		jump = maxf(jump, seen[i - 1] - seen[i])
	t.check(jump < (1.0 - _faded_level()) * 0.5, "no step is half the range: %f" % jump)
	var back: Array[float] = []
	for i in 8:
		step(STEP, 0.0, [])
		back.append(shown(part))
	t.expect_near(back[7], 1.0, 0.001, "out of the way it is whole again in the same time")
	t.check(back[0] < 1.0 and back[0] > _faded_level(), "and it does not pop back")
	settle(0.6, 0.0, [Vector2.ZERO])


## A view that did not change writes no instance, and nothing is listed that is whole.
func _a_still_view_writes_nothing(t: TestContext) -> void:
	for i in 5:
		step(STEP, 0.0, [Vector2.ZERO])
		t.expect_eq(_fade.written, 0, "step %d of a still view wrote nothing" % i)
	settle(0.6, 0.0, [])
	for i in 3:
		step(STEP, 0.0, [])
		t.expect_eq(_fade.written, 0, "no focus, all whole: nothing written (%d)" % i)
	t.expect_eq(_fade.fading, 0, "and nothing is listed")
	settle(0.6, 0.0, [Vector2.ZERO])


## Turning the camera a half turn swaps the wall in front for the one that was behind.
func _turning_swaps(t: TestContext) -> void:
	settle(0.6, 180.0, [Vector2.ZERO])
	t.expect_near(shown(_segment_named("near")), 1.0, 0.001, "turned: the old front wall is whole")
	t.expect_near(shown(_segment_named("behind")), _faded_level(), 0.07, "the one behind fades")
	t.expect_near(shown(_tall.get_child(0)), 1.0, 0.001, "and so is the tall piece, now behind")
	settle(0.6, 0.0, [Vector2.ZERO])
	t.expect_near(
		shown(_segment_named("near")),
		_faded_level(),
		0.07,
		"turned back: it fades again",
	)
	t.expect_near(shown(_segment_named("behind")), 1.0, 0.001, "and the other is whole")


## Spectating: every focus fades the wall in its own way, and a wall near none stays.
func _spectating(t: TestContext) -> void:
	settle(0.6, 0.0, [Vector2.ZERO])
	t.expect_near(
		shown(_segment_named("near_second")),
		1.0,
		0.001,
		"one focus: the far wall is whole",
	)
	settle(0.6, 0.0, [Vector2.ZERO, Vector2(600, 0)])
	t.expect_near(
		shown(_segment_named("near")),
		_faded_level(),
		0.07,
		"the first focus's wall fades",
	)
	t.expect_near(
		shown(_segment_named("near_second")),
		_faded_level(),
		0.07,
		"so does the second's",
	)
	t.expect_near(shown(_segment_named("between")), 1.0, 0.001, "a wall between them stays")
	settle(0.6, 0.0, [Vector2(600, 0)])
	t.expect_near(
		shown(_segment_named("near")),
		1.0,
		0.001,
		"the first focus gone: its wall is whole",
	)
	t.expect_near(shown(_segment_named("near_second")), _faded_level(), 0.07, "the second's holds")
	settle(0.6, 0.0, [Vector2.ZERO])


## A shorter radius leaves a wall that was in reach whole; the tunable is put back.
func _radius_is_tunable(t: TestContext) -> void:
	var was := WallFadeConfig.radius
	WallFadeConfig.radius = 5.0
	settle(0.6, 0.0, [Vector2.ZERO])
	t.expect_near(
		shown(_segment_named("near")),
		1.0,
		0.001,
		"radius 5: the wall 8 px away is whole",
	)
	WallFadeConfig.radius = was
	settle(0.6, 0.0, [Vector2.ZERO])
	t.expect_near(shown(_segment_named("near")), _faded_level(), 0.07, "radius back: it fades")


## A wall that rebuilds a segment (a hit) has the fade on the new instance at once and lets it go
## when the focus leaves, the old instance gone with no error.
func _rebuilt_segment_keeps_its_fade(t: TestContext) -> void:
	var before := shown(_segment_named("near"))
	var old := _segment_named("near")
	var index := SEGMENTS.find_custom(func(s): return s["name"] == "near")
	var old_unit := _fade.unit_of(1, index)
	var entries := _fade.grid.entries
	var part := _wall.replace(index)
	t.check(part != old, "premise: the segment is a new instance")
	t.check(not _fade.grid.holds(old_unit), "the replaced segment's old unit is in no grid cell")
	t.expect_eq(_fade.grid.entries, entries, "and the grid holds as many entries as before")
	t.expect_eq(_fade.count(), SEGMENTS.size() + 1, "and as many units")
	t.expect_near(shown(part), before, 0.001, "the new instance has the fade at once")
	t.expect_near(shown(part), _faded_level(), 0.07, "which is a faded one")
	settle(0.6, 0.0, [Vector2.ZERO])
	t.expect_near(shown(part), _faded_level(), 0.07, "it stays faded while the focus is there")
	settle(0.6, 0.0, [])
	t.expect_near(shown(part), 1.0, 0.001, "and comes back when it leaves")
	settle(0.6, 0.0, [Vector2.ZERO])


## A piece built again (a dent) while faded starts at the fade it had, not whole.
func _piece_built_again_keeps_its_fade(t: TestContext) -> void:
	var before := shown(_tall.get_child(0))
	t.expect_near(before, _faded_level(), 0.07, "premise: the tall piece is faded")
	var parent := _tall.get_parent()
	var at := _tall.position
	parent.remove_child(_tall)
	_tall.free()
	_tall = _piece(parent, "tall_again", at, Vector3(40, 70, 40))
	_fade.watch(_tall, 2, true)
	step(0.0, 0.0, [Vector2.ZERO])
	t.expect_near(shown(_tall.get_child(0)), before, 0.001, "the new piece starts at that fade")
	settle(0.6, 0.0, [])
	t.expect_near(shown(_tall.get_child(0)), 1.0, 0.001, "and comes back when it is not in the way")


## A unit more than half faded casts no shadow (a stippled one would darken the character behind
## it); whole again, each part has the setting it had: a part that cast none still casts none. A
## fixed and a movable piece, each with a handle that casts none, in a fade of their own.
func _a_faded_unit_casts_no_shadow(t: TestContext) -> void:
	var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var on := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	_fade = WallFade.new()
	view.add_child(_fade)
	_fade.set_process(false)
	var pieces: Array[Node3D] = []
	for key in 2:
		var piece := _piece(view, "shadowed", Vector3(0, 0, 28), Vector3(40, 70, 40))
		var handle := MeshInstance3D.new()
		handle.mesh = BoxMesh.new()
		handle.cast_shadow = off
		handle.position = Vector3(0, 35, 0)
		piece.add_child(handle)
		_fade.watch(piece, 20 + key, key == 1)
		pieces.append(piece)
	step(0.0, 0.0, [])
	t.expect_eq(_casts(pieces, 0), [on, on], "premise: both pieces cast their shadows")
	settle(0.1, 0.0, [Vector2.ZERO])  # a little under half faded
	t.expect_eq(_casts(pieces, 0), [on, on], "under half faded they still cast")
	settle(0.1, 0.0, [Vector2.ZERO])
	t.expect_eq(_casts(pieces, 0), [off, off], "more than half faded they cast no shadow")
	t.expect_eq(_casts(pieces, 1), [off, off], "nor does a part of them")
	settle(0.6, 0.0, [Vector2.ZERO])
	step(STEP, 0.0, [Vector2.ZERO])
	t.expect_eq(_fade.written, 0, "a settled fade writes nothing, shadows included")
	settle(0.6, 0.0, [])
	t.expect_eq(_casts(pieces, 0), [on, on], "whole again they cast as before")
	t.expect_eq(_casts(pieces, 1), [off, off], "the part that cast none still casts none")


## The `cast_shadow` of child `index` of each of `pieces`.
func _casts(pieces: Array[Node3D], index: int) -> Array:
	var found: Array = []
	for piece in pieces:
		found.append((piece.get_child(index) as GeometryInstance3D).cast_shadow)
	return found


## Hundreds of movable pieces far from the focus are never asked: the grid only gives the units in
## the cells the focus reaches.
func _far_pieces_are_not_looked_at(t: TestContext) -> void:
	var parent := _tall.get_parent()
	for i in 300:
		var far := _piece(
			parent,
			"far%d" % i,
			Vector3(4000.0 + i * 20.0, 0, 3000.0),
			Vector3(30, 70, 30),
		)
		_fade.watch(far, 1000 + i, true)
	step(STEP, 0.0, [Vector2.ZERO])
	t.expect_eq(_fade.count(), SEGMENTS.size() + 1 + 300, "premise: the far pieces are kept")
	step(STEP, 0.0, [Vector2.ZERO])
	t.check(_fade.looked < 20, "a focus asks the units near it, not the %d far ones (%d)"
		% [300, _fade.looked])


## A movable piece that was shoved to the focus's line is found there within the poll's rounds.
func _a_moved_piece_is_found_where_it_went(t: TestContext) -> void:
	var piece := _fade.unit_of(1000)
	t.check(piece != null and piece.movable, "premise: a far movable piece")
	var mesh := piece.anchor
	mesh.position = Vector3(0, 0, 20)
	for i in WallFadeConfig.poll_frames + 2:
		step(STEP, 0.0, [Vector2.ZERO])
	settle(0.6, 0.0, [Vector2.ZERO])
	t.expect_near(shown(mesh.get_child(0)), _faded_level(), 0.07, "it fades where it went")
	t.check(_fade.grid.holds(piece), "and the grid has it there")


## A wall leaving the tree takes its units out of the grid and the count.
func _a_forgotten_wall_leaves_no_trace(t: TestContext) -> void:
	var before := _fade.count()
	var entries := _fade.grid.entries
	var units: Array[FadeUnit] = []
	for i in SEGMENTS.size():
		units.append(_fade.unit_of(1, i))
	_wall.get_parent().remove_child(_wall)
	t.expect_eq(_fade.count(), before - SEGMENTS.size(), "its units are not counted")
	t.check(
		entries > _fade.grid.entries,
		"and its grid entries are gone (%d left)" % _fade.grid.entries,
	)
	t.check(
		units.all(func(u: FadeUnit) -> bool: return not _fade.grid.holds(u)),
		"none is in a cell",
	)
	_wall.free()


## A wall of one separable instance per segment that says when it rebuilt one, as `WallMesh` does.
class StandInWall extends Node3D:
	signal segment_replaced(index: int, part: MeshInstance3D)

	var specs: Array = []

	func segments() -> Dictionary:
		var out := {}
		for child in get_children():
			if child is MeshInstance3D:
				out[int(String(child.name).trim_prefix("Segment"))] = child
		return out

	func put(index: int) -> MeshInstance3D:
		var spec: Dictionary = specs[index]
		var part := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(spec["len"], 96.0, 8.0)
		part.mesh = box
		part.name = "Segment%d" % index
		part.position = Vector3(spec["at"].x, 48.0, spec["at"].y)
		add_child(part)
		return part

	func replace(index: int) -> MeshInstance3D:
		var old := get_node("Segment%d" % index)
		remove_child(old)
		old.free()
		var part := put(index)
		segment_replaced.emit(index, part)
		return part
