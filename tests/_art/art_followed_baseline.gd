extends Node3D
## Test helper (windowed picture tests): the picture a body's mesh makes when it is placed by hand
## from the 2D body's pose, not carried on its twin. `show_followed(carrier, bodies)` takes the
## carried mesh of each body off its twin and builds the same mesh again (the carrier's own
## builder), standing where the body stands each frame (a body a free 3D body leads stands as that
## does, tilt and all) with its `mirror_update` run and shown as the carrier shows the one it
## replaced: the reference a carried picture is compared against.

## Body -> the mesh this helper holds for it.
var _held: Dictionary = {}
## Body -> the carried mesh it replaced (the carrier still decides whether that one shows).
var _carried: Dictionary = {}


func _process(_delta: float) -> void:
	for body: Variant in _held:
		if is_instance_valid(body):
			_place(body as Node2D, _held[body] as Node3D)


## `mesh` stands where `body` does, its `mirror_update` run.
func _place(body: Node2D, mesh: Node3D) -> void:
	var lead := TwinSpace.leader_of(body)
	mesh.transform = (
		lead.global_transform if lead != null else PlanSpace.lift_transform(body.global_transform)
	)
	var carried := _carried.get(body) as Node3D
	mesh.visible = carried == null or not is_instance_valid(carried) or carried.visible
	if mesh.has_method(&"mirror_update"):
		mesh.call(&"mirror_update", body)


## Show `bodies` by meshes placed from their 2D pose, in place of the ones `carrier` carries.
## Returns how many bodies were shown so.
func show_followed(carrier: MeshCarrier, bodies: Array[Node2D]) -> int:
	var shown := 0
	for body in bodies:
		var carried := carrier.mesh_of(body)
		var builder := carrier.builder_for(body)
		if carried == null or not builder.is_valid():
			continue
		var made: Variant = builder.call(body)
		if not made is Node3D:
			continue
		carried.get_parent().remove_child(carried)  # the carried mesh leaves the picture
		add_child(made as Node3D)
		_held[body] = made
		_carried[body] = carried
		_place(body, made as Node3D)  # at once: a view that does not process still draws it
		shown += 1
	return shown


## The mesh this helper holds for `body`, or null.
func mesh_of(body: Node) -> Node3D:
	return _held.get(body)
