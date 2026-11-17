extends UnitSuite
## Native unit suite (pure logic) for the furniture meshes (`ObjectMeshes.BUILDERS`, Objects; the
## domestic, commercial, shell and street kinds): the cache key of every mesh names every tuning
## value its shape reads, so a retuned holder is another mesh and never a stale cached one. Each
## tuning field of the `ObjectMesh*Config` holders is changed in turn and each kind rebuilt with the
## cache warm and then with it cleared: a mesh the warm cache answers with the old resource must be
## the mesh the empty cache would build.

const Probe := preload("res://tests/_objects/furniture_piece_probe.gd")
const HOLDERS := [
	"res://scenes/objects/art/object_mesh_config.gd",
	"res://scenes/objects/art/object_mesh_car_config.gd",
	"res://scenes/objects/art/object_mesh_chair_config.gd",
	"res://scenes/objects/art/object_mesh_clinic_config.gd",
	"res://scenes/objects/art/object_mesh_decor_config.gd",
	"res://scenes/objects/art/object_mesh_kitchen_config.gd",
	"res://scenes/objects/art/object_mesh_noodle_config.gd",
	"res://scenes/objects/art/object_mesh_overhead_config.gd",
	"res://scenes/objects/art/object_mesh_room_config.gd",
	"res://scenes/objects/art/object_mesh_seat_config.gd",
	"res://scenes/objects/art/object_mesh_shell_config.gd",
	"res://scenes/objects/art/object_mesh_shop_config.gd",
	"res://scenes/objects/art/object_mesh_state_config.gd",
	"res://scenes/objects/art/object_mesh_storage_config.gd",
	"res://scenes/objects/art/object_mesh_street_config.gd",
	"res://scenes/objects/art/object_mesh_tech_config.gd",
]
## Every look the kinds' options give: [art id, size, art_opts, facing], and for a piece with an
## overhead part its `{ size, reach }` last.
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
	["tech", Vector2(150, 40), { "neon": "cyan" }, Vector2.DOWN],
	["tech", Vector2(90, 40), { "neon": "pink" }, Vector2.LEFT],
	["tech", Vector2(44, 60), { "kind": "server_rack" }, Vector2.DOWN],
	["clinic", Vector2(46, 32), { "kind": "tool_cart" }, Vector2.DOWN],
	["clinic", Vector2(100, 34), { "kind": "cyberware_shelf" }, Vector2.UP],
	["security", Vector2(120, 28), { "kind": "barricade" }, Vector2.DOWN],
	["security", Vector2(22, 22), { "kind": "scanner" }, Vector2.DOWN],
	["security", Vector2(100, 36), { "kind": "lockers" }, Vector2.DOWN],
	["shop", Vector2(110, 44), { "kind": "counter" }, Vector2.DOWN],
	["shop", Vector2(120, 40), { "kind": "aisle" }, Vector2.DOWN],
	["shop", Vector2(64, 36), { "kind": "fridge" }, Vector2.DOWN],
	["shop", Vector2(46, 34), { "kind": "snack" }, Vector2.LEFT],
	["noodle", Vector2(150, 34), { "kind": "bar" }, Vector2.DOWN],
	["noodle", Vector2(20, 20), { "kind": "stool" }, Vector2.DOWN],
	["noodle", Vector2(96, 64), { "kind": "booth" }, Vector2.DOWN],
	["noodle", Vector2(100, 20), { "kind": "menu" }, Vector2.DOWN],
	["stock", Vector2(46, 46), { "kind": "crates" }, Vector2.DOWN],
	["stock", Vector2(64, 56), { "kind": "pallet" }, Vector2.DOWN],
	["stock", Vector2(36, 32), { "kind": "safe" }, Vector2.DOWN],
	["street_prop", Vector2(40, 34), { "kind": "vending" }, Vector2.DOWN],
	["street_prop", Vector2(74, 26), { "kind": "bench" }, Vector2.DOWN],
	["street_prop", Vector2(26, 26), { "kind": "bin" }, Vector2.DOWN],
	["street_prop", Vector2(40, 18), { "kind": "grate" }, Vector2.DOWN],
	["street_prop", Vector2(44, 30), { "kind": "litter" }, Vector2.DOWN],
	["podium", Vector2(144, 20), {}, Vector2.DOWN],
	["shell_decor", Vector2(104, 20), { "kind": "rebar" }, Vector2.DOWN],
	["shell_decor", Vector2(70, 48), { "kind": "rubble" }, Vector2.DOWN],
	["shell_decor", Vector2(120, 52), { "kind": "scaffold" }, Vector2.DOWN],
	["shell_decor", Vector2(88, 40), { "kind": "cement" }, Vector2.DOWN],
	["shell_decor", Vector2(72, 46), { "kind": "stain" }, Vector2.DOWN],
	["decor", Vector2(30, 24), { "kind": "trash" }, Vector2.DOWN],
	["decor", Vector2(84, 14), { "kind": "cables" }, Vector2.DOWN],
	["decor", Vector2(60, 48), { "kind": "cable_nest" }, Vector2.DOWN],
	["decor", Vector2(40, 28), { "kind": "cardboard" }, Vector2.DOWN],
	["decor", Vector2(48, 30), { "kind": "puddle" }, Vector2.DOWN],
	["decor", Vector2(64, 7), { "kind": "neon_tube", "tone": "magenta" }, Vector2.DOWN],
	[
		"streetlight",
		Vector2(14, 14),
		{ "head": "cobra" },
		Vector2.DOWN,
		{ "size": Vector2(16, 40), "reach": 20.0 },
	],
	[
		"streetlight",
		Vector2(14, 14),
		{ "head": "sign" },
		Vector2.UP,
		{ "size": Vector2(24, 40), "reach": 20.0 },
	],
	[
		"streetlight",
		Vector2(14, 14),
		{ "head": "sign", "neon": "magenta" },
		Vector2.LEFT,
		{ "size": Vector2(16, 40), "reach": 20.0 },
	],
	[
		"awning",
		Vector2(8, 8),
		{ "kind": "awning" },
		Vector2.DOWN,
		{ "size": Vector2(120, 36), "reach": 18.0 },
	],
	[
		"awning",
		Vector2(8, 8),
		{ "kind": "hanging" },
		Vector2.RIGHT,
		{ "size": Vector2(26, 72), "reach": 36.0 },
	],
	["car", Vector2(130, 220), {}, Vector2.DOWN],
]


