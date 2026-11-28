extends "res://scenes/ai/perception/agent_vision.gd"
## Test double (not a test itself): an NPC's sight sense that answers as the real one does and
## checks every `sees_in_view` (the cast half of `can_see_node_at`) against a fresh recompute that
## reads nothing kept (`SightRay`'s kept looks-through, exclude rids and posture points): the
## target's points from `BodyHeights`, the rids from `exclude_of`, a struck body's surface read as
## it is now. A disagreement is written to `mismatches`. Put on a perception's `sight.vision` with
## `set_script` (the object, and every part that holds it, stays the same one).

## What the checks found: one text per disagreement.
var mismatches: Array[String] = []
## How many asks were checked, and how many answered true.
var asked := 0
var seen := 0


func sees_in_view(
	node: Node2D,
	point: Vector2,
	from_pos: Vector2,
	space: PhysicsDirectSpaceState3D,
	eye: float,
) -> bool:
	var answer := super(node, point, from_pos, space, eye)
	if space == null or not enabled or node == null or not is_instance_valid(node):
		return answer
	asked += 1
	if answer:
		seen += 1
	var fresh := _fresh(node, from_pos, space, eye)
	if fresh != answer:
		mismatches.append("frame %d %s: kept answer %s, fresh %s" % [
			Engine.get_physics_frames(), str(node.name), str(answer), str(fresh),
		])
	return answer


## The heights sight looks at over `node`, read off the body: a character's points at its posture,
## half the top of a piece's twin, the floor's point for anything else.
func _heights_of(node: Node2D) -> PackedFloat32Array:
	if node.get("movement") != null:
		return BodyHeights.sight_points(SightRay.posture_of(node))
	var twin := TwinSpace.twin_for(node)
	if twin != null:
		return PackedFloat32Array([0.5 * TwinShapes.top_of(twin)])
	return PackedFloat32Array([SightRay.GROUND_POINT])


## The sight ask with nothing kept: every ray cast here, each struck body's `transparent` read off
## its own surface.
func _fresh(
	node: Node2D, from_pos: Vector2, space: PhysicsDirectSpaceState3D, eye: float,
) -> bool:
	var heights := _heights_of(node)
	var exclude := SightRay.exclude_of(node)
	var origin := PlanSpace.lift(from_pos, eye)
	for height in heights:
		var ray := PhysicsRayQueryParameters3D.new()
		ray.from = origin
		ray.to = PlanSpace.lift(node.global_position, height)
		ray.collision_mask = SightRay.MASK
		ray.exclude = exclude.duplicate()
		while true:
			var found := space.intersect_ray(ray)
			if found.is_empty():
				return true
			var body := TwinSpace.owner_of(found["collider"])
			var glass: bool = (
				body != null and body.has_method("get_surface")
				and bool((body.get_surface() as Dictionary).get("transparent", false))
			)
			if not glass:
				break
			var more := ray.exclude.duplicate()
			more.append(found["rid"])
			ray.exclude = more
	return false
