extends RefCounted
## Tests: the oracle of "what stands on this plan line", cast straight into the twin space with
## raw 3D queries (never through `AgentVision` or `SightRay`, which a test is checking). It
## replaces the 2D `PhysicsRayQueryParameters2D` on `PhysicsLayers.SOLID` the tests used: a floor
## line (`FLOOR_LINE` px up) meets every piece, since each one stands on the floor, a wall, a door
## and a vehicle, and `WITH_BODIES` adds the characters. The answers name the 2D bodies the twins
## stand for (`TwinSpace.owner_of`).

## The height (px) of a floor line: under every piece's top, over the floor.
const FLOOR_LINE := 4.0
## The layers of a line over the solids of the world.
const SOLIDS := PhysicsLayers.TWIN_WORLD | PhysicsLayers.TWIN_VEHICLE
## The layers with the living added.
const WITH_BODIES := PhysicsLayers.TWIN_ALL


## A bare plan handle: a `Node2D` of `TwinSpace.BODIES` with no engine body and no shape, which the
## twin space looks at once it is in the tree (a test's stand-in for a body no domain builds).
static func handle() -> Node2D:
	var node := Node2D.new()
	node.add_to_group(TwinSpace.BODIES)
	return node


## The first thing on the plan line `a` to `b`, `FLOOR_LINE` px up, as `{ collider: the 2D body,
## position: plan point, rid: the twin's rid }`, or {} when it is clear. `mask` is the twin layers
## asked; `skip` are 2D bodies (or the 3D rids) the line passes through.
static func first(
	node: Node,
	a: Vector2,
	b: Vector2,
	skip: Array = [],
	mask := SOLIDS,
) -> Dictionary:
	var space := TwinSpace.space_of(node)
	var query := PhysicsRayQueryParameters3D.create(
		PlanSpace.lift(a, FLOOR_LINE), PlanSpace.lift(b, FLOOR_LINE), mask,
	)
	var rids: Array[RID] = []
	for one: Variant in skip:
		if one is RID:
			rids.append(one)
		elif one is Node:
			var twin := TwinSpace.twin_for(one as Node)
			if twin is CollisionObject3D:
				rids.append((twin as CollisionObject3D).get_rid())
	query.exclude = rids
	var found := space.intersect_ray(query)
	if found.is_empty():
		return {}
	return {
		"collider": TwinSpace.owner_of(found["collider"]),
		"position": PlanSpace.plan_of(found["position"]),
		"rid": found["rid"],
	}


## Whether nothing stands on the plan line `a` to `b` (see `first`).
static func clear(
	node: Node,
	a: Vector2,
	b: Vector2,
	skip: Array = [],
	mask := SOLIDS,
) -> bool:
	return first(node, a, b, skip, mask).is_empty()


## Whether no wall (a static body) stands on the plan line `a` to `b`: furniture and characters are
## looked past, a floor's slab too.
static func walls_clear(node: Node, a: Vector2, b: Vector2, height := FLOOR_LINE) -> bool:
	return walls_clear_in(TwinSpace.space_of(node), a, b, height)


## `walls_clear` in the twin space `space`.
static func walls_clear_in(
	space: PhysicsDirectSpaceState3D, a: Vector2, b: Vector2, height := FLOOR_LINE,
) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		PlanSpace.lift(a, height), PlanSpace.lift(b, height), PhysicsLayers.TWIN_WORLD,
	)
	var skipped: Array[RID] = []
	for _i in 24:
		query.exclude = skipped
		var found := space.intersect_ray(query)
		if found.is_empty():
			return true
		var owner := TwinSpace.owner_of(found["collider"])
		if owner != null and owner.is_in_group(TwinSpace.HARD):
			return false
		skipped.append(found["rid"])
	return false


## Every plan body under `root`, in tree order: each plan handle of `TwinSpace.BODIES` (a wall has
## no engine body, so a scan by type never meets it).
static func bodies_under(root: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for node in root.find_children("*", "Node2D", true, false):
		if node.is_in_group(TwinSpace.BODIES):
			out.append(node as Node2D)
	return out


## Every piece of furniture or decor under `root`, in tree order: the plan handles of
## `TwinSpace.PIECES` (a piece is a plain handle with no engine body).
static func pieces_under(root: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for node in root.find_children("*", "Node2D", true, false):
		if node.is_in_group(TwinSpace.PIECES):
			out.append(node as Node2D)
	return out


## Every character under `root`, in tree order: the plan handles of the group `characters` (a
## character has no engine body, so a scan by `Node2D` never meets it).
static func characters_under(root: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for node in root.find_children("*", "Node2D", true, false):
		if node.is_in_group(&"characters"):
			out.append(node as Node2D)
	return out
