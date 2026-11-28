extends RefCounted
## Test helper: a twin for a bare probe body (a bare plan handle of `TwinSpace.BODIES`: `Mortal`,
## the wall probe, `PlanProbe.handle`) no domain twins, so the carrier has a twin to hang its mesh
## on. `install(world)` adds a last builder to the world's twin space: a plain `Node3D` that the
## space writes the body's pose onto. Bodies a domain builds a twin for keep theirs (the builders
## are asked in order).


## Give every plan handle of `world` that no domain builder answers a plain
## `Node3D` twin, from now on.
static func install(world: Node) -> void:
	var twins := TwinSpace.of_world(world)
	if twins != null:
		twins.builders.append(_plain)


## The twin of a probe body.
static func _plain(node: Node2D) -> Node3D:
	return Node3D.new() if node.is_in_group(TwinSpace.BODIES) else null
