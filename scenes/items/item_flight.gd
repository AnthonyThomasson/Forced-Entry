class_name ItemFlight
extends RefCounted
## Items domain: the 3D flight of a small thing let go into the world (a thrown grenade, a dropped
## weapon), flown in the twin 3D space (`TwinSpace`, interface 29): under gravity, swept each
## physics frame with a sphere through the real walls, furniture, doors, vehicles and bodies,
## bounced off what it strikes, rolled and skidded on a floor or on top of a piece, until it lies
## still. One stepper for the node (`ThrownGrenade`, `DroppedItem`) and for the planner
## (`GrenadeArc`), so what the planner predicts is the node's own flight.
##
## **Heights** are px above the floor (`PlanSpace`, `BodyHeights`), of the sphere's CENTRE
## (`height`), and `at` is its plan point (the 2D `(x, y)` = 3D `(x, z)`). The floor is a plane the
## sphere rests on (`GROUND_GAP` px over the room's slab, which stands 0.1 px up): a floor is no
## collider of the twin space a flight sweeps (a sphere rolling over slabs would catch their seams).
## A ceiling (`ceiling`, px: where a roof is over the flight; none in the open) keeps a flight's top
## under it. A roof is also a body of the twin space over a room's floor (`Floor.roofed`, the layer
## `TWIN_ROOF`), which the default `mask` strikes like a wall, for a flight that is not given the
## ceiling; a dropped item's mask leaves it out (it falls from a hand's height).
##
## **Contact.** A strike that comes in faster than `min_hop` and rebounds more than the next frame's
## gravity takes back bounces: the velocity is reflected and scaled by the surface's restitution
## (`floor_restitution` off one that faces up, `wall_restitution` off any other); a slower one
## settles: what drives it into the surface is cancelled, and on an upward-facing one it rolls, the
## floor slowing it by `friction`, until it is slower than `REST_SPEED`.

## What a step did: nothing notable, a bounce off an upward-facing surface (floor or a piece's top),
## a bounce off a wall or anything else, or it came to rest.
const NONE := 0
const LANDED := 1
const STRUCK := 2
const RESTED := 3
## It is at rest once it rolls slower than this (px/s).
const REST_SPEED := 4.0
## How far (px) the sphere's underside floats over the plane it rests on: over the room slab's
## 0.1 px, so a flight never touches a floor collider.
const GROUND_GAP := 0.5
## A surface whose normal's `y` is over this faces up: a flight rolls on it.
const FACES_UP := 0.7
## Contacts resolved in one step (a corner may take two: floor then wall).
const CONTACTS := 3
## No bodies passed.
const NOBODY: Array[RID] = []

## Where it is (plan point), and its height (centre, px above the floor).
var at := Vector2.ZERO
var height := 0.0
## Its velocity across the floor (px/s) and its vertical speed (up, px/s).
var velocity := Vector2.ZERO
var rise := 0.0
## The sphere's radius (px) and gravity (px/s²), the ceiling (px, the highest its centre plus radius
## goes; `INF`: none) and what it strikes (`PhysicsLayers`, 3D).
var radius := 3.0
var gravity := 680.0
var ceiling := INF
var mask := PhysicsLayers.TWIN_ALL | PhysicsLayers.TWIN_ROOF
## The share of its velocity a bounce keeps, off a surface facing up and off any other; the speed
## (px/s) under which a strike settles and does not bounce; the floor's skid deceleration (px/s²).
var floor_restitution := 0.35
var wall_restitution := 0.35
var min_hop := 40.0
var friction := 520.0
## It lies still: `step` does nothing.
var resting := false
## It is on a surface facing up and rolling (`step` slows it by `friction`).
var rolling := false
## The sweep (a sphere).
var _query := PhysicsShapeQueryParameters3D.new()


func _init(sphere_radius: float = 3.0) -> void:
	radius = sphere_radius
	var sphere := SphereShape3D.new()
	sphere.radius = sphere_radius * RenderConfig.unit
	_query.shape = sphere
	_query.collision_mask = mask


## The lowest the sphere's centre goes: the plane it rests on.
func floor_height() -> float:
	return radius + GROUND_GAP


## How high (px) its underside is over the floor: 0 where it lies on it, the piece's top on one.
func altitude() -> float:
	return maxf(height - floor_height(), 0.0)


## The speed across the floor (px/s).
func speed() -> float:
	return velocity.length()


## The 3D point of its centre.
func point() -> Vector3:
	return PlanSpace.lift(at, height)


## Put it at plan point `plan`, its centre `centre` px up.
func place(plan: Vector2, centre: float) -> void:
	at = plan
	height = maxf(centre, floor_height())


