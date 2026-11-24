class_name NavWorld extends RefCounted
## Navigation domain: which navigation map a sim node stands on (#194 nav3d-b, D4). The nav is 3D:
## every region and agent is on the navigation map of the 3D world of the node's twin space
## (`TwinWorlds.world_in`, interface 29), the map of the sim's own viewport where no twin space
## stands beside it (a world built by hand), which a bare `World2D` has no map of any more.

## The maps of worlds with no twin space, by the instance id of their `World2D` (what `map_of`
## found there): what `map_in` answers for a reader that holds the world and no node.
static var _bare: Dictionary = {}


## The planning map of the world `node` stands in; invalid for a node outside the tree.
static func map_of(node: Node) -> RID:
	if node == null or not node.is_inside_tree():
		return RID()
	var viewport := node.get_viewport()
	var world := viewport.find_world_2d()
	var twins := TwinWorlds.world_in(world)
	if twins != null:
		return twins.navigation_map
	var map := viewport.find_world_3d().navigation_map
	_bare[world.get_instance_id()] = map
	return map


## The planning map of `world` (the `World2D` the sim's nodes stand in), for a reader that holds it
## and no node; invalid for a world with no twin space that `map_of` has not been asked about.
static func map_in(world: World2D) -> RID:
	var twins := TwinWorlds.world_in(world)
	if twins != null:
		return twins.navigation_map
	return _bare.get(world.get_instance_id(), RID())
