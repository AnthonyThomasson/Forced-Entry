class_name TwinWorlds extends RefCounted
## General domain: which twin space stands beside a `World2D` (interface 29), for a reader that
## holds the 2D world the sim's nodes stand in and needs the 3D one: its direct space
## (`TwinSpace.space_in`) and its navigation map (`NavWorld`).

## The twin spaces by the instance id of the `World2D` they stand beside.
static var _beside: Dictionary = {}


## The 3D world of the twin space standing beside `world` (the `World2D` the sim's nodes stand
## in), null when no twin space stands there (a world built by hand).
static func world_in(world: World2D) -> World3D:
	var stand := standing_in(world)
	return stand.find_world_3d() if stand != null else null


## The twin space standing beside `world`, the newest in the tree (an older one may be on its way
## out); null when none stands there.
static func standing_in(world: World2D) -> TwinSpace:
	var stands: Array = _beside.get(world.get_instance_id(), [])
	for i in range(stands.size() - 1, -1, -1):
		var stand: TwinSpace = stands[i]
		if is_instance_valid(stand) and stand.is_inside_tree():
			return stand
	return null


## Note that `space` stands beside `world` (its `watch` does).
static func enter(space: TwinSpace, world: World2D) -> void:
	var id := world.get_instance_id()
	if not _beside.has(id):
		_beside[id] = []
	if not space in _beside[id]:
		_beside[id].append(space)


## Note that `space` stands beside no world any more (it left the tree).
static func leave(space: TwinSpace) -> void:
	for id: int in _beside.keys():
		var stands: Array = _beside[id]
		stands.erase(space)
		if stands.is_empty():
			_beside.erase(id)
