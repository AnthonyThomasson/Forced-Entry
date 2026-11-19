extends RefCounted
## Vehicles domain: one door of a vehicle, in the vehicle's own frame (x forward, y toward its right
## side). It keeps the door's eased open amount, says where the door is as it opens (a `swing` door
## turns out about its front hinge, a `rear` door out behind about its back corner, a `slide` door
## rolls back along the body), where a character stands to use it and where the gap behind it is,
## and whether it is free to open: a shape query along its swing arc or slide track, and at the
## stand point. The vehicle steps it (`update`) and reads it out (`info`).

## How high (px) above the floor a door's swing column and the stand point's cylinder start: clear
## of a floor slab's top.
const SWEEP_FROM := 1.0
## How high (px) a door's swing column reaches for a vehicle whose twin has no top to read.
const SWEEP_HEIGHT := 40.0

## Its id in the kind's `doors` row (`front_left`, `side` ...).
var id: StringName
## `swing`, `slide` or `rear`.
var kind: StringName
## The seat behind it.
var seat: StringName
## Where it turns (a sliding door: its front edge), on the body's edge.
var hinge: Vector2
## Where it is pulled, on the body's edge, the door shut.
var handle: Vector2
## Hinge to handle (a sliding door: its length along the body).
var length: float
## How far (rad) a swing or rear door turns when fully open.
var open_angle: float
## Out of the body through this door (unit).
var outward: Vector2
## Which way the door turns as it opens (the sign of the angle), so its free edge goes outward.
var _turn := 1.0
## Closed 0 .. open 1, linear in time; `amount()` eases it.
var _progress := 0.0
## Where the progress is heading: 0 closing (or shut), 1 opening (or open).
var _target := 0.0


func _init(def: Dictionary) -> void:
	id = def["id"]
	kind = def["kind"]
	seat = def["seat"]
	hinge = def["hinge"]
	handle = def["handle"]
	open_angle = def.get("open_angle", 0.0)
	length = def.get("length", hinge.distance_to(handle))
	outward = Vector2.LEFT if kind == &"rear" else Vector2(0.0, signf(handle.y))
	_turn = signf((handle - hinge).cross(outward))


## Move the door toward its target by `delta` s. Returns true on the frame a closing door shuts (the
## slam).
func update(delta: float) -> bool:
	if _progress == _target:
		return false
	var time := (VehicleDoorConfig.slide_time
			if kind == &"slide"
			else (VehicleDoorConfig.open_time
					if _target > _progress
					else VehicleDoorConfig.close_time))
	_progress = move_toward(_progress, _target, delta / maxf(time, 0.01))
	return _progress == 0.0 and _target == 0.0


## Start opening; true when the door was shut (so it is the handle's click, not a door already on
## its way).
func open() -> bool:
	var was_shut := _progress == 0.0 and _target == 0.0
	_target = 1.0
	return was_shut


## Start closing.
func close() -> void:
	_target = 0.0


## How far open, 0 (shut) .. 1 (open): eased out of the progress, so it opens fast and settles, and
## gathers speed as it shuts.
func amount() -> float:
	return 1.0 - (1.0 - _progress) * (1.0 - _progress)


## True once fully open.
func is_open() -> bool:
	return _progress >= 1.0


## How far a swing or rear door is turned (rad, signed); 0 for a sliding door.
func angle() -> float:
	return 0.0 if kind == &"slide" else _turn * open_angle * amount()


## How far a sliding door has rolled (local px): back along the body, standing a little out from it;
## zero for the others.
func offset() -> Vector2:
	if kind != &"slide":
		return Vector2.ZERO
	var a := amount()
	return Vector2(
		-length * a,
		0.0,
	) + outward * VehicleDoorConfig.slide_pop * clampf(a * 4.0, 0.0, 1.0)


## The handle where the door is now (local).
func handle_now() -> Vector2:
	if kind == &"slide":
		return handle + offset()
	return hinge + (handle - hinge).rotated(angle())


