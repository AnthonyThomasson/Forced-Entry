extends GameTest
## The mirror's rule for a body whose collision shapes change (#193, Art's `MeshCarrier`, interface
## 27), on its own: a shape added to a mirrored body builds its mesh again, unless the mesh says
## `follows_shapes() -> true` (a wall's, which replaces the one segment that changed itself), and a
## shape that is queued to be freed is never a change. Counted by how often the builder is asked.

const ProbeTwins := preload("res://tests/_art/art_probe_twins.gd")

var _asked := 0
var _follows := false


func describe() -> Dictionary:
	return {
		"name": "A mirrored body whose shapes change is meshed again unless its mesh follows them",
		"description": "A shape added to a body builds its mesh again; with follows_shapes() true "
			+ "it does not; a shape queued to be freed never does.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	ProbeTwins.install(t.world)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	mirror.builders[MeshKinds.FURNITURE] = func(_body: Node2D) -> Node3D:
		_asked += 1
		var mesh := StandIn.new()
		mesh.follows = _follows
		return mesh
	view.add_child(mirror)
	var body := StaticBody2D.new()
	body.add_child(_shape())
	t.world.add_child(body)
	mirror.carry(t.world)
	await t.frames(2)
	t.expect_eq(_asked, 1, "premise: the body's mesh was built once")
	body.add_child(_shape())
	await t.frames(2)
	t.expect_eq(_asked, 2, "a shape added: a mesh that does not follow its shapes is built again")
	var doomed := _shape()
	body.add_child(doomed)
	await t.frames(2)
	t.expect_eq(_asked, 3, "premise: another shape added, built again")
	doomed.queue_free()
	await t.frames(2)
	t.expect_eq(_asked, 3, "a shape queued to be freed is no change")
	_follows = true
	mirror.remirror(body)
	t.expect_eq(_asked, 4, "premise: built again with a mesh that follows its shapes")
	body.add_child(_shape())
	await t.frames(2)
	t.expect_eq(_asked, 4, "a shape added: a mesh that follows them is left alone")


func _shape() -> CollisionShape2D:
	var node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 20)
	node.shape = rect
	return node


## A mesh that says whether it follows its body's shapes itself.
class StandIn extends Node3D:
	var follows := false

	func follows_shapes() -> bool:
		return follows
