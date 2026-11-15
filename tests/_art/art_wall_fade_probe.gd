extends RefCounted
## Shared helper for the tests of the wall fade (not a test itself): the real walls of a 3D match
## to stand behind, and how whole a wall's instance is drawn.

## A segment this long and this thin is a wall to stand behind.
const LONG := 80.0
const THIN := 20.0


## Walls of `world` with a segment long and thin enough to stand behind, no two within `apart` px,
## each one `keep.call(centre)` accepts (a centre on the ground, `Vector2`; an invalid `Callable`
## accepts all): per wall its body, its mesh, the segment's index and instance, its centre and
## (once `stand_behind` ran) the marker.
static func walls(
	mirror: WorldMirror, world: Node, apart: float, keep := Callable()
) -> Array:
	var found: Array = []
	for body: Node in world.find_children("*", "StaticBody2D", true, false):
		var shown := mirror.proxies_of(body)
		if not body.has_method(&"segment_shapes") or shown.size() != 1:
			continue
		var mesh: Node3D = shown[0]
		if not mesh.has_method(&"segments"):
			continue
		var segment := _segment_to_stand_behind(mesh, found, apart, keep)
		if not segment.is_empty():
			segment.merge({ "body": body, "mesh": mesh })
			found.append(segment)
	return found


## The first segment of `mesh` that is a wall to stand behind: its index, instance and centre, or
## an empty dictionary.
static func _segment_to_stand_behind(
	mesh: Node3D, found: Array, apart: float, keep: Callable
) -> Dictionary:
	var segments: Dictionary = mesh.call(&"segments")
	for index: int in segments:
		var part := segments[index] as MeshInstance3D
		var box: AABB = part.global_transform * part.get_aabb()
		var centre := Vector2(box.get_center().x, box.get_center().z)
		if _fits(box, centre, found, apart, keep):
			return { "index": index, "part": part, "centre": centre }
	return {}


static func _fits(box: AABB, centre: Vector2, found: Array, apart: float, keep: Callable) -> bool:
	var long := maxf(box.size.x, box.size.z)
	var thin := minf(box.size.x, box.size.z)
	if long < LONG or thin > THIN:
		return false
	if keep.is_valid() and not keep.call(centre):
		return false
	return found.all(func(w: Dictionary) -> bool: return w["centre"].distance_to(centre) > apart)


## The 2D point `standoff` px behind `wall`'s segment as the camera sees it (the camera looks from
## `back`, the ground direction toward it): the wall is between that point and the camera.
static func behind(wall: Dictionary, back: Vector2, standoff: float) -> Vector2:
	return wall["centre"] - back * standoff


## The ground direction from the world toward a camera at `yaw` degrees.
static func back_of(yaw: float) -> Vector2:
	return Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw)))


## How whole `part` is drawn (what the shader is told; 1 when nothing was written).
static func level(part: Node) -> float:
	var value: Variant = (part as GeometryInstance3D).get_instance_shader_parameter(&"fade")
	return 1.0 if value == null else float(value)
