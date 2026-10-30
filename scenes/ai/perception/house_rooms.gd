extends RefCounted
## AI PERCEPTION sub-domain — HOUSE ROOMS: the lookups over a house's rooms (`{ key, type, rect }`
## dicts, `WorldGen.get_rooms`) that the perception, its snapshot, the doorway views and the entry
## geometry share, so every reader finds a room the same way: the room a world point lies in
## (`at`), its key (`key_at`) and the room with a key (`by_key`); and how a doorway (a
## `WorldGen.get_openings` dict, its `rooms` the keys of the rooms it joins) joins them: the rooms
## it joins (`joins`) and the room it leads into from one of them (`beyond`), which the doorway
## geometry and the team read alike. Static, preloaded (no `class_name`).


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


## The keys of the rooms doorway `o` joins, as Strings: two for a doorway between rooms, one for an
## exterior door.
static func joins(o: Dictionary) -> Array:
	return (o.get("rooms", []) as Array).map(func(k): return str(k))


## The room doorway `o` leads into from room `here` ("" = outside): the other room it joins, "" for
## an exterior door gone out by; null when `o` is not a doorway of `here` (from outside: not an
## exterior door).
static func beyond(o: Dictionary, here: String) -> Variant:
	var keys := joins(o)
	if here == "":
		return keys[0] if keys.size() == 1 else null
	if not keys.has(here):
		return null
	if keys.size() == 1:
		return ""
	return keys[1] if keys[0] == here else keys[0]
