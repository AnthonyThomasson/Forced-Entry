extends GameTest
## The sun lights only the street, so what cannot shadow a street spot stays out of its shadow
## pass: it is on a render layer the sun's `shadow_caster_mask` leaves out. The oracle is the sky
## mask itself (`ToonLight.sky_reaches`), sampled along each left-out mesh's own shadow: none of it
## may be on the street, so leaving it out changes no pixel. What stands in the street casts; an
## awake rigid body, a character and a mesh no body holds always cast; a mesh a script moves into
## the street casts again; the camera and the other lights see every layer.

## The step (px) the shadow's footprint is sampled at.
const STEP := 3.0

var _view: SubViewport
var _lighting: WorldLighting3D


func describe() -> Dictionary:
	return {
		"name": "The sun's shadow pass draws only what can shadow the street",
		"description": "In a district, no mesh left out of the sun's pass can shadow a sunlit "
			+ "spot; street meshes, awake bodies, characters and loose meshes cast; a woken or "
			+ "moved mesh casts again.",
		"tags": ["lighting", "3d", "perf"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.district(4)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	_build(t)
	# every item and piece of the district is asleep well within this
	await t.seconds(6.0)
	var sun := _lighting.sun()
	var left_out := _indoor_bit()
	t.check(sun.shadow_caster_mask & left_out == 0, "the sun casts nothing from the indoor layer")
	t.check(sun.shadow_caster_mask & 1 == 1, "and casts from the layer meshes are on")
	t.check(sun.light_cull_mask & left_out != 0, "but lights it like any other")
	_check_left_out(t)
	await _check_woken(t)
	await _check_moved_and_loose(t)


## A view of the twins' world with the carried meshes and the 3D lighting, as Main's view has.
func _build(t: TestContext) -> void:
	_view = SubViewport.new()
	_view.world_3d = TwinSpace.of_world(t.world).find_world_3d()
	t.world.add_child(_view)
	var carrier := MeshCarrier.new()
	ObjectMeshes.register(carrier.builders)
	CharacterMeshes.register(carrier.builders)
	_view.add_child(carrier)
	carrier.carry(t.world)
	_lighting = WorldLighting3D.light(
		_view, t.world, 1, WorldGen.district_rooms(t.world.district)
	)


func _indoor_bit() -> int:
	return 1 << (LightingCostConfig.sun_indoor_layer - 1)


## The meshes of the twins' world that cast shadows.
func _meshes(t: TestContext) -> Array:
	var world := _view.find_world_3d()
	return t.world.get_tree().root.find_children("*", "MeshInstance3D", true, false).filter(
		func(m: MeshInstance3D) -> bool: return (
			m.is_inside_tree() and m.get_world_3d() == world
			and m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	)


func _out(mesh: MeshInstance3D) -> bool:
	return mesh.layers & _indoor_bit() != 0


## Whether the shadow of `mesh`'s box, thrown by the sun, touches a spot the sky reaches.
func _shadows_street(mesh: MeshInstance3D) -> bool:
	var box := mesh.global_transform * mesh.get_aabb()
	var unit := RenderConfig.unit
	var travel := -_lighting.sun().global_basis.z
	var foot := Rect2(
		Vector2(box.position.x, box.position.z) / unit, Vector2(box.size.x, box.size.z) / unit
	)
	var longest := maxf(box.end.y / unit, 0.0) / -travel.y
	var fall := Vector2(travel.x, travel.z) * longest
	var steps := maxi(1, ceili(fall.length() / STEP))
	for k in steps + 1:
		var at := Rect2(foot.position + fall * (float(k) / steps), foot.size)
		var y := at.position.y
		while true:
			var x := at.position.x
			while true:
				if ToonLight.sky_reaches(Vector2(x, y)):
					return true
				if x >= at.end.x:
					break
				x = minf(x + STEP, at.end.x)
			if y >= at.end.y:
				break
			y = minf(y + STEP, at.end.y)
	return false


func _check_left_out(t: TestContext) -> void:
	var meshes := _meshes(t)
	var out := meshes.filter(_out)
	t.require(out.size() > 300, "premise: much of the district is indoors (%d)" % out.size())
	var wrong := out.filter(_shadows_street)
	t.expect_eq(wrong.size(), 0, "no mesh left out of the sun's pass can shadow the street")
	var street := meshes.filter(
		func(m: MeshInstance3D) -> bool:
			var centre := m.global_transform * m.get_aabb().get_center()
			return ToonLight.sky_reaches(Vector2(centre.x, centre.z) / RenderConfig.unit)
	)
	t.require(street.size() > 20, "premise: meshes stand in the street (%d)" % street.size())
	t.expect_eq(street.filter(_out).size(), 0, "what stands in the street casts")
	for body: Node in t.world.get_tree().get_nodes_in_group(&"characters"):
		var twin := TwinSpace.twin_for(body) as Node
		if twin == null or not t.world.is_ancestor_of(body):
			continue
		for part: MeshInstance3D in twin.find_children("*", "MeshInstance3D", true, false):
			t.check(not _out(part), "a character's mesh always casts")


## A left-out mesh on a sleeping rigid body casts while the body is awake, and not after.
func _check_woken(t: TestContext) -> void:
	var found: MeshInstance3D = null
	var body: RigidBody3D = null
	for mesh: MeshInstance3D in _meshes(t).filter(_out):
		var at: Node = mesh.get_parent()
		while at != null and not at is RigidBody3D:
			at = at.get_parent()
		if at != null:
			found = mesh
			body = at
			break
	if not t.require(found != null, "premise: a left-out mesh rests on a rigid body"):
		return
	body.sleeping = false
	body.apply_central_impulse(Vector3.UP * body.mass * 40.0 * RenderConfig.unit)
	await t.frames(3)
	t.check(not body.sleeping, "premise: the body is awake")
	t.check(not _out(found), "its mesh casts while it moves")
	await t.seconds(8.0)
	t.require(body.sleeping, "premise: the body came to rest")
	t.check(_out(found), "and is left out again once it sleeps indoors")


## A held mesh a script moves into the street casts again; one under no body always casts; a new
## one on a static body is judged where it stands.
func _check_moved_and_loose(t: TestContext) -> void:
	var out := _meshes(t).filter(_out)
	var indoor: MeshInstance3D = out[0]
	var at := indoor.global_transform * indoor.get_aabb().get_center()
	var loose := MeshInstance3D.new()
	loose.mesh = BoxMesh.new()
	_view.add_child(loose)
	loose.global_position = at
	var still := StaticBody3D.new()
	_view.add_child(still)
	still.global_position = at
	var held := MeshInstance3D.new()
	held.mesh = BoxMesh.new()
	still.add_child(held)
	await t.frames(3)
	t.check(not _out(loose), "a mesh no body holds always casts")
	t.check(_out(held), "a new mesh on a static body indoors is left out")
	# onto open street: the point of the sky mask's first lit texel found along a line
	var street := _street_point(t)
	still.global_position = Vector3(street.x, 0.5, street.y) * RenderConfig.unit
	await t.frames(ceili(float(_meshes(t).size()) / LightingCostConfig.sun_recheck) + 120)
	t.check(not _out(held), "moved into the street, it casts again")
	loose.queue_free()
	still.queue_free()


## A spot the sky reaches.
func _street_point(t: TestContext) -> Vector2:
	var rect := ToonLight.sky_rect()
	var y := rect.position.y + 5.0
	while y < rect.end.y:
		var x := rect.position.x + 5.0
		while x < rect.end.x:
			if ToonLight.sky_reaches(Vector2(x, y)):
				return Vector2(x, y)
			x += 40.0
		y += 40.0
	t.check(false, "the district has sunlit ground")
	return Vector2.ZERO
