extends RefCounted
## AI PERCEPTION sub-domain: the phase of each NPC's scheduled look for unknown rooms and furniture
## (`perception_house.gd`, `learn_by_sight`), handed out in turn in the order the NPCs first look,
## so a squad of N never has more than ceil(N / cycle) of them looking on one frame whatever the
## process allocated before them. Each world root counts on its own (by its instance id, which is
## never reused), so two worlds asking alternately each get an even spread and the same match
## hands out the same phases whenever it runs.

## Most world roots counted before the ones freed are dropped.
const ROOTS_KEPT := 16

## World root instance id -> how many phases it has handed out.
static var _given := {}


## The next phase, 0 to `cycle` - 1, for an NPC of `character`'s world.
static func next(character: Node, cycle: int) -> int:
	var root: Node = character.world_root() if character.has_method("world_root") else null
	var id := root.get_instance_id() if root != null else 0
	if not _given.has(id) and _given.size() >= ROOTS_KEPT:
		for kept: int in _given.keys():
			if kept != 0 and not is_instance_id_valid(kept):
				_given.erase(kept)
	var given: int = _given.get(id, 0)
	_given[id] = given + 1
	return given % cycle
