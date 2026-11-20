extends GameTest
## A vehicle and a character carry their meshes on their twins (#194 del2d-b3, interface 27 and 29):
## a car's mesh is a child of its `VehicleBody` with no transform of its own and a character's a
## child of its `CharacterTwin` that holds only the turn of its facing; both stand where the 2D
## body stands every frame of a drive and a walk, and the mirror writes nothing for them
## (`written` is 0). The mirror keeps the shown rules (a driver in a seat is hidden), the mesh's own
## hooks and a corpse's mesh. A world no view looks at builds no mesh.

const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
const CAR_AT := Vector2(500, 400)
const WALKER_AT := Vector2(150, 150)
const DRIVER_AT := Vector2(420, 400)
## Plan px and radians a mesh may stand off the 2D body.
const NEAR := 0.05
## Plan px a 2D footprint may trail its twin beyond the step of travel its speed gives
## (`speed / 60`): the footprint is the twin's pose a physics step ago, no more.
const TRAIL_SLACK := 1.0
const TURNED := 0.08


func describe() -> Dictionary:
	return {
		"name": "A vehicle and a character carry their meshes on their twins",
		"description": "With a view, a car's mesh is a child of its VehicleBody (no transform of "
			+ "its own), a walking, turning character's a child of its CharacterTwin holding only "
			+ "its facing; both at the 2D body's pose every frame, the mirror writes nothing; a "
			+ "driver's mesh hides while seated; a corpse's mesh stays; no view, no mesh.",
		"tags": ["mirror", "render3d", "twins", "3d", "vehicle", "character", "carriers"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 900), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", CAR_AT)
	s.actor(&"walker", &"puppet", WALKER_AT)
	s.actor(&"driver", &"puppet", DRIVER_AT)
	s.actor(&"victim", &"puppet", Vector2(150, 700))


func run(t: TestContext) -> void:
	await t.frames(3)
	var car := t.vehicle(&"car") as Node2D
	var walker := t.actor(&"walker") as Node2D
	if not t.require(
		TwinSpace.twin_for(car) is VehicleBody and TwinSpace.twin_for(walker) is CharacterTwin,
		"premise: a car and a character have 3D bodies",
	):
		return
	for body: Node in [car, walker]:
		t.check(
			TwinSpace.twin_for(body).find_children("*", "MeshInstance3D", true, false).is_empty(),
			"with no view %s's twin carries no mesh" % body.name,
		)
	var mirror := _view(t)
	mirror.mirror(t.world)
	await t.frames(4)
	_check_carried(t, mirror, car, true)
	_check_carried(t, mirror, walker, false)
	await _check_walk(t, mirror, walker)
	await _check_retwinned(t, mirror, walker)
	await _check_drive(t, mirror, car)
	_check_seated(t, mirror, car, t.actor(&"driver") as Node2D)
	await _check_dead(t, mirror, t.actor(&"victim") as Node2D)


func _view(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.world_3d = TwinSpace.of_world(t.world).find_world_3d()  # drawn in the twins' world
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	VehicleMeshes.register(mirror.builders)
	CharacterMeshes.register(mirror.builders)
	view.add_child(mirror)
	return mirror


## How far (px) mesh `mesh` stands off its body's twin (the truth of where the body is) and how much
## (rad) it is turned off the 2D body's turn. The 2D body is the twin's footprint, written from it
## a physics step later for a vehicle, so it may trail the mesh by one step of travel (its speed
## over 60, and `TRAIL_SLACK`).
func _off(mesh: Node3D, body: Node2D) -> Vector2:
	var twin := TwinSpace.twin_for(body)
	var want := Basis(Vector3.UP, -body.global_rotation)
	var trail := mesh.global_position.distance_to(PlanSpace.lift(body.global_position))
	var apart := mesh.global_position.distance_to(twin.global_position)
	var step := float(body.call(&"speed")) / 60.0 if body.has_method(&"speed") else 0.0
	return Vector2(
		apart if trail <= step + TRAIL_SLACK else INF,
		mesh.global_basis.z.angle_to(want.z),
	)


func _check_carried(t: TestContext, mirror: WorldMirror, body: Node2D, bare: bool) -> void:
	var twin := TwinSpace.twin_for(body)
	var mesh := mirror.mesh_of(body)
	if not t.require(
		mesh != null and twin != null,
		"premise: %s has a mesh and a twin" % body.name,
	):
		return
	t.check(mesh.get_parent() == twin, "%s's mesh is a child of its twin" % body.name)
	t.check(
		mesh.is_inside_tree() and mesh.visible,
		"%s's mesh is in the tree and shown" % body.name,
	)
	t.expect_eq(mirror.proxies_of(body).size(), 1, "%s has one mesh" % body.name)
	if bare:
		t.check(
			mesh.transform.is_equal_approx(Transform3D.IDENTITY),
			"%s's mesh has no transform of its own" % body.name,
		)
	else:
		t.check(mesh.position.is_zero_approx(), "%s's mesh stands on its twin" % body.name)
	var off := _off(mesh, body)
	t.check(off.x < NEAR and off.y < TURNED, "%s's mesh is at its 2D pose" % body.name)


## A character walked and turned: the mesh is at the body's pose (its place and facing) every frame
## and the mirror writes nothing.
func _check_walk(t: TestContext, mirror: WorldMirror, walker: Node2D) -> void:
	var puppet := t.puppet(&"walker")
	puppet.walk_to(WALKER_AT + Vector2(300, 200))
	var off := 0
	var written := 0
	var moved := 0.0
	var start := walker.global_position
	for _i in 90:
		await t.frames(1)
		var mesh := mirror.mesh_of(walker)
		var gap := _off(mesh, walker)
		if gap.x > NEAR or gap.y > TURNED:
			off += 1
		written += mirror.written
		moved = maxf(moved, walker.global_position.distance_to(start))
	t.require(moved > 60.0, "premise: it walked (%.0f px)" % moved)
	t.expect_eq(off, 0, "the character's mesh was at its pose every frame of the walk")
	t.expect_eq(written, 0, "the mirror wrote nothing while it walked")
	walker.global_rotation = 1.2  # a script turns the 2D body: the mesh turns with it
	await t.frames(3)
	var after := _off(mirror.mesh_of(walker), walker)
	t.check(after.x < NEAR and after.y < TURNED, "a character turned by a script is drawn turned")
	t.check(
		mirror.mesh_of(walker).get_parent() == TwinSpace.twin_for(walker),
		"still its twin's child",
	)


## A character twinned again (its old twin is freed) is drawn turned at once, the frame the new twin
## is made (the new twin holds no turn: the mirror puts its facing on it), and a mirror pointed at
## another world leaves the old twin space's signal alone.
func _check_retwinned(t: TestContext, mirror: WorldMirror, walker: Node2D) -> void:
	var old := TwinSpace.twin_for(walker)
	walker.global_rotation += 1.3  # turned this frame: the mesh has not been written yet
	t.check(_off(mirror.mesh_of(walker), walker).y > TURNED, "premise: the mesh holds the old turn")
	TwinSpace.retwin(walker)
	var at_once := TwinSpace.twin_for(walker)
	var mesh := mirror.mesh_of(walker)
	t.check(
		at_once != old and mesh.get_parent() == at_once,
		"premise: its mesh moved to the new twin",
	)
	t.check(_off(mesh, walker).y < TURNED, "and is turned the frame the twin is made")
	var twins := TwinSpace.of_world(t.world)
	# a new twin that stands upright (a character's twin never turns): the handler puts the facing
	# on the mesh itself
	at_once.global_basis = Basis.IDENTITY
	t.check(_off(mesh, walker).y > TURNED, "premise: an upright twin leaves the mesh unturned")
	twins.retwinned.emit(walker, old)
	t.check(_off(mesh, walker).y < TURNED, "a retwinned character's mesh is turned by the handler")
	var listening := twins.retwinned.get_connections().size()
	var bare := Node2D.new()
	t.world.get_parent().add_child(bare)
	mirror.mirror(bare)  # a world of no twin space: the mirror leaves this one's signal
	t.expect_eq(
		twins.retwinned.get_connections().size(), listening - 1, "a re-pointed mirror disconnects"
	)
	bare.queue_free()
	mirror.mirror(t.world)  # and listens again
	t.expect_eq(twins.retwinned.get_connections().size(), listening, "and listens again")
	await t.frames(2)


## A car driven forward and round: its mesh is its twin's pose every frame.
func _check_drive(t: TestContext, mirror: WorldMirror, car: Node2D) -> void:
	var puppet := t.puppet(&"driver")
	if not t.require(
		await VehicleRide.board_by(t, &"driver", car, &"front_left"), "premise: the driver boards"
	):
		return
	var off := 0
	var written := 0
	var start := car.global_position
	var far := 0.0
	var turned := 0.0
	for i in 150:
		puppet.drive(1.0, 0.0 if i < 50 else 0.7, false)
		await t.frames(1)
		var mesh := mirror.mesh_of(car)
		var gap := _off(mesh, car)
		if gap.x > NEAR or gap.y > TURNED or mesh.get_parent() != TwinSpace.twin_for(car):
			off += 1
		written += mirror.written
		far = maxf(far, car.global_position.distance_to(start))
		turned = maxf(turned, absf(car.global_rotation))
	puppet.drive(0.0, 0.0, false)
	t.require(
		far > 80.0 and turned > 0.2,
		"premise: the car drove (%.0f px, %.2f rad)" % [far, turned],
	)
	t.expect_eq(off, 0, "the car's mesh was at its pose every frame of the drive")
	t.expect_eq(written, 0, "the mirror wrote nothing while it drove")


## A character in a seat has no circle that counts: the shown rules hide its mesh (it stays on its
## twin).
func _check_seated(t: TestContext, mirror: WorldMirror, car: Node2D, driver: Node2D) -> void:
	var mesh := mirror.mesh_of(driver)
	if not t.require(mesh != null, "premise: the driver has a mesh"):
		return
	t.check(not mesh.visible, "a seated character's mesh is hidden")
	t.check(mesh.get_parent() == TwinSpace.twin_for(driver), "and stays on its twin")
	t.check(is_instance_valid(car), "premise: the car stands")


## A character that dies keeps its mesh (the corpse's), on the twin that goes with the body.
func _check_dead(t: TestContext, mirror: WorldMirror, victim: Node2D) -> void:
	var mesh := mirror.mesh_of(victim)
	if not t.require(mesh != null, "premise: the victim has a mesh"):
		return
	var count := mirror.count
	victim.set("health", 1.0)
	victim.call(&"take_damage", 1000.0)
	await t.seconds(1.0)
	t.check(is_instance_valid(mesh) and mesh.is_inside_tree(), "a corpse's mesh is still there")
	t.expect_eq(mirror.count, count, "and counted")
	var apart := PlanSpace.plan_of(mesh.global_position).distance_to(victim.global_position)
	t.check(apart < 1.0, "and it stands where the body lies (%.1f px apart)" % apart)
