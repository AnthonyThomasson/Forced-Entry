extends GameTest
## A piece that stands still (no `mirror_update`, no turn, not shown only once seen) costs the
## carrier next to nothing a frame, and keeps every shown rule all the same (interface 27): in the
## update that follows, its mesh follows its body's `visible`, a view layer put on `MOVING` (hidden
## outside the cone, marked moving for the shaders) and back, and a mesh freed under the carrier is
## built again. The carrier counts it among the meshes it looked at.

const ProbeTwins := preload("res://tests/_art/art_probe_twins.gd")
## An area of the view that does not reach the chair.
const FAR_AREA := Rect2(2000, 2000, 100, 100)


func describe() -> Dictionary:
	return {
		"name": "A still piece's mesh keeps the shown rules",
		"description": "A still piece's mesh hides and shows with its body, follows its view "
			+ "layer outside the cone and back, and is built again when freed.",
		"tags": ["mirror", "3d", "render", "vision"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"chair", "armchair", Vector2(300, 200))
	s.object(&"other", "armchair", Vector2(500, 200))


func run(t: TestContext) -> void:
	await t.frames(5)
	ProbeTwins.install(t.world)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var carrier := MeshCarrier.new()
	view.add_child(carrier)
	carrier.builders[MeshKinds.FURNITURE] = func(_body: Node2D) -> Node3D:
		var made := Node3D.new()
		made.add_child(MeshNodes.instance(BoxMesh.new()))
		return made
	carrier.carry(t.world)
	await t.frames(3)
	var chair := t.object(&"chair")
	var mesh := carrier.mesh_of(chair)
	if not t.require(mesh != null and mesh.visible, "premise: the chair's mesh is shown"):
		return
	carrier.update()
	t.expect_eq(carrier.followed, 2, "the still pieces are counted among the meshes looked at")
	chair.visible = false
	carrier.update()
	t.check(not mesh.visible, "a hidden body's mesh is hidden by the next update")
	chair.visible = true
	carrier.update()
	t.check(mesh.visible, "and shown again with it")
	_check_view(t, carrier, chair, mesh)
	mesh.free()
	carrier.update()
	carrier.update()
	var fresh := carrier.mesh_of(chair)
	t.check(fresh != null and is_instance_valid(fresh), "a mesh freed under it is built again")
	t.expect_eq(carrier.count, 2, "as many meshes as before")
	chair.visible = false
	carrier.update()
	t.check(fresh != null and not fresh.visible, "the new mesh follows the body too")
	chair.visible = true
	carrier.update()
	_check_other_kept(t, carrier, chair)


## Building one still mesh again leaves the other still piece's rules in place.
func _check_other_kept(t: TestContext, carrier: MeshCarrier, chair: Node2D) -> void:
	var other := t.object(&"other")
	carrier.remirror(chair)
	other.visible = false
	carrier.update()
	t.expect_eq(carrier.followed, 2, "two still pieces after one is built again")
	t.check(not carrier.mesh_of(other).visible, "and the other one still follows its body")


## With a view on that does not reach it, a piece put on `MOVING` is hidden and its mesh marked
## moving; back on `WORLD` it is shown and the mark is gone. One put on `MOVING` while no view is
## on is hidden when the view comes on, though its body says nothing then.
func _check_view(t: TestContext, carrier: MeshCarrier, chair: Node2D, mesh: Node3D) -> void:
	var white := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	ToonMask.set_mask(ImageTexture.create_from_image(white), FAR_AREA, 0.0)
	var corners := PackedVector2Array([
		FAR_AREA.position,
		Vector2(FAR_AREA.end.x, FAR_AREA.position.y),
		FAR_AREA.end,
		Vector2(FAR_AREA.position.x, FAR_AREA.end.y),
	])
	SeenArea.set_area([corners], FAR_AREA)
	carrier.update()
	t.check(mesh.visible, "a still piece outside the cone is shown (it is remembered)")
	ViewLayers.set_moving(chair, true)
	carrier.update()
	t.check(not mesh.visible, "put on MOVING outside the cone it is hidden")
	t.check(bool(mesh.get_meta(&"moving", false)), "and marked moving")
	SeenArea.clear()
	carrier.update()
	t.check(mesh.visible, "still MOVING, with the view gone it is shown")
	ViewLayers.set_moving(chair, false)
	carrier.update()
	t.check(mesh.visible, "back on WORLD it is shown")
	t.check(not bool(mesh.get_meta(&"moving", true)), "and no longer marked moving")
	ToonMask.clear()
	ViewLayers.set_moving(chair, true)
	carrier.update()
	carrier.update()
	t.check(mesh.visible, "put on MOVING with no view on, it is shown")
	ToonMask.set_mask(ImageTexture.create_from_image(white), FAR_AREA, 0.0)
	SeenArea.set_area([corners], FAR_AREA)
	carrier.update()
	t.check(not mesh.visible, "the view coming on later, outside its cone, hides it")
	SeenArea.clear()
	ToonMask.clear()
	ViewLayers.set_moving(chair, false)
	carrier.update()
