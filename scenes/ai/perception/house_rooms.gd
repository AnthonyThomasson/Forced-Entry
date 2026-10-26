extends RefCounted
## AI PERCEPTION sub-domain — HOUSE ROOMS: the lookups over a house's rooms (`{ key, type, rect }`
## dicts, `WorldGen.get_rooms`) that the perception, its snapshot, the doorway views and the entry
## geometry share, so every reader finds a room the same way: the room a world point lies in
## (`at`), its key (`key_at`) and the room with a key (`by_key`). Static, preloaded (no
## `class_name`).


## The room dict whose rect contains `p`, or empty when `p` is outside every room.
static func at(p: Vector2, list: Array) -> Dictionary:
	for room in list:
		if (room["rect"] as Rect2).has_point(p):
			return room
	return {}


## The key of the room world point `p` lies in (`at`), or "" when it is outside every room.
static func key_at(p: Vector2, list: Array) -> String:
	return str(at(p, list).get("key", ""))


## The room of `list` (`{ key, type, rect }` dicts) with key `key`, or {}.
static func by_key(list: Array, key: String) -> Dictionary:
	for room in list:
		if str(room["key"]) == key:
			return room
	return {}
