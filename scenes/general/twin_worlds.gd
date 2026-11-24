class_name TwinWorlds extends RefCounted
## General domain: the 3D world of the twin space standing beside a `World2D` (interface 29), for
## a reader that holds the 2D world and needs the 3D one: its navigation map (`NavWorld`).


## The 3D world of the twin space standing beside `world` (the `World2D` the sim's nodes stand
## in), null when no twin space stands there (a world built by hand).
static func world_in(world: World2D) -> World3D:
	var stands: Array = TwinSpace.standing.get(world.get_instance_id(), [])
	for i in range(stands.size() - 1, -1, -1):  # the newest: an older one may be on its way out
		var stand: TwinSpace = stands[i]
		if is_instance_valid(stand) and stand.is_inside_tree():
			return stand.find_world_3d()
	return null
