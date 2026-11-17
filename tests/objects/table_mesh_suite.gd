extends UnitSuite
## Native unit suite (pure logic) for the table's 3D mesh (`TableMesh`, Objects; #193 phase 2):
## how tall a table of a footprint stands (a spec: a side table is low, a piece's own `art_opts`
## height wins) and that every value the shape reads is in the mesh's cache key, so a retuned
## holder is another mesh and never a stale cached one. Each tuning case is one line.

const TableMesh := preload("res://scenes/objects/art/table_mesh.gd")
const Probe := preload("res://tests/_objects/furniture_piece_probe.gd")


## The mesh a table of `size` (and `opts`, its `art_opts`) is shown by now.
func _mesh_of(size: Vector2, opts := {}) -> Mesh:
	var piece := Probe.new()
	piece.size = size
	piece.look.art_opts = opts
	piece.look.art = "table"
	var rig := TableMesh.build(piece) as FurnitureRig
	var mesh := rig.body.mesh
	rig.free()
	piece.free()
	return mesh


func test_a_small_table_is_low_a_dining_table_standard_and_art_opts_decide() -> void:
	assert_float(TableMesh.height_of(Vector2(30, 30), {})).is_equal(22.0)  # a side table
	assert_float(TableMesh.height_of(Vector2(120, 70), {})).is_equal(31.0)  # a dining table
	assert_float(TableMesh.height_of(Vector2(30, 30), { "height": 18 })).is_equal(18.0)
	assert_float(TableMesh.height_of(Vector2(120, 70), { "height": 12.5 })).is_equal(12.5)


func test_a_pieces_height_is_the_mesh_it_gets() -> void:
	assert_float(_mesh_of(Vector2(30, 30)).get_aabb().size.y).is_equal_approx(22.0, 0.01)
	assert_float(_mesh_of(Vector2(120, 70)).get_aabb().size.y).is_equal_approx(31.0, 0.01)
	var coffee := _mesh_of(Vector2(70, 40), { "height": 16 })
	assert_float(coffee.get_aabb().size.y).is_equal_approx(16.0, 0.01)


func test_every_tuning_value_the_shape_reads_is_in_its_cache_key() -> void:
	# [field, a value that is not the default, a footprint the field matters for]
	var cases: Array = [
		[&"table_height", 40.0, Vector2(120, 70)],
		[&"table_low_height", 12.0, Vector2(30, 30)],
		[&"table_low_area", 500.0, Vector2(30, 30)],  # the side table is no longer small
		[&"table_top_thickness", 7.0, Vector2(120, 70)],
		[&"table_leg", 9.0, Vector2(120, 70)],
		[&"table_leg_inset", 8.0, Vector2(120, 70)],
	]
	var holder: Object = ObjectMeshConfig
	for tuned: Array in cases:
		var field: StringName = tuned[0]
		var size: Vector2 = tuned[2]
		var was: float = holder.get(field)
		var plain := _mesh_of(size)
		holder.set(field, tuned[1])
		var retuned := _mesh_of(size)
		holder.set(field, was)
		assert_bool(retuned == plain).override_failure_message(
			"%s is not in the table mesh's cache key" % field
		).is_false()