## A fingerprint of the rig `look` is shown by: the vertices and colours of every mesh on it, and
## with `identity` the resources themselves (two pieces that share their meshes have one).
func _fingerprint(look: Array, identity := false) -> int:
	var piece := Probe.new()
	piece.size = look[1]
	piece.look.art_opts = look[2]
	piece.look.facing = look[3]
	if look.size() > 4:
		piece.look.overhang = look[4]
	var rig: Node3D = ObjectMeshes.BUILDERS[look[0]].build(piece)
	var found: Array = []
	var nodes: Array = [rig]
	nodes.append_array(rig.get_children())
	for node in nodes:
		if node is MeshInstance3D and node.mesh != null and node.mesh.get_surface_count() == 0:
			found.append("empty")  # a retuned value can leave a part nothing to show
		elif node is MeshInstance3D and node.mesh != null:
			var arrays: Array = (node.mesh as ArrayMesh).surface_get_arrays(0)
			found.append([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_COLOR]])
			if identity:
				found.append(node.mesh.get_instance_id())
	rig.free()
	piece.free()
	return hash(found)


## The `static var`s of the holder script at `path` a retune can change, field -> value.
func _tunables_of(path: String) -> Dictionary:
	var holder: Object = load(path)
	var out := {}
	var pattern := RegEx.create_from_string("(?m)^static var (\\w+)")
	for found in pattern.search_all(FileAccess.get_file_as_string(path)):
		var field := found.get_string(1)
		if _retuned(holder.get(field)) != null:
			out[field] = holder.get(field)
	return out


## `value` changed the way a retune would (a number doubled and a bit more, a colour inverted, a
## vector, an array or a dictionary of them each changed); null for a value there is no retune of
## (a name, a flag).
func _retuned(value: Variant) -> Variant:
	if value is float or value is int:
		return value * 2 + 3
	if value is Color:
		return Color(1.0 - value.r, 1.0 - value.g, 1.0 - value.b, value.a)
	if value is Vector2:
		return value * 2.0 + Vector2.ONE
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_retuned(item) if _retuned(item) != null else item)
		return out
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _retuned(value[key]) if _retuned(value[key]) != null else value[key]
		return out
	return null


## Whether `field` of the holder at `path`, retuned, leaves the mesh of `look` what the empty cache
## builds: the warm cache must not answer with the mesh of the old value.
func _key_names(path: String, field: String, look: Array) -> bool:
	var holder: Object = load(path)
	var was: Variant = holder.get(field)
	MeshCache.clear()
	_fingerprint(look)
	holder.set(field, _retuned(was))
	var warm := _fingerprint(look)
	MeshCache.clear()
	var cold := _fingerprint(look)
	holder.set(field, was)
	return warm == cold


func test_every_tuning_value_a_furniture_mesh_reads_is_in_its_cache_key() -> void:
	var stale: Array[String] = []
	var paths := HOLDERS.duplicate()
	paths.append_array(_art_holders())
	for path: String in paths:
		for field: String in _tunables_of(path):
			for look: Array in LOOKS:
				if not _key_names(path, field, look):
					stale.append("%s.%s: %s %s" % [path.get_file(), field, look[0], look[2]])
	MeshCache.clear()
	assert_array(stale).override_failure_message(
		"not in the cache key of the mesh: %s" % [stale]
	).is_empty()


