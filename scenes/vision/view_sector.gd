extends RefCounted
## Vision domain: where a ray of the cone can pass, for `ViewWatch`. The rays are `view_distance`
## long and lie in the sector of the cone round the facing and in the bubble round the eye, so a
## solid wholly outside both is in none of them. A solid is taken with its extent (the radius of a
## disc about its origin) and `MARGIN` more, the half pixel at which `ViewShapes` joins two corners
## and more, so it is a superset of what the rays can meet.

## The margin (px) past the sector and the bubble.
const MARGIN := 2.0

## The eye, the facing (zero for none), the reach (px), half the cone's width (rad) and the
## bubble's radius (px) the last `look` was made for.
var eye := Vector2.ZERO
var facing := Vector2.ZERO
var reach := 0.0
var half := 0.0
var near := 0.0


## Look from `from` along `along` by `sight` (`Character.sight()`).
func look(from: Vector2, along: Vector2, sight: Dictionary) -> void:
	eye = from
	facing = along
	reach = float(sight["view_distance"])
	half = deg_to_rad(float(sight["fov_degrees"])) * 0.5
	near = float(sight["awareness_radius"])


## Whether a disc of `radius` about `origin` has a part where a ray can pass.
func touches(origin: Vector2, radius: float) -> bool:
	var to := origin - eye
	var dist := to.length()
	if dist > reach + radius:
		return false
	if dist <= near + radius + MARGIN:
		return true
	if facing == Vector2.ZERO:
		return false
	var slack := asin(minf(1.0, (radius + MARGIN) / dist))
	return absf(facing.angle_to(to)) <= half + slack
