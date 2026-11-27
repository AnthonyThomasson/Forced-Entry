extends UnitSuite
## Native unit suite for the sun's casters (`sun_casters.gd`, `domain-lighting`) on a street and a
## house made by hand: the shadow's sweep (what stands deep in a house casts when its shadow falls
## out onto the street, and not when it falls short), and the meshes a rigid body is followed with
## (only those it still carries, however often its mesh was built again).

const SunCasters := preload("res://scenes/lighting/sun_casters.gd")
## A house, and the street beside it toward +x (px).
const HOUSE := Rect2(0.0, 0.0, 200.0, 200.0)
const STREET := Rect2(200.0, 0.0, 200.0, 200.0)
## The side (px) of the boxes judged, and how often the body's mesh is built again.
const SIDE := 20.0
const DENTS := 12


## The casters of a sun falling toward +x at 45 degrees (a shadow as long as a thing is tall).
func _casters() -> SunCasters:
	var sun := DirectionalLight3D.new()
	var casters := SunCasters.new()
	add_child(auto_free(sun))
	add_child(auto_free(casters))
	var streets: Array[Rect2] = [STREET]
	var houses: Array[Rect2] = [HOUSE]
	casters.watch(sun, streets, houses, Vector3(1.0, -1.0, 0.0).normalized())
	return casters


## A box `height` px tall standing on the floor, its low corner at `at` (px), in 3D units.
func _box(at: Vector2, height: float) -> AABB:
	var unit := RenderConfig.unit
	return AABB(Vector3(at.x, 0.0, at.y) * unit, Vector3(SIDE, height, SIDE) * unit)


func test_a_tall_thing_deep_in_a_house_casts_and_a_short_one_does_not() -> void:
	var casters := _casters()
	var at := Vector2(60.0, 90.0)
	# premise: the margins alone (the street's and the shadow's) do not reach the street from here
	assert_float(STREET.position.x - at.x - SIDE).is_greater(
		LightingCostConfig.sun_caster_margin * 2.0
	)
	assert_bool(casters.reaches_street(_box(at, 200.0))).override_failure_message(
		"a tall box's shadow falls onto the street"
	).is_true()
	assert_bool(casters.reaches_street(_box(at, 10.0))).override_failure_message(
		"a short box's shadow stays indoors"
	).is_false()


func test_a_body_dented_again_and_again_is_followed_with_the_meshes_it_has() -> void:
	var casters := _casters()
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	add_child(auto_free(body))
	var mesh: MeshInstance3D = null
	for i in DENTS:
		if mesh != null:
			mesh.free()
		mesh = MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		body.add_child(mesh)
		casters.settle()
	for asleep: bool in [true, false]:
		body.sleeping = asleep
		casters._process(0.0)
	assert_int(casters.carried(body)).is_equal(1)