## The painters' holders (`ObjectArt*Config`): the colours and proportions a mesh reads off them
## as its painter does.
func _art_holders() -> Array:
	var out: Array = []
	for file in DirAccess.get_files_at("res://scenes/objects/art"):
		if file.begins_with("object_art_") and file.ends_with("_config.gd"):
			out.append("res://scenes/objects/art/%s" % file)
	return out


func test_every_look_builds_a_body_and_none_of_its_parts_is_empty() -> void:
	for look: Array in LOOKS:
		var piece := Probe.new()
		piece.size = look[1]
		piece.look.art_opts = look[2]
		piece.look.facing = look[3]
		if look.size() > 4:
			piece.look.overhang = look[4]
		var rig: Node3D = ObjectMeshes.BUILDERS[look[0]].build(piece)
		var nodes: Array = [rig]
		nodes.append_array(rig.get_children())
		for node in nodes:
			if node is MeshInstance3D:
				assert_int(node.mesh.get_surface_count()).override_failure_message(
					"%s %s: %s has no surface" % [look[0], look[2], node.name]
				).is_greater(0)
		rig.free()
		piece.free()


func test_pieces_of_one_look_share_their_meshes_and_a_turn_is_another_mesh() -> void:
	MeshCache.clear()
	for look: Array in LOOKS:
		assert_int(_fingerprint(look, true)).is_equal(_fingerprint(look, true))
	var sofa: Array = LOOKS[0]
	var turned: Array = [sofa[0], sofa[1], sofa[2], Vector2.LEFT]
	assert_int(_fingerprint(sofa)).is_not_equal(_fingerprint(turned))
	MeshCache.clear()


func test_beds_look_on_staggered_frames() -> void:
	var waits := {}
	for id in range(1000, 1000 + ObjectMeshStateConfig.occupied_every):
		waits[FurnitureBedRig.first_wait(id)] = true
		var wait := FurnitureBedRig.first_wait(id)
		assert_int(wait).is_equal(id % ObjectMeshStateConfig.occupied_every)
	assert_int(waits.size()).is_equal(ObjectMeshStateConfig.occupied_every)


## The body mesh of a rig built for `art` of `size` facing `facing`.
func _body_mesh(art: String, size: Vector2, facing: Vector2) -> ArrayMesh:
	var piece := Probe.new()
	piece.size = size
	piece.look.art_opts = {}
	piece.look.facing = facing
	var rig: FurnitureRig = ObjectMeshes.BUILDERS[art].build(piece)
	var mesh := rig.body.mesh as ArrayMesh
	rig.free()
	piece.free()
	return mesh


## The ground point (2D `x`, `y` as 3D `x`, `z`) the highest vertices of `mesh` average to.
func _top_centre(mesh: ArrayMesh) -> Vector2:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top := mesh.get_aabb().end.y
	var sum := Vector2.ZERO
	var count := 0
	for v in vertices:
		if v.y > top - 0.01:
			sum += Vector2(v.x, v.z)
			count += 1
	return sum / count


## Whether `box` (a mesh's bounds in the body's frame) lies inside a footprint of `size` centred
## on the origin.
func _inside(box: AABB, size: Vector2) -> bool:
	var half := size / 2.0 + Vector2(0.01, 0.01)
	return (
		box.position.x >= -half.x
		and box.end.x <= half.x
		and box.position.z >= -half.y
		and box.end.z <= half.y
	)


## `art` of `size` facing `facing`: inside its size, its highest part (a sofa's back, a fixture's
## frame) on the side of the footprint away from the front. Returns the mesh's vertices for the
## caller to compare.
func _turned_case(art: String, size: Vector2, facing: Vector2) -> PackedVector3Array:
	var mesh := _body_mesh(art, size, facing)
	var box := mesh.get_aabb()
	var at := "%s facing %s" % [art, facing]
	assert_bool(_inside(box, size)).override_failure_message(
		"%s is not inside its size %s: %s" % [at, size, box]
	).is_true()
	var top := _top_centre(mesh)
	assert_float(top.dot(facing)).override_failure_message(
		"%s has its highest part toward the front: %s" % [at, top]
	).is_less(-1.0)
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func test_a_sofa_and_a_wall_fixture_turn_to_every_facing() -> void:
	# [art, the piece's size facing down or up]: a wall fixture hangs at the back of its footprint
	var cases := [["sofa", Vector2(150, 70)], ["fixture", Vector2(44, 12)]]
	for case: Array in cases:
		var seen := {}
		for facing: Vector2 in [Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2.RIGHT]:
			var size: Vector2 = case[1]
			size = Vector2(size.y, size.x) if facing.x != 0.0 else size
			seen[hash([_turned_case(case[0], size, facing)])] = true
		assert_int(seen.size()).override_failure_message(
			"%s: the four facings are not four meshes" % case[0]
		).is_equal(4)
	MeshCache.clear()
