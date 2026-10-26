extends RefCounted
## Shared helpers for the tests of where a stack's slots lie (`docs/tactical-entry.md` E20 to E22,
## ticket #65 round 2; not a test itself): `const Slots :=
## preload("res://tests/_ai/slots_probe.gd")`.
##
## The rules are judged from the house's own data and the test's own geometry, never from the entry
## code's: the rooms' rects and the doorway's wall plane (which room a slot is in, how far it is
## from the wall, which side of the door), the navmesh (`NavBuilder.snap` / `route`), the carved
## furniture (`NavBuilder.furniture_holes`) and the other doorways' views and funnels (the test's
## own copies, `door_view_probe.gd` / `entry_probe.gd`). Only WHERE the slots are is read from the
## AI, through the published entry geometry (`agent_entry.gd`, loaded by path as `PlayerStack` uses
## it): `new()`, `set_house(openings, rooms)`, `opening_id(o)`, `geometry(id, into, map, space)` and
## the one rule for where a stack of N stands, `StackLayout.slots(g, count, side)` ->
## `[{ n, point, side, row }]`.
##
## This one holds that seam, a way in's frame, the world a sweep judges in and the spec's numbers.
## The rules for one point are `slot_rules_probe.gd` (`SlotRules`), the faults a slot, a stack or a
## short wall's chain breaks `slot_faults_probe.gd` (`SlotFaults`), and rule 6's ways in and what
## each holds `slot_capacity_probe.gd` (`SlotCapacity`).

const ENTRY_SCRIPT := "res://scenes/ai/perception/agent_entry.gd"
## The stack's layout rules, whose `slots` lays a stack out.
const STACK_LAYOUT_SCRIPT := "res://scenes/ai/perception/stack/stack_layout.gd"
## Body radius (px) of a character.
const BODY := 14.0
## A slot inside its room keeps at least this far (px) from the room rect's edges (the walls'
## centrelines): half a wall plus most of a body, so a body standing there is inside the room's
## walls.
const ROOM_INSET := 16.0
## The first file stands against the wall: its slots lie between these distances (px) out from the
## wall plane (E2). The second file stands a step out from it, behind the first (E21): up to
## `ROW2_MAX`.
const ROW1_MIN := 14.0
const ROW1_MAX := 50.0
const ROW2_MAX := 110.0
## A slot stands beside the door, clear of its opening by a body: at least half the width plus this
## far (px) along the wall.
const BESIDE := BODY
## Whether a side has room for one (E21 "while it has room"), judged on spots of the test's own
## (`room_for_one`): this far out from the wall plane, from this far past the jamb along the wall
## every `ROOM_FOR_ONE_STEP` px.
const ROOM_FOR_ONE_OUT := 30.0
const ROOM_FOR_ONE_PAST := 18.0
const ROOM_FOR_ONE_STEP := 11.0
## How far (px) along the wall an exterior door's side runs, outdoors, for the room-for-one
## judgement: six slots' worth.
const ROOM_FOR_ONE_REACH := 300.0
## The largest stack (`AgentEntry.MAX_SLOTS`, the spec's six).
const MAX_STACK := 6
## `tuning.entry_geometry.stack_spacing`: how far apart (px) the fewest-views fallback's own picks
## of spots stand.
const STACK_SPACING := 44.0
## How far (px) from the doorway into the small room a tail member may hold (rule 6's tail: at that
## doorway, in the room it came by).
const TAIL_REACH := 140.0


# --- The AI's entry geometry, through its published seam ------------------------------------------


## A new entry geometry over the house's `openings` and `rooms` (null when the script is missing).
static func entry_geometry(openings: Array, rooms: Array) -> RefCounted:
	if not ResourceLoader.exists(ENTRY_SCRIPT):
		return null
	var e: RefCounted = (load(ENTRY_SCRIPT) as GDScript).new()
	e.set_house(openings, rooms)
	return e


## The id the AI gives opening `o` (`AgentEntry.opening_id`).
static func _opening_id(o: Dictionary) -> String:
	return String((load(ENTRY_SCRIPT) as GDScript).opening_id(o))