## Where a character of `radius` stands to use the door (local): out from the body beyond its
## radius, and on past the handle (away from the hinge) until it is clear of the door's swing, so
## the door opens and shuts beside it. A sliding door's stand point is out from the front of its
## opening, clear of the track it rolls back along.
func stand_point(radius: float) -> Vector2:
	var out := radius + VehicleDoorConfig.stand_out
	if kind == &"slide":
		return handle + Vector2(-8.0, 0.0) + outward * out
	var along := (handle - hinge).normalized()
	var reach := length + radius + VehicleDoorConfig.clearance
	var past := maxf(4.0, sqrt(maxf(reach * reach - out * out, 0.0)) - length)
	return handle + along * past + outward * out


## The gap a character of `radius` steps into on its way to the seat (local): the middle of the
## door's opening, just outside the body.
func entry_point(radius: float) -> Vector2:
	var middle := (hinge + handle) * 0.5
	if kind == &"slide":
		middle = hinge + Vector2(-length * 0.5, 0.0)
	return middle + outward * radius * 0.4


## Whether the door can open for `rider`, a character of `radius` (it and the vehicle ignored):
## nothing solid (a wall, furniture, a character, another vehicle) is in its swing arc or slide
## track as high as the vehicle stands, nor at its stand point as high as a person. Asked of the
## twin space (interface 29): what stands in the way is what the 3D bodies fill.
func is_clear(vehicle: Node2D, rider: Node2D, radius: float) -> bool:
	var space := TwinSpace.space_of(vehicle)
	if space == null:
		return true
	var params := PhysicsShapeQueryParameters3D.new()
	params.collision_mask = PhysicsLayers.TWIN_ALL
	var ignored: Array[RID] = []
	for body: Object in [TwinSpace.twin_for(vehicle), TwinSpace.walker_of(rider)]:
		if body is CollisionObject3D:
			ignored.append((body as CollisionObject3D).get_rid())
	params.exclude = ignored
	var twin := TwinSpace.twin_for(vehicle)
	var high := TwinShapes.top_of(twin) if twin != null else SWEEP_HEIGHT
	params.shape = _sweep_shape(maxf(high, SWEEP_FROM + 1.0))
	params.transform = PlanSpace.lift_transform(vehicle.global_transform)
	if not space.intersect_shape(params, 1).is_empty():
		return false
	var body := CylinderShape3D.new()
	body.radius = radius * RenderConfig.unit
	body.height = BodyHeights.head_top(BodyHeights.STAND) - SWEEP_FROM
	params.shape = body
	params.transform = Transform3D(
		Basis(),
		PlanSpace.lift(vehicle.to_global(stand_point(radius)), SWEEP_FROM + body.height * 0.5),
	)
	return space.intersect_shape(params, 1).is_empty()


## The door as `doors()` reports it (world space): `{ id, kind, seat, handle, open, hinge, angle,
## offset }`.
func info(vehicle: Node2D) -> Dictionary:
	return {
		"id": id, "kind": kind, "seat": seat, "handle": vehicle.to_global(handle_now()),
		"open": amount(), "hinge": vehicle.to_global(hinge), "angle": angle(),
		"offset": vehicle.global_transform.basis_xform(offset()),
	}


## The ground the door sweeps (local): the sector its free edge turns through, a little longer than
## the door, or the strip beside the body that a sliding door rolls along, as a column from
## `SWEEP_FROM` up to `high` (px).
func _sweep_shape(high: float) -> ConvexPolygonShape3D:
	var points := PackedVector2Array()
	var clearance := VehicleDoorConfig.clearance
	if kind == &"slide":
		var depth := outward * (VehicleDoorConfig.slide_pop + 2.0 + clearance)
		var back := hinge + Vector2(-2.0 * length - clearance, 0.0)
		points = PackedVector2Array([hinge, back, back + depth, hinge + depth])
	else:
		var arm := (handle - hinge) * (1.0 + clearance / maxf(length, 1.0))
		points.append(hinge)
		var steps := 6
		for i in steps + 1:
			points.append(hinge + arm.rotated(_turn * open_angle * float(i) / steps))
	var column := PackedVector3Array()
	for point in points:
		column.append(PlanSpace.lift(point, SWEEP_FROM))
		column.append(PlanSpace.lift(point, high))
	var shape := ConvexPolygonShape3D.new()
	shape.points = column
	return shape
