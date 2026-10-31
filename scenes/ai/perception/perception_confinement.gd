extends RefCounted
## AI PERCEPTION sub-domain — the NPC's CONFINEMENT, the perception's part `confinement`: where it
## may act. Four rules, all of which must hold at a point: its territory (a defender keeps inside
## the house, `tuning.decision.defend_territory`), the room a `defend_room` order keeps it to
## (`docs/leadership.md` LD8), its squad leash (a follower holding no order fights within
## `SquadFollowConfig.leash` of its leader, LD23) and the room a stack held for its leader's go is
## to enter, which a member of it keeps out of (LD13, D38). The controller refreshes it once a
## tick, after the order intake and the squad's follow reads, and again as it refuses an order. The
## planner's COMBAT filter asks the frozen copy in the decision snapshot whether an option may be
## taken (`allows_option`, and `confines()` whether anything confines it); the behaviour's fight
## and `Combat`'s spots ask the live one whether it may act at a point (`allows(p)`). A data leaf:
## it holds no owner, only the house rooms it judges by.

const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")

## The house's rooms (`{ key, type, rect }` dicts, `WorldGen.get_rooms`) the rules judge a point
## by.
var rooms: Array = []
## The territory: it acts only in a room of the house.
var inside_only := false
## The room a `defend_room` order keeps it to ("" with none).
var room := ""
## Its leader's live position, the centre of its leash (`Vector2.INF` with no leash).
var leash_center := Vector2.INF
## The leash (px) round `leash_center` (0 with none).
var leash := 0.0
## The room it keeps out of: the one its held stack is to enter ("" with none).
var keep_out := ""


## Takes the tick's rules: `territorial` (the preset's territory), `order` (the live order, {} with
## none; only a `defend_room` one names a room), the leash, `radius` px round `center`
## (`Vector2.INF`: none), and `held_room`, the room its held stack is to enter ("" with none).
func refresh(
	territorial: bool,
	order: Dictionary,
	center: Vector2,
	radius: float,
	held_room := "",
) -> void:
	inside_only = territorial
	room = String(order.get("room", "")) if String(order.get("kind", "")) == "defend_room" else ""
	leash_center = center
	leash = radius if center != Vector2.INF else 0.0
	keep_out = held_room


## Whether any rule confines it.
func confines() -> bool:
	return inside_only or room != "" or leash_center != Vector2.INF or keep_out != ""


## Whether it may act at world point `p`: in the house when territorial, in the ordered room when
## it has one, out of the held stack's room when it has one, and within its leash when it has one.
func allows(p: Vector2) -> bool:
	if inside_only and room_at(p) == "":
		return false
	if room != "" and room_at(p) != room:
		return false
	if keep_out != "" and room_at(p) == keep_out:
		return false
	return leash_center == Vector2.INF or leash_center.distance_to(p) <= leash


## Whether it may take decision option `o`, judged where it acts: `params.from` (the spot a grenade
## is thrown from), else `params.point`. An option naming no place (a reload, a punch) is allowed.
func allows_option(o: Dictionary) -> bool:
	var params: Dictionary = o.get("params", {})
	var at = params.get("from", params.get("point"))
	if not at is Vector2 or at == Vector2.INF:
		return true
	return allows(at)


## The key of the house room world point `p` lies in, "" outside every room.
func room_at(p: Vector2) -> String:
	return HouseRooms.key_at(p, rooms)


## A copy that a later refresh leaves as it is: the decision snapshot's.
func copy() -> RefCounted:
	var out: RefCounted = get_script().new()
	out.rooms = rooms
	out.inside_only = inside_only
	out.room = room
	out.leash_center = leash_center
	out.leash = leash
	out.keep_out = keep_out
	return out


## Its rules as plain data, for `debug_state()`.
func view() -> Dictionary:
	return {
		"inside_only": inside_only,
		"room": room,
		"leash_center": leash_center,
		"leash": leash,
		"keep_out": keep_out,
		"confines": confines(),
	}
