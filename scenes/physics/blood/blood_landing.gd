class_name BloodLanding
extends RefCounted
## Physics System, blood: where a parcel of blood thrown from a wound comes down in the twin 3D
## space (`TwinSpace`, interface 29). It leaves at the wound's real height, `HitInfo.height`, flies
## out along its direction and falls, and is traced as a few straight rays (sorted queries, no Jolt
## contact events): the first wall, piece or vehicle it meets is where it lands. On a wall's face it
## marks the wall at that height (`WALL`); on a piece's top it marks the top (`TOP`: a desk's, at
## its real height); meeting nothing it comes down on the floor, which the 2D splat keeps (`{}`: the
## floor's own rule, clipped by the walls round it).

## What a parcel met: a wall's face or the top of a piece.
enum Kind {
	WALL,
	TOP,
}

## The straight rays the flight is cut into.
const SEGMENTS := 8
## A hit lower than this (px) over the floor is the floor's: it lands as the 2D splat does.
const FLOOR_BAND := 1.5
## How steeply up (the normal's y) a face must look to be a top.
const FACES_UP := 0.7


## The surface the blood thrown from plan point `from`, `height` px up, along `direction` lands on
## within `flight` px of it, in `space`: `{ "kind": Kind, "at": the plan point, "height": px up,
## "normal": the face's plan normal (a wall's) }`; `{}` where it lands on the floor (a floor, no
## height, no twin space, or no direction to fly).
static func trace(
	space: PhysicsDirectSpaceState3D,
	from: Vector2,
	direction: Vector2,
	height: float,
	flight: float,
) -> Dictionary:
	if space == null or height < 0.0 or direction.length() < 0.001:
		return {}
	var unit := direction.normalized()
	var previous := PlanSpace.lift(from, height)
	for k in range(1, SEGMENTS + 1):
		var along := float(k) / float(SEGMENTS)
		var next := PlanSpace.lift(from + unit * flight * along, height * (1.0 - along * along))
		var query := PhysicsRayQueryParameters3D.create(previous, next, PhysicsConfig.twin_mask)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return _surface(hit)
		previous = next
	return {}


## What the ray `hit` struck, as `trace` answers (`{}` for the floor and for a ceiling's underside).
static func _surface(hit: Dictionary) -> Dictionary:
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var height := PlanSpace.height_of(point)
	if normal.y < -FACES_UP or (normal.y > FACES_UP and height < FLOOR_BAND):
		return {}
	var surface := { "at": PlanSpace.plan_of(point), "height": height }
	if normal.y > FACES_UP:
		surface["kind"] = Kind.TOP
	else:
		surface["kind"] = Kind.WALL
		surface["normal"] = Vector2(normal.x, normal.z).normalized()
	return surface
