extends AnimatableBody2D
## Vehicles domain: a drivable vehicle (a car or a van, `kind`, tuned by its `VehicleConfig.kinds`
## row). The control layer. Its truth is a free 3D body locked upright (`VehicleBody`, in the twin
## space, interface 29: `TwinSpace.leader_of`), which the physics engine moves and collides, driven
## by this vehicle's `drive`, the bicycle model (vehicle_drive.gd), inside the body's
## `_integrate_forces` from the drive intent its driver hands on. This node is the 2D footprint, a
## kinematic body on `PhysicsLayers.SOLID` that the twin space writes from the 3D body each frame,
## so the characters that still walk in 2D are stopped by it and everything that reads where a
## vehicle is reads it here; its `linear_velocity`, `angular_velocity`, `mass`, `apply_impulse` and
## `sleeping` are the old rigid body's reads and writes, answered by the 3D body. Its `cabin`
## (vehicle_cabin.gd) holds its doors (vehicle_door.gd) and seats, and the rides of the characters
## getting in and out (vehicle_boarding.gd, stepped by each character's CharacterVehicleUse). The 3D
## mirror shows it (`VehicleMeshRig`, `art/`).
## Vehicles are found by the group `vehicles`.
##
## The drivable contract (interface 19): `doors()`, `seats()`, `driver()`, `board(character, door)`,
## `exit(character)`, `drive_input(...)`, and the reads `speed()`, `engine_state()`, `slip()`,
## `wheel_angle()`, `brake_lights()`, `view_zoom_out()`.
## It is also hittable like furniture (`get_surface` / `take_hit`: dents through Physics'
## Deformable, debris and a shove) and pushable through `apply_impulse(v, at)` / `get_mass()`
## (`Knockback.push` is the way to shove it at a height). Its contacts post crashes, and a character
## it strikes (directly, or through a piece of furniture pressed against it) is knocked back and
## hurt by the closing speed, the vehicle losing only the momentum the character and what it is
## pressed against take. A piece of furniture it meets is a free 3D body too: the two are solved by
## the physics engine. The `vehicle`,
## `engine` and `skid` EventBus topics are posted here and by its parts (`post`).

const VehicleDrive = preload("res://scenes/vehicle/vehicle_drive.gd")
const VehicleBoarding = preload("res://scenes/vehicle/vehicle_boarding.gd")

## Which `VehicleConfig.kinds` row this is.
@export var kind: StringName = &"car"
## The body's paint.
@export var color: Color = Color(0.62, 0.13, 0.12)

## Its kind's `VehicleConfig.kinds` row.
var row: Dictionary
## The driving model (`VehicleDrive`), stepped in `_integrate_forces`: the drive intent, the engine
## and the skids.
var drive := VehicleDrive.new(self)
## Its doors and seats and the rides through them (`VehicleCabin`), built in `_ready` from its row.
var cabin: VehicleCabin
## Records the dents.
var _deformable: Deformable
## Its contacts: the crashes, and the characters and furniture it strikes (`VehicleContacts`).
var contacts := VehicleContacts.new(self)
## Its mass (kg-ish: the kind's row), as the old rigid body had it.
var mass := 1.0
## The engine runs: the body may not sleep (the wheels and revs follow the driver even at rest).
var can_sleep := true:
	set(value):
		can_sleep = value
		var lead := TwinSpace.leader_of(self)
		if lead != null:
			lead.can_sleep = value
## Its velocity in plan space (px/s): the 3D body's, zero before the twin space has built that. A
## write sets it (and wakes the body).
var linear_velocity: Vector2:
	get:
		var lead := _lead()
		return lead.call(&"plan_velocity") if lead != null else Vector2.ZERO
	set(value):
		var lead := _lead()
		if lead != null:
			lead.call(&"set_plan_velocity", value)
## How fast it turns about up (rad/s, clockwise on the plan positive). A write sets it.
var angular_velocity: float:
	get:
		var lead := _lead()
		return lead.call(&"plan_spin") if lead != null else 0.0
	set(value):
		var lead := _lead()
		if lead != null:
			lead.call(&"set_plan_spin", value)
## Whether the body is asleep (a parked vehicle is). A write to false wakes it.
var sleeping: bool:
	get:
		var lead := _lead()
		return lead.sleeping if lead != null else true
	set(value):
		var lead := _lead()
		if lead == null:
			return
		if value:
			lead.sleeping = true
		else:
			lead.call(&"wake")


func _enter_tree() -> void:
	# a plan handle the twin space twins (and the game finds bodies by)
	add_to_group(TwinSpace.BODIES)
	add_to_group(TwinSpace.HARD)