## Where a stack of `count` going in by geometry `g` stands, its point on side `side` (1 / -1 along
## the wall), read through the published rule `StackLayout.slots(g, count, side)`:
## `{ slots: [{ n, point, side, row }] }`.
static func layout(g: Dictionary, count: int, side: int) -> Dictionary:
	var raw = (load(STACK_LAYOUT_SCRIPT) as GDScript).call("slots", g, count, side)
	var published: Array = []
	for s in (raw if raw is Array else []):
		published.append({
			"n": int(s.get("n", 0)),
			"point": s.get("point", Vector2.INF),
			"side": int(s.get("side", 0)),
			"row": int(s.get("row", 1)),
		})
	return { "slots": published }


# --- The doorway, in the test's own frame ---------------------------------------------------------


## The unit normal pointing into `rect` from the edge door `pos` lies on (the nearest edge).
static func _normal_into(rect: Rect2, pos: Vector2) -> Vector2:
	var edges := [
		[absf(pos.x - rect.position.x), Vector2.RIGHT],
		[absf(pos.x - rect.end.x), Vector2.LEFT],
		[absf(pos.y - rect.position.y), Vector2.DOWN],
		[absf(pos.y - rect.end.y), Vector2.UP],
	]
	edges.sort_custom(func(a, b): return a[0] < b[0])
	return edges[0][1]


## The room `{ key, type, rect }` of `rooms` with key `key`, or {}.
static func _room(rooms: Array, key: String) -> Dictionary:
	for r in rooms:
		if String(r["key"]) == key:
			return r
	return {}


## The frame of going through opening `o` into room `into` (an `entry_probe` doorway frame plus the
## stack side): `{ id, pos, width, out (unit normal away from `into`), along (out.orthogonal(), the
## axis the side 1 / -1 is read on), room (into's rect), room_key, from (the stack side's room key,
## "" outdoors), from_rect }`.
static func frame(o: Dictionary, into: String, rooms: Array) -> Dictionary:
	var into_rect: Rect2 = _room(rooms, into).get("rect", Rect2())
	var pos: Vector2 = o["pos"]
	var out := -_normal_into(into_rect, pos)
	var from := ""
	for k in o.get("rooms", []):
		if String(k) != into:
			from = String(k)
	return {
		"id": _opening_id(o), "pos": pos, "width": float(o.get("width", 80.0)), "out": out,
		"along": out.orthogonal(), "room": into_rect, "room_key": into, "from": from,
		"from_rect": _room(rooms, from).get("rect", Rect2()),
	}


## The frame of every opening other than frame `f`'s that joins `f`'s stack-side room to another
## room (or to outside), framed going into the stack-side room: the doorways a tail may hold at
## (rule 6), in the room it came by.
static func ways_into_stack_room(w: Dictionary, f: Dictionary) -> Array:
	var out: Array = []
	if String(f["from"]) == "":
		return out
	for o in w["openings"]:
		if _opening_id(o) != f["id"] and (o.get("rooms", []) as Array).has(f["from"]):
			out.append(frame(o, String(f["from"]), w["rooms"]))
	return out


## Every way into a room through every opening of the house: one frame per opening and room it
## joins.
static func frames(openings: Array, rooms: Array) -> Array:
	var out: Array = []
	for o in openings:
		for k in o.get("rooms", []):
			out.append(frame(o, String(k), rooms))
	return out


## The side of the door (1 / -1 along `along`) point `p` lies on.
static func side_of(f: Dictionary, p: Vector2) -> int:
	return 1 if (p - (f["pos"] as Vector2)).dot(f["along"]) >= 0.0 else -1


# --- The world a sweep judges points in -----------------------------------------------------------


## The world a sweep judges points in: `{ rooms, openings, map, space, holes, frames }` (`frames`:
## every way into every room, for the other doorways' views and funnels).
static func world_of(
	rooms: Array,
	openings: Array,
	map: RID,
	space: PhysicsDirectSpaceState2D,
	house: Node2D,
) -> Dictionary:
	return {
		"rooms": rooms, "openings": openings, "map": map, "space": space,
		"holes": NavBuilder.furniture_holes(house), "frames": frames(openings, rooms),
	}
