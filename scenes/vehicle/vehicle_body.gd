class_name VehicleBody
extends RigidBody3D
## Vehicles domain, the 3D body of a vehicle (D13,
## `docs/adr/0014-twin-staging-and-plan-space.md`): a `RigidBody3D` in the twin space (`TwinSpace`,
## interface 29), locked upright (it cannot roll or pitch: it turns about up and slides on the
## floor, gravity and the floor under it), shaped from the vehicle's real body (`VehicleTwins`: the
## outline up to the belt, the cabin on up to the roof). It is the vehicle's truth: the driving
## model (`VehicleDrive`) steps in its `_integrate_forces`, in plan space as it always did (the same
## bicycle, the same numbers), and the 2D body (`Vehicle`, a plain `Node2D` plan handle) follows it,
## written from it each frame by the twin space (`TwinSpace.leader_of`), so the doors, the seats and
## the ride go on reading the handle's transform.
##
## What it meets, Jolt solves: a wall, a free piece of furniture (two free bodies: the piece is
## pushed on, and the bumper's blow on it, `VehicleContacts`, tips a tall thin one over where a low
## heavy one only slides), another vehicle. A character it does not collide with in 3D: it is never
## stopped dead by one (`docs/vehicles.md` V6); what a character is struck by, the momentum it
## takes, the harm and the crashes are judged outside the step by shape queries (`VehicleContacts`),
## never by Jolt's contact events, which arrive in a different count and order run to run.

## The 2D vehicle this is the body of.
var _vehicle: Node2D


## A body for `of` (a `Vehicle`): its mass, inertia, grip and locks set. The shapes are added by
## the builder (`VehicleTwins`).
func _init(of: Node2D = null) -> void:
	_vehicle = of
	collision_layer = PhysicsLayers.TWIN_VEHICLE
	collision_mask = (
		PhysicsLayers.TWIN_WORLD
		| PhysicsLayers.TWIN_VEHICLE
		| PhysicsLayers.TWIN_GROUND
	)
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	gravity_scale = VehicleCollisionConfig.gravity * RenderConfig.unit / float(
		ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	can_sleep = true
	continuous_cd = PhysicsImpactConfig.body_continuous_cd
	if of == null:
		return
	var row: Dictionary = of.get("row")
	var size: Vector2 = row["size"]
	mass = row["mass"]
	var yaw := mass * (size.x * size.x + size.y * size.y) / 12.0
	inertia = Vector3(yaw, yaw, yaw)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	var heights: Dictionary = VehicleMeshConfig.heights[of.get("kind")]
	center_of_mass = Vector3(0.0, float(heights["belt"]) * 0.5 * RenderConfig.unit, 0.0)
	# the tyres hold it on the floor through the drive's own model, not the floor's friction
	var grip := PhysicsMaterial.new()
	grip.friction = 0.0
	grip.bounce = row["bounce"]
	physics_material_override = grip


## The 2D vehicle this is the body of.
func vehicle() -> Node2D:
	return _vehicle


## Called by the twin space as it takes the vehicle over: the 2D body is the footprint (a
## body only the twin space moves). A parked vehicle is asleep: it costs Jolt nothing. One whose
## engine already runs (it was started before this body was built) keeps what the 2D vehicle was
## told: it may not sleep and it is awake.
func take_over(footprint: Node2D) -> void:
	can_sleep = bool(footprint.get("can_sleep"))
	sleeping = can_sleep and not _vehicle.drive.running


## The drive's step, in plan space, then what it ended the step at, for the contacts of the next
## (`VehicleContacts.remember`).
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_vehicle.drive.step(state, _vehicle.row)
	_vehicle.contacts.remember(state)


## Shove the vehicle: `impulse` (plan space, as `apply_impulse`'s) at the point `at` px from its
## origin (world orientation; zero is the origin), `height` px above the floor (a negative height is
## its centre of mass). Locked upright, only the plan part of the shove turns it (a yaw about up) or
## moves it: a blow at the roof does not lean it.
func push(impulse: Vector2, at: Vector2 = Vector2.ZERO, height: float = -1.0) -> void:
	var lift := impulse * RenderConfig.unit
	var offset := Vector3(at.x, 0.0, at.y) * RenderConfig.unit
	var centre := global_transform.basis * center_of_mass
	offset.y = centre.y if height < 0.0 else height * RenderConfig.unit - global_position.y
	apply_impulse(Vector3(lift.x, 0.0, lift.y), offset)


## The vehicle's velocity in plan space (px/s), as the physics server has it now, shoves given this
## frame included.
func plan_velocity() -> Vector2:
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	return PlanSpace.plan_of(state.linear_velocity if state != null else linear_velocity)


## Wake the body now. A body woken by a script (not by a contact) is not reported as woken by the
## engine, so the twin space, which follows a sleeping body only until it sleeps, is told here.
func wake() -> void:
	if sleeping:
		sleeping = false
		sleeping_state_changed.emit()


## Set the velocity in plan space (px/s), keeping the vertical part: the floor holds it up.
func set_plan_velocity(velocity: Vector2) -> void:
	linear_velocity = Vector3(velocity.x, linear_velocity.y, velocity.y) * RenderConfig.unit
	wake()


## How fast it turns about up (rad/s, a 2D body's sign: clockwise on the y-down plan is positive).
func plan_spin() -> float:
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	return -(state.angular_velocity.y if state != null else angular_velocity.y)


## Set the turn about up (rad/s, a 2D body's sign).
func set_plan_spin(spin: float) -> void:
	angular_velocity = Vector3(0.0, -spin, 0.0)
	wake()


## How much one unit of impulse turns the vehicle about up (the inverse of its moment of inertia
## about up, as the engine has it): 0 for a body not in the world yet.
func inverse_yaw_inertia() -> float:
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	return state.inverse_inertia_tensor.y.y if state != null else 0.0


## How high (px) its centre of mass is above the floor now.
func centre_height() -> float:
	return (global_transform * center_of_mass).y / RenderConfig.unit
