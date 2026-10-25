extends RigidBody2D
## Vehicles domain: a drivable vehicle (a car or a van, `kind`, tuned by its `VehicleConfig.kinds`
## row). The control layer: a rigid body on `PhysicsLayers.SOLID` that the physics engine moves and
## collides, driven by its `drive`, the bicycle model (vehicle_drive.gd), inside `_integrate_forces`
## from the drive intent its driver hands on. Its `cabin` (vehicle_cabin.gd) holds its doors
## (vehicle_door.gd) and seats, and the rides of the characters getting in and out
## (vehicle_boarding.gd, stepped by each character's CharacterVehicleUse). Drawing is
## vehicle_visuals.gd on the `Chassis` (under the occupants) and `Roof` (over them) children.
## Vehicles are found by the group `vehicles`.
##
## The drivable contract (interface 19): `doors()`, `seats()`, `driver()`, `board(character, door)`,
## `exit(character)`, `drive_input(...)`, and the reads `speed()`, `engine_state()`, `slip()`,
## `wheel_angle()`, `brake_lights()`, `view_zoom_out()`.
## It is also hittable like furniture (`get_surface` / `take_hit`: dents through Physics'
## Deformable, debris and a shove) and pushable through RigidBody2D's own `apply_impulse(v, at)` /
## `get_mass()`. Its contacts post crashes, and a character it strikes (directly, or through a piece
## of furniture pressed against it) is knocked back and hurt by the closing speed, the vehicle
## losing only the momentum the character and what it is pressed against take. The `vehicle`,
## `engine` and `skid` EventBus topics are posted here and by its parts (`post`).

const VehicleDrive = preload("res://scenes/vehicle/vehicle_drive.gd")
const VehicleBoarding = preload("res://scenes/vehicle/vehicle_boarding.gd")

## Which `VehicleConfig.kinds` row this is.
@export var kind: StringName = &"car"
## The body's paint.
@export var color: Color = Color(0.62, 0.13, 0.12)

## Its kind's `VehicleConfig.kinds` row.
var _row: Dictionary
## The driving model (`VehicleDrive`), stepped in `_integrate_forces`: the drive intent, the engine
## and the skids.
var drive := VehicleDrive.new(self)
## Its doors and seats and the rides through them (`VehicleCabin`), built in `_ready` from its row.
var cabin: VehicleCabin
## Records the dents.
var _deformable: Deformable
## Its contacts: the crashes, and the characters and furniture it strikes (`VehicleContacts`).
var _contacts := VehicleContacts.new(self)


func _ready() -> void:
	_row = VehicleConfig.kinds[kind]
	add_to_group(&"vehicles")
	# Before the characters each frame: a character struck at the last step is shoved before it
	# moves, so it moves off in this frame and is not met where it stood by the next step.
	process_physics_priority = -1
	var size: Vector2 = _row["size"]
	mass = _row["mass"]
	inertia = mass * (size.x * size.x + size.y * size.y) / 12.0
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector2.ZERO
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = PhysicsLayers.SOLID
	collision_mask = PhysicsLayers.SOLID
	var surface := PhysicsMaterial.new()
	surface.bounce = _row["bounce"]
	surface.friction = _row["friction"]
	physics_material_override = surface
	_build_collider()
	cabin = VehicleCabin.new(self, _row)
	_deformable = Deformable.new()
	_deformable.max_depth = VehicleCollisionConfig.dent_max_depth
	_deformable.allow_chunks = false
	_deformable.max_impacts = VehicleCollisionConfig.dent_max_impacts
	add_child(_deformable)


func _physics_process(delta: float) -> void:
	cabin.update(delta)
	_contacts.apply()
	drive.update_skid()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	_contacts.read(state)
	drive.step(state, _row)
	_contacts.remember(state)


# --- The drivable contract (interface 19) ------------------------------------------------


## The doors, world space: `[{ id, kind, seat, handle, open, hinge, angle, offset }]` (`open` 0..1,
## `angle` how far a swing or rear door is turned, `offset` how far a sliding door has rolled).
func doors() -> Array:
	return cabin.door_list().map(func(d): return d.info(self))


## The seats: `[{ id, occupant }]`, the occupant the character holding it (boarding, seated or
## getting out) or null.
func seats() -> Array:
	var out := []
	for id in cabin.seat_ids():
		out.append({ "id": id, "occupant": cabin.occupant(id) })
	return out


## Who holds the driver's seat (null when nobody).
func driver() -> Node:
	return cabin.occupant(&"driver")