## Advance one physics frame of `delta` s in `space`, skipping the bodies in `passed`; returns what
## it did (`NONE`, `LANDED`, `STRUCK`, `RESTED`). With no `space` only the floor and the ceiling are
## there.
func step(space: PhysicsDirectSpaceState3D, delta: float, passed: Array[RID] = NOBODY) -> int:
	if resting:
		return NONE
	_query.exclude = passed
	_query.collision_mask = mask
	var event := NONE
	rise -= gravity * delta
	var left := Vector3(velocity.x, rise, velocity.y) * delta
	rolling = false
	for _pass in CONTACTS:
		if left.length_squared() < 0.0000001:
			break
		var hit := _sweep(space, left)
		if hit.is_empty():
			at += Vector2(left.x, left.z)
			height += left.y
			break
		at += Vector2(left.x, left.z) * float(hit["safe"])
		height += left.y * float(hit["safe"])
		var normal: Vector3 = hit["normal"]
		var taken := _contact(normal, delta)
		event = maxi(event, taken)
		left = _remaining(left, float(hit["safe"]), normal, taken)
	if rolling:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		if velocity.length() <= REST_SPEED:
			velocity = Vector2.ZERO
			resting = true
			event = RESTED
	return event


## Move it level toward plan point `target` as far as it is clear: it stops where a body of the twin
## space first meets the sphere (a wall, a piece), without bouncing; nothing else changes.
func advance_to(space: PhysicsDirectSpaceState3D, target: Vector2) -> void:
	_query.exclude = NOBODY
	_query.collision_mask = mask
	var across := target - at
	var motion := Vector3(across.x, 0.0, across.y)
	var found := _cast(space, motion) if space != null else {}
	var safe := float(found["safe"]) if not found.is_empty() else 1.0
	at += across * safe


## What stops a sweep of `motion` (3D, px) from where it is first, as `{ safe, normal }` (the share
## of it that is clear, and the surface's normal, a unit 3D vector): the floor and the ceiling
## planes, and the twin space's bodies; {} when nothing does.
func _sweep(space: PhysicsDirectSpaceState3D, motion: Vector3) -> Dictionary:
	var best := {}
	var safe := 1.0
	var lowest := floor_height()
	if height + motion.y < lowest and motion.y < 0.0:
		safe = clampf((height - lowest) / -motion.y, 0.0, 1.0)
		best = { "safe": safe, "normal": Vector3.UP }
	var highest := ceiling - radius
	if height + motion.y > highest and motion.y > 0.0:
		var share := clampf((highest - height) / motion.y, 0.0, 1.0)
		if share < safe:
			safe = share
			best = { "safe": share, "normal": Vector3.DOWN }
	if space == null:
		return best
	var found := _cast(space, motion * safe)
	if not found.is_empty():
		var share := safe * float(found["safe"])
		best = { "safe": share, "normal": found["normal"] }
	return best


## What the twin space's bodies stop the sphere's sweep of `motion` at: `{ safe, normal }` or {}.
func _cast(space: PhysicsDirectSpaceState3D, motion: Vector3) -> Dictionary:
	_query.transform = Transform3D(Basis(), point())
	_query.motion = motion * RenderConfig.unit
	var res := space.cast_motion(_query)
	if res.is_empty() or res[0] >= 1.0:
		return {}
	_query.transform = Transform3D(Basis(), point() + motion * RenderConfig.unit * res[1])
	_query.motion = Vector3.ZERO
	var info := space.get_rest_info(_query)
	var normal: Vector3 = info["normal"] if not info.is_empty() else -motion.normalized()
	return { "safe": res[0], "normal": normal }


## Settle the velocity against a surface of `normal` struck: a bounce when it comes in hard, else
## the part of the velocity into it cancelled (a roll on a surface that faces up). Returns what it
## was.
func _contact(normal: Vector3, delta: float) -> int:
	var v := Vector3(velocity.x, rise, velocity.y)
	var into := v.dot(normal)
	var faces_up := normal.y > FACES_UP
	if into >= 0.0:
		return NONE
	var keep := floor_restitution if faces_up else wall_restitution
	if -into > min_hop and -into * keep > gravity * delta:
		v = (v - 2.0 * into * normal) * keep
		velocity = Vector2(v.x, v.z)
		rise = v.y
		return LANDED if faces_up else STRUCK
	v -= into * normal
	velocity = Vector2(v.x, v.z)
	rise = v.y
	if faces_up:
		rolling = true
		rise = 0.0
	return NONE


## What is left of the frame's `motion` after a strike `safe` of the way along it, against a surface
## of `normal`: nothing after a bounce, else what slides along the surface.
func _remaining(motion: Vector3, safe: float, normal: Vector3, taken: int) -> Vector3:
	if taken == LANDED or taken == STRUCK:
		return Vector3.ZERO
	var rest := motion * (1.0 - safe)
	return rest - rest.dot(normal) * normal if rest.dot(normal) < 0.0 else rest
