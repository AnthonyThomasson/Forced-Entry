extends RefCounted
## The vehicle's frame for the vehicle tests (not a test): its front and sides, out of a door, where
## a door's user stands, where its body ends and what is beyond it, and its motion read in its own
## frame. `const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")`, beside
## `vehicle_probe.gd` (`Probe`), whose door reads `stand_point` stands on. Read through the drivable
## contract (interface 19) and the physics space, duck-typed.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


## The vehicle's front (unit, world).
static func forward(v: Node2D) -> Vector2:
	return v.global_transform.x.normalized()


## Its right side (unit, world): +y at rotation 0, so its left side is toward -y.
static func right(v: Node2D) -> Vector2:
	return v.global_transform.y.normalized()


## Out of door `d` (a `doors()` entry): behind the vehicle for a rear door, else away from its side.
static func outward(v: Node2D, d: Dictionary) -> Vector2:
	if d.get("kind") == &"rear":
		return -forward(v)
	var side := signf((d["handle"] as Vector2 - v.global_position).dot(right(v)))
	return right(v) * (side if side != 0.0 else 1.0)


## Where a character stands to use door `id`: `out` px out from its handle.
static func stand_point(v: Node2D, id: StringName, out := 22.0) -> Vector2:
	var d := Probe.door(v, id)
	return (d["handle"] as Vector2) + outward(v, d) * out


## Where the vehicle's body meets the line from its centre toward `direction` (world), by a ray from
## far out along it that hits only the vehicle (whatever else is on the line is skipped). The centre
## when nothing is hit.
static func edge(v: Node2D, direction: Vector2) -> Vector2:
	var space := v.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		v.global_position + direction.normalized() * 800.0,
		v.global_position,
	)
	var skipped: Array[RID] = []
	for i in 12:
		query.exclude = skipped
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		if hit["collider"] == v:
			return hit["position"]
		skipped.append(hit["rid"])
	return v.global_position


## How far (px) from the vehicle's body along `direction` the next solid thing is (another body or a
## wall), by a ray out from its edge; INF when nothing is within 2000 px.
static func gap_to_solid(v: Node2D, direction: Vector2) -> float:
	var space := v.get_world_2d().direct_space_state
	var from := edge(v, direction)
	var query := PhysicsRayQueryParameters2D.create(from, from + direction.normalized() * 2000.0)
	query.exclude = [v.get_rid()]
	var hit := space.intersect_ray(query)
	return INF if hit.is_empty() else from.distance_to(hit["position"])


## Its tail (the back of the body on its centre line) in its own frame, measured at rest.
static func tail_offset(v: Node2D) -> Vector2:
	return v.to_local(edge(v, -forward(v)))


## The body's velocity in its own frame: x along its front, y toward its right.
static func local_velocity(v: Node2D) -> Vector2:
	var lv: Vector2 = v.get("linear_velocity")
	return Vector2(lv.dot(forward(v)), lv.dot(right(v)))


## The pivot: the point on the centre line (its own frame, + = forward of the centre) with no
## sideways velocity, -lateral / yaw rate. In a gripping turn it is the rear axle; when the tail
## slides out it moves forward. INF while the body turns slower than 0.1 rad/s.
static func pivot(v: Node2D) -> float:
	var w: float = v.get("angular_velocity")
	if absf(w) <= 0.1:
		return INF
	return -local_velocity(v).y / w


## The body slip angle toward the outside of the turn (rad): + when the velocity points outside the
## heading (the tail is out, a slide), - when inside it (a gripping turn). 0 below 5 px/s or 0.05
## rad/s of turn.
static func outward_slip(v: Node2D) -> float:
	var lv := local_velocity(v)
	var w: float = v.get("angular_velocity")
	if lv.length() < 5.0 or absf(w) < 0.05:
		return 0.0
	return -atan2(lv.y, absf(lv.x)) * signf(w)


## Its velocity along its own front (px/s; negative = reversing).
static func along(v: Node2D) -> float:
	return (v.get("linear_velocity") as Vector2).dot(forward(v))
