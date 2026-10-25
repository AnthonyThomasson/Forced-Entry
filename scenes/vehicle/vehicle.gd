extends RigidBody2D
## Vehicles domain: a drivable vehicle (a car or a van, `kind`, tuned by its `VehicleConfig.kinds`
## row). The control layer: a rigid body on `PhysicsLayers.SOLID` that the physics engine moves and
## collides, driven by the bicycle model (vehicle_drive.gd) inside `_integrate_forces` from the
## drive intent its driver hands on. It owns its doors (vehicle_door.gd) and seats, and the rides of
## the characters getting in and out (vehicle_boarding.gd, stepped by each character's
## CharacterVehicleUse). Drawing is vehicle_visuals.gd on the `Chassis` (under the occupants) and
## `Roof` (over them) children. Vehicles are found by the group `vehicles`.
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

const VehicleDoor = preload("res://scenes/vehicle/vehicle_door.gd")
const VehicleDrive = preload("res://scenes/vehicle/vehicle_drive.gd")
const VehicleBoarding = preload("res://scenes/vehicle/vehicle_boarding.gd")

## Which `VehicleConfig.kinds` row this is.
@export var kind: StringName = &"car"
## The body's paint.
@export var color: Color = Color(0.62, 0.13, 0.12)

## Its kind's `VehicleConfig.kinds` row.
var _row: Dictionary
## Its doors, in the row's order.
var _doors: Array[VehicleDoor] = []
## Seat id -> who holds it (boarding into it, sitting in it or getting out of it), or null.
var _seats: Dictionary = {}
## Seat id -> the character on its way into it from another seat (a passenger sliding across to the
## wheel).
var _reserved: Dictionary = {}
## Character -> its ride (VehicleBoarding), from the E press to its last step out.
var _rides: Dictionary = {}
## The driving model (`VehicleDrive`), stepped in `_integrate_forces`: the drive intent, the engine
## and the skids.
var drive := VehicleDrive.new(self)
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
	for def: Dictionary in _row["doors"]:
		_doors.append(VehicleDoor.new(def))
	for id in _row["seats"]:
		_seats[id] = null
	_deformable = Deformable.new()
	_deformable.max_depth = VehicleCollisionConfig.dent_max_depth
	_deformable.allow_chunks = false
	_deformable.max_impacts = VehicleCollisionConfig.dent_max_impacts
	add_child(_deformable)


func _physics_process(delta: float) -> void:
	for d in _doors:
		if d.update(delta):
			post(&"slide_close" if d.kind == &"slide" else &"door_close", to_global(d.handle))
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
	return _doors.map(func(d): return d.info(self))


## The seats: `[{ id, occupant }]`, the occupant the character holding it (boarding, seated or
## getting out) or null.
func seats() -> Array:
	var out := []
	for id in _seats:
		out.append({ "id": id, "occupant": occupant(id) })
	return out


## Who holds the driver's seat (null when nobody).
func driver() -> Node:
	return occupant(&"driver")


## Start `character` boarding by door `door_id`: it walks to the door, which opens, and gets in to
## the seat behind it. Returns the ride for its CharacterVehicleUse to step, or null when that door
## cannot be used now: the vehicle moves at `board_max_speed` or faster, the seat is taken, or the
## door's swing (or the stand point beside it) is blocked.
func board(character: Node2D, door_id: StringName) -> RefCounted:
	var by := _door(door_id)
	if (by == null
			or speed() >= VehicleBoardingConfig.board_max_speed
			or _rides.has(character)
			or not is_free(by.seat)):
		return null
	if not by.is_clear(self, [get_rid(), character.get_rid()], character.radius):
		return null
	_seats[by.seat] = character
	var ride := VehicleBoarding.new(self, character, by)
	_rides[character] = ride
	character.add_collision_exception_with(self)
	return ride


## `character`, seated, asks to get out (it brakes or waits for the vehicle to slow first; with no
## clear door it stays in). False when it is not seated here.
func exit(character: Node2D) -> bool:
	var ride: VehicleBoarding = _rides.get(character)
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


## The door objects (VehicleDoor), for the visuals.
func door_list() -> Array[VehicleDoor]:
	return _doors


## Where seat `id` is (local).
func seat_point(id: StringName) -> Vector2:
	return _row["seats"][id]


## Who holds seat `id` (null when empty or freed).
func occupant(id: StringName) -> Node:
	var who: Variant = _seats.get(id)
	return who if is_instance_valid(who) else null


## Whether seat `id` is free: nobody holds it or is on the way into it.
func is_free(id: StringName) -> bool:
	return occupant(id) == null and not is_instance_valid(_reserved.get(id))


## Hold seat `id` for `character` while it slides across the bench to it.
func reserve(character: Node2D, id: StringName) -> void:
	_reserved[id] = character


## Move `character` to seat `id` (it has slid across the bench).
func change_seat(character: Node2D, id: StringName) -> void:
	for s in _seats:
		if _seats[s] == character:
			_seats[s] = null
	_seats[id] = character
	_reserved.erase(id)


## `character` gives up its seat and its ride (out, given up, or dead). A driver leaving cuts the
## engine.
func release(character: Node2D) -> void:
	for s in _seats:
		if _seats[s] == character:
			_seats[s] = null
			if s == &"driver":
				drive.stop_engine()
	for s in _reserved.keys():
		if _reserved[s] == character:
			_reserved.erase(s)
	_rides.erase(character)


## Open `which` (posting the handle's click the moment a shut door starts to open).
func open_door(which: VehicleDoor) -> void:
	if which.open():
		post(&"slide_open" if which.kind == &"slide" else &"door_open", to_global(which.handle))


## Close `which` (the slam is posted when it shuts).
func close_door(which: VehicleDoor) -> void:
	which.close()


## The door `character`, in `seat`, gets out by: `own` (the one it got in by) when clear, else the
## nearest clear door whose seat is its own or empty; null when none is clear.
func exit_door(character: Node2D, seat: StringName, own: VehicleDoor) -> VehicleDoor:
	var exclude: Array[RID] = [get_rid(), character.get_rid()]
	if own != null and own.seat == seat and own.is_clear(self, exclude, character.radius):
		return own
	var best: VehicleDoor = null
	var best_distance := INF
	for d in _doors:
		if d.seat != seat and not is_free(d.seat):
			continue
		var distance: float = character.global_position.distance_to(to_global(d.handle))
		if distance < best_distance and d.is_clear(self, exclude, character.radius):
			best = d
			best_distance = distance
	return best


# --- Helpers -----------------------------------------------------------------------------


## Post a `vehicle` event at `stage`, at `where`, with `extra` fields.
func post(stage: StringName, where: Vector2, extra := {}) -> void:
	var data := { "position": where, "kind": kind, "stage": stage }
	data.merge(extra)
	EventBus.post(&"vehicle", data)


## Door `id`, or null.
func _door(id: StringName) -> VehicleDoor:
	for d in _doors:
		if d.id == id:
			return d
	return null


## The body's collider: its outline (built here, the runtime-shape convention).
func _build_collider() -> void:
	var shape := ConvexPolygonShape2D.new()
	shape.set_point_cloud(outline())  # The hull, wound the way the physics server expects.
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