## Start `character` boarding by door `door_id`: it walks to the door, which opens, and gets in to
## the seat behind it. Returns the ride for its CharacterVehicleUse to step, or null when that door
## cannot be used now: the vehicle moves at `board_max_speed` or faster, the seat is taken, or the
## door's swing (or the stand point beside it) is blocked.
func board(character: Node2D, door_id: StringName) -> RefCounted:
	var by := cabin.door(door_id)
	if (by == null
			or speed() >= VehicleBoardingConfig.board_max_speed
			or cabin.ride_of(character) != null
			or not cabin.is_free(by.seat)):
		return null
	if not by.is_clear(self, [get_rid(), character.get_rid()], character.radius):
		return null
	var ride := cabin.take_seat(character, by)
	character.add_collision_exception_with(self)
	return ride


## `character`, seated, asks to get out (it brakes or waits for the vehicle to slow first; with no
## clear door it stays in). False when it is not seated here.
func exit(character: Node2D) -> bool:
	var ride: VehicleBoarding = cabin.ride_of(character)
	if ride == null or not ride.is_seated():
		return false
	ride.request_exit()
	return true


## The drive intent from `character`'s keys: `throttle` (1 = W, -1 = S: brake, then reverse),
## `steer` (1 = right, relative to the vehicle) and `handbrake`. Only the driver drives.
func drive_input(character: Node2D, throttle: float, steer: float, handbrake: bool) -> void:
	if driver() != character or not drive.running:
		return
	drive.intent = { "throttle": throttle, "steer": steer, "handbrake": handbrake, "brake": false }
	if throttle != 0.0 or steer != 0.0:
		sleeping = false


## How fast it moves (px/s, unsigned).
func speed() -> float:
	return linear_velocity.length()


## The engine: `{ running, rpm, load }` (revs 0..1 of the redline with a gear-like rise and drop,
## load the throttle).
func engine_state() -> Dictionary:
	return { "running": drive.running, "rpm": drive.rpm, "load": drive.engine_load }


## How much it slides: 0 while the tyres grip, rising with the slide.
func slip() -> float:
	return drive.slip


## The front wheels' steering angle (rad, + = to the right), as they are drawn.
func wheel_angle() -> float:
	return drive.wheel_angle


## True while braking (the brake lights show).
func brake_lights() -> bool:
	return drive.braking


## How far a camera following someone aboard zooms out (V8): `VehicleDriveConfig.zoom_out` at the
## top speed, in proportion below it, none at rest.
func view_zoom_out() -> float:
	return VehicleDriveConfig.zoom_out * clampf(speed() / float(_row["top_speed"]), 0.0, 1.0)


# --- Hittable contract (interface 3) -----------------------------------------------------


## A metal body: high coverage, hard to shoot through.
func get_surface() -> Dictionary:
	return {
		"coverage": _row["coverage"],
		"penetration": _row["penetration"],
		"material": _row["material"],
		"color": color,
	}


## A hit dents the body where it struck, throws debris and shoves it at the contact point. A vehicle
## is never destroyed.
func take_hit(hit: HitInfo) -> void:
	apply_impulse(Physics.impact_impulse(hit), hit.position - global_position)
	_deformable.record(hit)
	Physics.spawn_debris(get_parent(), hit, get_surface())


## The dents (Deformable impacts, local), for the visuals.
func hit_marks() -> Array:
	return _deformable.impacts


# --- Vehicles-internal: what a ride and the visuals use ----------------------------------


## Half the body's length and width (px).
func half_size() -> Vector2:
	return (_row["size"] as Vector2) * 0.5


## The body's outline (local): its rectangle with chamfered corners. The collider, and what the
## visuals paint.
func outline() -> PackedVector2Array:
	var half := half_size()
	var c: float = _row["corner"]
	return PackedVector2Array([
		Vector2(half.x, -half.y + c), Vector2(half.x, half.y - c), Vector2(half.x - c, half.y),
		Vector2(-half.x + c, half.y), Vector2(-half.x, half.y - c), Vector2(-half.x, -half.y + c),
		Vector2(-half.x + c, -half.y), Vector2(half.x - c, -half.y),
	])


## The kind's tuning row.
func row() -> Dictionary:
	return _row


# --- Helpers -----------------------------------------------------------------------------


## Post a `vehicle` event at `stage`, at `where`, with `extra` fields.
func post(stage: StringName, where: Vector2, extra := {}) -> void:
	var data := { "position": where, "kind": kind, "stage": stage }
	data.merge(extra)
	EventBus.post(&"vehicle", data)


## The body's collider: its outline (built here, the runtime-shape convention).
func _build_collider() -> void:
	var shape := ConvexPolygonShape2D.new()
	shape.set_point_cloud(outline())  # The hull, wound the way the physics server expects.
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
