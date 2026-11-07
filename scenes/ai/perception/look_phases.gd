extends RefCounted
## AI PERCEPTION sub-domain: the phase of each NPC's scheduled look for unknown rooms and furniture
## (`perception_house.gd`, `learn_by_sight`), handed out in turn in the order the NPCs first look,
## so a squad of N never has more than ceil(N / cycle) of them looking on one frame whatever the
## process allocated before them (an instance id's remainder clustered, and moved with every
## allocation, #192 Extension 3). The count starts over in a new world root, so the same match
## hands out the same phases whenever it runs.

## The world root the phases are being handed out in, and how many have been.
static var _root: Node = null
static var _given := 0


## The next phase, 0 to `cycle` - 1, for an NPC of `character`'s world.
static func next(character: Node, cycle: int) -> int:
	var root: Node = character.world_root() if character.has_method("world_root") else null
	if root != _root:
		_root = root
		_given = 0
	_given += 1
	return (_given - 1) % cycle