func _ready() -> void:
	row = VehicleConfig.kinds[kind]
	add_to_group(&"vehicles")
	# Before the characters each frame: a character struck at the last step is shoved before it
	# moves, so it moves off in this frame and is not met where it stood by the next step.
	process_physics_priority = -1
	mass = row["mass"]
	sync_to_physics = false  # the twin space writes the footprint: no velocity is derived from it
	collision_layer = PhysicsLayers.SOLID
	collision_mask = PhysicsLayers.SOLID
	_build_collider()
	cabin = VehicleCabin.new(self, row)
	_deformable = Deformable.new()
	_deformable.max_depth = VehicleCollisionConfig.dent_max_depth
	_deformable.allow_chunks = false
	_deformable.max_impacts = VehicleCollisionConfig.dent_max_impacts
	add_child(_deformable)


func _physics_process(delta: float) -> void:
	cabin.update(delta)
	contacts.read()
	contacts.apply()
	drive.update_skid()
	# A vehicle under way is not remembered by the player's view; one parked is.
	ViewLayers.set_moving(self, speed() > VehicleDriveConfig.stop_speed)


## Its mass, as the pushable contract reads it.
func get_mass() -> float:
	return mass


## Shove it by `impulse` (plan space) at `at` px from its origin: the pushable contract. Through
## `Knockback.push`, at its centre's height.
func apply_impulse(impulse: Vector2, at: Vector2 = Vector2.ZERO) -> void:
	var lead := _lead()
	if lead != null:
		lead.call(&"push", impulse, at, -1.0)


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


## Whether `character` could board by door `door_id` now: the vehicle moves slower than
## `board_max_speed`, the character is not riding, the seat behind the door is free and the door's
## swing (and the stand point beside it) is clear. Changes nothing.
func can_board(character: Node2D, door_id: StringName) -> bool:
	var by := cabin.door(door_id)
	return (by != null
			and speed() < VehicleBoardingConfig.board_max_speed
			and cabin.ride_of(character) == null
			and cabin.is_free(by.seat)
			and by.is_clear(self, character, character.radius))


## Start `character` boarding by door `door_id`: it walks to the door, which opens, and gets in to
## the seat behind it. Returns the ride for its CharacterVehicleUse to step, or null when that door
## cannot be used now (`can_board`).
func board(character: Node2D, door_id: StringName) -> RefCounted:
	if not can_board(character, door_id):
		return null
	var ride := cabin.take_seat(character, cabin.door(door_id))
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
	return VehicleDriveConfig.zoom_out * clampf(speed() / float(row["top_speed"]), 0.0, 1.0)


# --- Hittable contract (interface 3) -----------------------------------------------------


## A metal body, hard to shoot through.
func get_surface() -> Dictionary:
	return {
		"penetration": row["penetration"],
		"material": row["material"],
		"color": color,
	}


## A hit dents the body where it struck, throws debris and shoves it at the contact point. A vehicle
## is never destroyed.
func take_hit(hit: HitInfo) -> void:
	Knockback.push(self, Physics.impact_impulse(hit), hit.position - global_position, hit.height)
	_deformable.record(hit)
	Physics.spawn_debris(get_parent(), hit, get_surface())


## The dents (Deformable impacts, local), for the 3D body.
func hit_marks() -> Array:
	return _deformable.impacts


# --- Vehicles-internal: what a ride and the 3D body use ----------------------------------


## The body's outline (local): its rectangle with chamfered corners. The collider, and what the
## 3D body is built on.
func outline() -> PackedVector2Array:
	var half: Vector2 = (row["size"] as Vector2) * 0.5
	var c: float = row["corner"]
	return PackedVector2Array([
		Vector2(half.x, -half.y + c), Vector2(half.x, half.y - c), Vector2(half.x - c, half.y),
		Vector2(-half.x + c, half.y), Vector2(-half.x, half.y - c), Vector2(-half.x, -half.y + c),
		Vector2(-half.x + c, -half.y), Vector2(half.x - c, -half.y),
	])


# --- Helpers -----------------------------------------------------------------------------


## Post a `vehicle` event at `stage`, at `where`, with `extra` fields.
func post(stage: StringName, where: Vector2, extra := {}) -> void:
	var data := { "position": where, "kind": kind, "stage": stage }
	data.merge(extra)
	EventBus.post(&"vehicle", data)


## The 3D body that leads this vehicle (`TwinSpace.leader_of`), or null before the twin space has
## built it.
func _lead() -> RigidBody3D:
	return TwinSpace.leader_of(self)


## The body's collider: its outline (built here, the runtime-shape convention).
func _build_collider() -> void:
	var shape := ConvexPolygonShape2D.new()
	shape.set_point_cloud(outline())  # The hull, wound the way the physics server expects.
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
