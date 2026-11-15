extends UnitSuite
## Native unit suite (pure logic) for the furniture meshes (`ObjectMeshes.BUILDERS`, Objects; the
## domestic kinds): the cache key of every mesh names every tuning value its shape reads, so a
## retuned holder is another mesh and never a stale cached one. Each tuning field of the six
## `ObjectMesh*Config` holders is changed in turn and each kind rebuilt with the cache warm and then
## with it cleared: a mesh the warm cache answers with the old resource must be the mesh the empty
## cache would build.

const Probe := preload("res://tests/_objects/furniture_piece_probe.gd")
const HOLDERS := [
	"res://scenes/objects/art/object_mesh_config.gd",
	"res://scenes/objects/art/object_mesh_chair_config.gd",
	"res://scenes/objects/art/object_mesh_decor_config.gd",
	"res://scenes/objects/art/object_mesh_kitchen_config.gd",
	"res://scenes/objects/art/object_mesh_room_config.gd",
	"res://scenes/objects/art/object_mesh_seat_config.gd",
	"res://scenes/objects/art/object_mesh_state_config.gd",
	"res://scenes/objects/art/object_mesh_storage_config.gd",
]
## Every look the kinds' options give: [art id, size, art_opts, facing].
const LOOKS := [
	["sofa", Vector2(150, 70), {}, Vector2.DOWN],
	["sofa", Vector2(60, 150), { "cushion_width": 5 }, Vector2.LEFT],
	["chair", Vector2(30, 30), {}, Vector2.DOWN],
	["cabinet", Vector2(90, 45), { "front": "doors", "count": 2, "crown": true }, Vector2.DOWN],
	["cabinet", Vector2(70, 40), { "front": "drawers", "count": 3 }, Vector2.UP],
	["shelf", Vector2(80, 25), { "contents": "books" }, Vector2.DOWN],
	["shelf", Vector2(80, 25), { "contents": "boxes" }, Vector2.DOWN],
	["shelf", Vector2(50, 20), { "contents": "shoes" }, Vector2.DOWN],
	["counter", Vector2(120, 50), {}, Vector2.DOWN],
	["counter", Vector2(60, 50), { "basin": "single" }, Vector2.DOWN],
	["counter", Vector2(60, 50), { "basin": "deep" }, Vector2.DOWN],
	["appliance", Vector2(60, 60), { "panel": "burners" }, Vector2.DOWN],
	["appliance", Vector2(60, 60), { "panel": "fridge" }, Vector2.DOWN],
	["appliance", Vector2(40, 40), { "panel": "fridge" }, Vector2.DOWN],
	["appliance", Vector2(50, 40), { "panel": "microwave" }, Vector2.DOWN],
	["appliance", Vector2(60, 60), { "panel": "washer" }, Vector2.DOWN],
	["appliance", Vector2(60, 60), { "panel": "dryer" }, Vector2.DOWN],
	["appliance", Vector2(60, 30), { "panel": "tv" }, Vector2.DOWN],
	["appliance", Vector2(60, 40), {}, Vector2.DOWN],
	["bed", Vector2(120, 180), {}, Vector2.DOWN],
	["office_chair", Vector2(34, 34), {}, Vector2.DOWN],
	["toilet", Vector2(40, 60), {}, Vector2.DOWN],
	["bath", Vector2(150, 70), {}, Vector2.DOWN],
	["bath", Vector2(80, 80), { "style": "shower" }, Vector2.DOWN],
	["rug", Vector2(160, 110), {}, Vector2.DOWN],
	["rug", Vector2(160, 60), { "pattern": "stripes" }, Vector2.DOWN],
	["rug", Vector2(60, 50), { "pattern": "plush" }, Vector2.DOWN],
	["plant", Vector2(36, 36), {}, Vector2.DOWN],
	["lamp", Vector2(30, 30), {}, Vector2.DOWN],
	["lamp", Vector2(30, 30), { "neon": "pink" }, Vector2.DOWN],
	["coat_rack", Vector2(24, 24), {}, Vector2.DOWN],
	["recliner", Vector2(60, 90), {}, Vector2.DOWN],
	["recliner", Vector2(60, 90), { "kind": "surgical" }, Vector2.DOWN],
	["fixture", Vector2(44, 12), {}, Vector2.DOWN],
	["fixture", Vector2(44, 12), { "kind": "towels" }, Vector2.DOWN],
	["hotplate", Vector2(60, 40), {}, Vector2.DOWN],
]


## A fingerprint of the rig `look` is shown by: the vertices and colours of every mesh on it, and
## with `identity` the resources themselves (two pieces that share their meshes have one).
func _fingerprint(look: Array, identity := false) -> int:
	var piece := Probe.new()
	piece.size = look[1]
	piece.look.art_opts = look[2]
	piece.look.facing = look[3]
	var rig: Node3D = ObjectMeshes.BUILDERS[look[0]].build(piece)
	var found: Array = []
	var nodes: Array = [rig]
	nodes.append_array(rig.get_children())
	for node in nodes:
		if node is MeshInstance3D and node.mesh != null:
			var arrays: Array = (node.mesh as ArrayMesh).surface_get_arrays(0)
			found.append([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_COLOR]])
			if identity:
				found.append(node.mesh.get_instance_id())
	rig.free()
	piece.free()
	return hash(found)


## The numeric `static var`s of the holder script at `path`, field -> value.
func _numbers_of(path: String) -> Dictionary:
	var holder: Object = load(path)
	var out := {}
	var pattern := RegEx.create_from_string("(?m)^static var (\\w+)")
	for found in pattern.search_all(FileAccess.get_file_as_string(path)):
		var field := found.get_string(1)
		var value: Variant = holder.get(field)
		if value is float or value is int:
			out[field] = value
	return out


## Whether `field` of the holder at `path`, doubled and a bit more, leaves the mesh of `look`
## what the empty cache builds: the warm cache must not answer with the mesh of the old value.
func _key_names(path: String, field: String, look: Array) -> bool:
	var holder: Object = load(path)
	var was: Variant = holder.get(field)
	MeshCache.clear()
	_fingerprint(look)
	holder.set(field, was * 2 + 3)
	var warm := _fingerprint(look)
	MeshCache.clear()
	var cold := _fingerprint(look)
	holder.set(field, was)
	return warm == cold


func test_every_tuning_value_a_furniture_mesh_reads_is_in_its_cache_key() -> void:
	var stale: Array[String] = []
	for path: String in HOLDERS:
		for field: String in _numbers_of(path):
			for look: Array in LOOKS:
				if not _key_names(path, field, look):
					stale.append("%s.%s: %s %s" % [path.get_file(), field, look[0], look[2]])
	MeshCache.clear()
	assert_array(stale).override_failure_message(
		"not in the cache key of the mesh: %s" % [stale]
	).is_empty()


func test_pieces_of_one_look_share_their_meshes_and_a_turn_is_another_mesh() -> void:
	MeshCache.clear()
	for look: Array in LOOKS:
		assert_int(_fingerprint(look, true)).is_equal(_fingerprint(look, true))
	var sofa: Array = LOOKS[0]
	var turned: Array = [sofa[0], sofa[1], sofa[2], Vector2.LEFT]
	assert_int(_fingerprint(sofa)).is_not_equal(_fingerprint(turned))
	MeshCache.clear()
