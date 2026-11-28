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
## The most a floor splat is moved off the solids round it (`clear_of_solids`), the px it is left
## clear of them by, and how far (px) its probe sphere floats over the floor's slab (which stands
## 0.1 px up and is no solid to push off).
const CLEAR_PASSES := 3
const CLEAR_MARGIN := 0.3
const CLEAR_LIFT := 0.5
## The thickness (px) of what blood laid on the floor asks the twin space about: a slab from
## `CLEAR_LIFT` up, so what stands on the floor in a cell blocks it, and a table's top or a lintel
## over it does not (blood runs under them).
const FLOOR_THICK := 1.0
## How far (px) in from a wall's face the ray for its top runs, and the height it starts from.
const TOP_PROBE := 0.5
const TOP_FROM := 400.0
## How steeply up (the normal's y) a face must look to be a top.
const FACES_UP := 0.7


## Where blood laid on the floor is asked about at plan point `at`: the middle of the floor slab.
static func on_floor(at: Vector2) -> Transform3D:
	return Transform3D(Basis(), PlanSpace.lift(at, CLEAR_LIFT + FLOOR_THICK * 0.5))


## The floor slab of a footprint `width` by `depth` px (plan), as a 3D box on `RenderConfig.unit`.
static func floor_box(width: float, depth: float) -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(width, FLOOR_THICK, depth) * RenderConfig.unit
	return box


## The surface the blood thrown from plan point `from`, `height` px up, along `direction` lands on
## within `flight` px of it, in `space`: `{ "kind": Kind, "at": the plan point, "height": px up,
## "normal": the face's plan normal and "top": its height, px (a wall's) }`; `{} ` where it lands on
## the floor (a floor, no height, no twin space, or no direction to fly).
static func trace(
	space: PhysicsDirectSpaceState3D,
	from: Vector2,
	direction: Vector2,
	height: float,
	flight: float,
) -> Dictionary:
	if space == null or height < 0.0 or flight < 0.001 or direction.length() < 0.001:
		return {}
	var unit := direction.normalized()
	var previous := PlanSpace.lift(from, height)
	for k in range(1, SEGMENTS + 1):
		var along := float(k) / float(SEGMENTS)
		var next := PlanSpace.lift(from + unit * flight * along, height * (1.0 - along * along))
		var query := PhysicsRayQueryParameters3D.create(previous, next, PhysicsConfig.twin_mask)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return _surface(space, hit)
		previous = next
	return {}


## Plan point `at` moved off any wall or piece that a splat laid flat on the floor there, its core
## reaching `extent` px from `at`, would overlap: the floor splat's 2D clipping stops its spikes and
## droplets at a footprint, not its core, which would lie under a desk's top or in a wall. Moved out
## along the nearest face's normal (from inside a solid too), at most `CLEAR_PASSES` times (a
## corner).
static func clear_of_solids(
	space: PhysicsDirectSpaceState3D, at: Vector2, extent: float
) -> Vector2:
	if space == null or extent <= 0.0:
		return at
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = extent * RenderConfig.unit
	query.shape = sphere
	query.collision_mask = PhysicsConfig.twin_mask
	for _pass in CLEAR_PASSES:
		query.transform = Transform3D(Basis(), PlanSpace.lift(at, extent + CLEAR_LIFT))
		var info := space.get_rest_info(query)
		if info.is_empty():
			break
		var out := Vector2(info["normal"].x, info["normal"].z)
		if out.length() < 0.5:
			break
		out = out.normalized()
		var depth := extent + CLEAR_MARGIN - (at - PlanSpace.plan_of(info["point"])).dot(out)
		if depth <= 0.0:
			break
		at += out * depth
	return at


## What the ray `hit` struck, as `trace` answers (`{}` for the floor and for a ceiling's underside).
static func _surface(space: PhysicsDirectSpaceState3D, hit: Dictionary) -> Dictionary:
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
		surface["top"] = _top_of(space, surface["at"], surface["normal"])
	return surface


## How high (px) the face struck at plan point `at`, looking along `facing`, stands: the height of
## what a ray down from over it meets just inside the face (a wall's 96, a desk's end 31).
static func _top_of(space: PhysicsDirectSpaceState3D, at: Vector2, facing: Vector2) -> float:
	var inside := at - facing * TOP_PROBE
	var query := PhysicsRayQueryParameters3D.create(
		PlanSpace.lift(inside, TOP_FROM), PlanSpace.lift(inside, 0.0), PhysicsConfig.twin_mask
	)
	var hit := space.intersect_ray(query)
	return PlanSpace.height_of(hit["position"]) if not hit.is_empty() else INF
