class_name VehicleCabin extends RefCounted
## Vehicles domain: a vehicle's doors and seats and whose ride is whose (`docs/vehicles.md` V1-V4),
## its body's `cabin` part: the doors (vehicle_door.gd), who holds each seat or is on the way into
## it, and the rides of the characters getting in and out (vehicle_boarding.gd), which the body's
## `board` and `exit` start and end and each ride calls back. Built once in the body's `_ready`,
## from its row; it holds the body (a node, so no reference cycle) for its frame, its physics, its
## `drive` and its `post`.

const VehicleDoor = preload("res://scenes/vehicle/vehicle_door.gd")
const VehicleBoarding = preload("res://scenes/vehicle/vehicle_boarding.gd")

## The vehicle it belongs to.
var vehicle: RigidBody2D
## Its doors, in the row's order.
var _doors: Array[VehicleDoor] = []
## Seat id -> who holds it (boarding into it, sitting in it or getting out of it), or null.
var _seats: Dictionary = {}
## Seat id -> the character on its way into it from another seat (a passenger sliding across to the
## wheel).
var _reserved: Dictionary = {}
## Character -> its ride (VehicleBoarding), from the E press to its last step out.
var _rides: Dictionary = {}


func _init(body: RigidBody2D, row: Dictionary) -> void:
	vehicle = body
	for def: Dictionary in row["doors"]:
		_doors.append(VehicleDoor.new(def))
	for id in row["seats"]:
		_seats[id] = null


## Step the doors by `delta` s, posting the slam (or the slide's close) the frame one shuts.
func update(delta: float) -> void:
	for d in _doors:
		if d.update(delta):
			vehicle.post(
				&"slide_close" if d.kind == &"slide" else &"door_close",
				vehicle.to_global(d.handle),
			)


## The seat ids, in the row's order.
func seat_ids() -> Array:
	return _seats.keys()


## Seat `character` behind door `by` and start its ride (VehicleBoarding), which it returns.
func take_seat(character: Node2D, by: VehicleDoor) -> RefCounted:
	_seats[by.seat] = character
	var ride := VehicleBoarding.new(vehicle, character, by)
	_rides[character] = ride
	return ride


## `character`'s ride (VehicleBoarding), from the E press to its last step out, or null.
func ride_of(character: Node2D) -> VehicleBoarding:
	return _rides.get(character)


## The door objects (VehicleDoor), for the visuals.
func door_list() -> Array[VehicleDoor]:
	return _doors


## Where seat `id` is (local).
func seat_point(id: StringName) -> Vector2:
	return vehicle.row()["seats"][id]


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
				vehicle.drive.stop_engine()
	for s in _reserved.keys():
		if _reserved[s] == character:
			_reserved.erase(s)
	_rides.erase(character)


## Open `which` (posting the handle's click the moment a shut door starts to open).
func open_door(which: VehicleDoor) -> void:
	if which.open():
		vehicle.post(
			&"slide_open" if which.kind == &"slide" else &"door_open",
			vehicle.to_global(which.handle),
		)


## Close `which` (the slam is posted when it shuts).
func close_door(which: VehicleDoor) -> void:
	which.close()


## The door `character`, in `seat`, gets out by: `own` (the one it got in by) when clear, else the
## nearest clear door whose seat is its own or empty; null when none is clear.
func exit_door(character: Node2D, seat: StringName, own: VehicleDoor) -> VehicleDoor:
	var exclude: Array[RID] = [vehicle.get_rid(), character.get_rid()]
	if own != null and own.seat == seat and own.is_clear(vehicle, exclude, character.radius):
		return own
	var best: VehicleDoor = null
	var best_distance := INF
	for d in _doors:
		if d.seat != seat and not is_free(d.seat):
			continue
		var distance: float = character.global_position.distance_to(vehicle.to_global(d.handle))
		if distance < best_distance and d.is_clear(vehicle, exclude, character.radius):
			best = d
			best_distance = distance
	return best


## Door `id`, or null.
func door(id: StringName) -> VehicleDoor:
	for d in _doors:
		if d.id == id:
			return d
	return null
