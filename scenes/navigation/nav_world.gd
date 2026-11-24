class_name NavWorld extends RefCounted
## Navigation domain: which navigation map a sim node stands on (#194 nav3d-b, D4). The nav is 3D:
## every region and agent is on the navigation map of the 3D world of the node's twin space
## (`TwinWorlds.world_in`, interface 29), the map of the sim's own viewport where no twin space
## stands beside it (a world built by hand), which a bare `World2D` has no map of any more.

## The worlds with no twin space `map_of` found a map in: `[World2D weak ref, World3D weak ref]` by
## the `World2D`'s instance id, what `map_in` answers for a reader that holds the world and no node.
## An entry whose world is gone is dropped the next time one is added, and never answered.
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
	var world3d := viewport.find_world_3d()
	_remember_bare(world, world3d)
	return world3d.navigation_map


## The planning map of `world` (the `World2D` the sim's nodes stand in), for a reader that holds it
## and no node; invalid for a world with no twin space that `map_of` has not been asked about, and
## for one whose 3D world is gone.
static func map_in(world: World2D) -> RID:
	var twins := TwinWorlds.world_in(world)
	if twins != null:
		return twins.navigation_map
	var entry: Array = _bare.get(world.get_instance_id(), [])
	if entry.size() == 2 and entry[0].get_ref() == world:
		var world3d: World3D = entry[1].get_ref()
		if world3d != null:
			return world3d.navigation_map
	return RID()


## Note that `world`'s map is `world3d`'s, dropping the notes of worlds that are gone.
static func _remember_bare(world: World2D, world3d: World3D) -> void:
	for id: int in _bare.keys():
		var entry: Array = _bare[id]
		if entry[0].get_ref() == null or entry[1].get_ref() == null:
			_bare.erase(id)
	_bare[world.get_instance_id()] = [weakref(world), weakref(world3d)]
