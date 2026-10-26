extends RefCounted
## AI PERCEPTION sub-domain — ENTRY GEOMETRY. What an NPC knows about getting through a doorway into
## a room (`docs/tactical-entry.md`): for each opening of the house, entered into one of the rooms
## it joins, the door's frame (its outward normal and the axis along its wall), the stack slots in
## single file against the wall on either side, the pie arc a point man sweeps from, and the four
## corners of the room behind, each tagged hard (unseen from just outside the threshold) or soft.
## The claims on an opening and the stack they make are the stack module's (`stack/`: `StackClaim`,
## `ClaimLedger`, `DoorStack`), which lays its slots in this geometry.
##
## Each doorway's VIEW and the walk that keeps out of the views are `agent_door_views.gd` (`views`),
## which a split stack reads (`cuts_view`, `docs/tactical-entry.md` E19).
##
## Pure geometry over the house's openings (Main's `WorldGen.get_openings`, injected), its rooms,
## the nav map (slots and pie points are snapped onto it) and sight rays (via the vision sense). The
## walls never move, so an opening's geometry is built once, the first time it is asked for on a
## baked map, and kept. No policy: it never decides which door, which slot or when to go.

## How far (px) outside the threshold the "entry point" is that a corner is judged hard or soft
## from.
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const AgentDoorViews := preload("res://scenes/ai/perception/agent_door_views.gd")
## The doorway's fatal funnel and the claims' fields (stack/stack_claim.gd).
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const StackLayout := preload("res://scenes/ai/perception/stack/stack_layout.gd")
const EntrySlots := preload("res://scenes/ai/perception/entry/entry_slots.gd")
const ENTRY_POINT_DEPTH := 24.0
## Slots worked out per side: a fuller team queues in the last one.
const MAX_SLOTS := 6
## How many bodies go into a room too small for the team (`short_room`): the point and the second,
## who take its corners.
const SHORT_ROOM_CAPACITY := 2
## A defend spot (`defend_spot`, `docs/leadership.md` D2): how far back from its doorway's wall (px)
## it is sought, at best `DEFEND_DEPTH`...
const DEFEND_DEPTHS := [60.0, 90.0, 120.0, 150.0]
const DEFEND_DEPTH := 100.0
## ... and how far along the wall past the doorway's jamb (px), at best `DEFEND_LATERAL`: off the
## doorway's axis, out of its funnel.
const DEFEND_LATERALS := [30.0, 50.0, 75.0, 100.0]
const DEFEND_LATERAL := 50.0
## Inset (px) of a defend spot from the room's walls (a body and half a wall), and the most a snap
## onto the navmesh may move it.
const DEFEND_INSET := 22.0
const DEFEND_SNAP := 10.0
## A spot within a body (px) of a doorway's width and closer than `DEFEND_FUNNEL_DEPTH` (px) to its
## wall stands in its fatal funnel.
const DEFEND_BODY := 14.0
const DEFEND_FUNNEL_DEPTH := 200.0
## Where (px into the room from the doorway's centre) a defender's sight line to its doorway ends.
const DEFEND_DOOR_IN := 8.0
## An ambush post (`ambush_spot`, `docs/leadership.md` LD15): how far back from the doorway's wall
## (px) it is sought, at best `AMBUSH_DEPTH` (the cover depth of a room's holders, E8)...
const AMBUSH_DEPTHS := [40.0, 70.0, 100.0, 130.0, 160.0]
const AMBUSH_DEPTH := 110.0
## ... and how far along the wall past the doorway's jamb (px): well along it, where the wall hides
## the post from a stack outside.
const AMBUSH_LATERALS := [30.0, 60.0, 90.0, 120.0, 150.0, 180.0, 220.0, 260.0]
## Inset (px) of an ambush post from the room's walls.
const AMBUSH_INSET := 22.0
## How far apart (px) two ambushers' posts on one side of the doorway stand (a stack's slot spacing:
## clear of each other's footprint).
const AMBUSH_SPACING := 44.0
## How far (px) round its post an ambusher may stand once there (it stops within a reach of the
## spot, the behaviour's `orders.DEFEND_REACH`, and a little): a post is hidden only when it is
## hidden there too.
const AMBUSH_SLACK := 12.0
## Where a stack may stand (`_lay_slots`, E20 to E22): a slot stays this far (px) inside its room's
## rect (half a wall and most of a body), within this far of where the navmesh snaps it, reached
## from this far out from the wall plane (ending within `SLOT_ROUTE_REACH`).
const SLOT_ROOM_INSET := 16.0
const SLOT_SNAP := 3.0
const SLOT_REACH_OUT := 60.0
const SLOT_ROUTE_REACH := 6.0
## A body's radius (px): a slot against the wall stands clear of the doorway's opening by it, one on
## the open floor off its axis.
const SLOT_BODY := 14.0
## Sides of the polygon a body is carved as (`slot_reach`).
const BODY_SEGMENTS := 10
## A route of `slot_reach` that ends short of its point still reaches it by a last leg walked plain,
## as a walk does (`Locomotion` `LAST_LEG` and `PASS_CLEARANCE`): the leg on at most this long (px),
## passing no body closer than `SLOT_PASS` (px).
const SLOT_LAST_LEG := 64.0
const SLOT_PASS := 32.0
## How far (px) past the jamb the first slot of a file stands, and the step (px) a side's wall is
## walked along in.
const SLOT_JAMB := 18.0
const SLOT_STEP := 4.0
## A tail member's outs against its doorway's wall (`_row1_outs`): between these (px) out from the
## wall plane.
const ROW1_MIN := 18.0
const ROW1_MAX := 46.0
## A spot against the wall (`_has_wall_spot`): between these (px) out from the wall plane, a body's
## standoff give or take a few px.
const WALL_SPOT_MIN := 24.0
const WALL_SPOT_MAX := 38.0
## The band beside the door a wall stack's slots are sought in (px out from the wall plane: against
## it to a step out), and the depth within which a slot counts as against the wall (row 1; past it
## row 2, the second file).
const SLOT_OUT_MIN := 14.0
const SLOT_OUT_MAX := 110.0
const ROW1_DEPTH := 50.0
## The grid (px) a wall stack's slots are first sought on; a wall short of a full stack is sought
## again on the `SLOT_STEP` grid.
const WALL_GRID := 8.0
## A body counts in a doorway's view only this far (px) inside its edges.
const VIEW_MARGIN := 10.0
## Outdoors, how far (px) along the house's wall from the doorway a file may run.
const OUTDOOR_REACH := 320.0
## The open-floor fallback: the grid (px) its spots are sought on, finer (`OPEN_GRID_FINE`) for a
## dead end whose room holds fewer than a full stack on it; the most search steps the dead end's
## packing takes; how far (px) from its doorway a tail member holds.
const OPEN_GRID := 8.0
const OPEN_GRID_FINE := 4.0
## Outdoors, how far (px) along the house's wall either side of the door, and out from it, a short
## wall's overflow is sought.
const OUTDOOR_FLOOR := 300.0
const PACK_BUDGET := 200_000
const TAIL_REACH := 140.0

## The geometry every NPC on a navigation map shares (map RID -> "<house and tuning>|<opening
## id>><room key>" -> geometry): it is the house's and the map's, not the NPC's, and laying a
## doorway's slots is costly (`_lay_slots`), so it is laid once per map, not once per NPC. Forgotten
## with the map's planning region.
static var _shared := {}
## The physics frame `warm_geometry` last laid a doorway in (one a frame, among every NPC).
static var _warmed_frame := -1

## The sight sense (sight rays over low cover): the perception hands in its own.
var vision: RefCounted = AgentVision.new()
## The doorway views and the walk round them: the perception hands in its own.
var views: RefCounted = AgentDoorViews.new()
## Where a stack may stand and walk at a doorway (`slots.on_stack_side(self, …)`); see
## entry/entry_slots.gd.
var slots: RefCounted = EntrySlots.new()
## Distance (px) between neighbouring stack slots: clear of a neighbour's footprint.
var stack_spacing: float = 44.0
## Distance (px) of a stack slot off the wall's centreline.
var wall_standoff: float = 28.0
## Distance (px) from the threshold of the pie arc a point man sweeps from.
var pie_radius: float = 100.0
## Points on the pie arc (angle steps).
var pie_steps: int = 5
## Inset (px) of a corner point from the room's two walls.
var corner_inset: float = 40.0
## A room with a side under this (px) is too small for the team: two go in (E13).
var short_room: float = 150.0
## The house's doorways (`{ pos, width, front, exit, rooms }`), as injected.
var _openings: Array = []
## The house's rooms (`{ key, type, rect }`).
var _rooms: Array = []
## "<opening id>><room key>" -> the geometry of that entry.
var _cache := {}
## The house handed in (`set_house`), as a hash: what the shared geometry is keyed by.
var _house := ""
## The shared geometry (`_shared_on`) in which `warm_geometry` last found every way in laid...
var _warm_done_in := {}
## ... for these `_tuning_inputs()` (the house and the tunables): nothing to look for until either
## changes.
var _warm_done_for: Array = []
## "<opening id>><room key>" -> the ambush post candidates of that doorway, room side
## (`_ambush_posts`).
var _posts := {}
## Every way into a room through every doorway, framed (`_door_frames`).
var _frames: Array = []


## Hand in the house: its doorways and rooms (to the views too). Forgets the cached geometry when
## they changed.
func set_house(openings: Array, rooms: Array) -> void:
	views.set_house(openings, rooms)
	if openings == _openings and rooms == _rooms:
		return
	_openings = openings
	_rooms = rooms
	_house = "%d:%d" % [hash(openings), hash(rooms)]
	_cache.clear()
	_posts.clear()
	_frames = []


## The stable id of doorway `o` ("door_<x>_<y>", its rounded world position): what the snapshot's
## options, the behaviour and the radio call it (`AgentDoorViews.opening_id`).
static func opening_id(o: Dictionary) -> String:
	return AgentDoorViews.opening_id(o)


## The house's doorway whose `opening_id` is `id`, or `{}`.
func _opening(id: String) -> Dictionary:
	for o in _openings:
		if opening_id(o) == id:
			return o
	return {}


## The doorways an NPC standing in room `here_key` ("" = outside) can go through into a room: an
## outer door from outside, any door of its room into the room on the far side. Each
## `{ id, into, pos, width, front }`.
func entries_from(here_key: String) -> Array:
	var out: Array = []
	for o in _openings:
		var joins: Array = o.get("rooms", [])
		var into := ""
		if here_key == "" and joins.size() == 1:
			into = str(joins[0])
		elif here_key != "" and joins.size() == 2 and here_key in joins.map(func(k): return str(k)):
			into = str(joins[0]) if str(joins[1]) == here_key else str(joins[1])
		if into == "":
			continue
		out.append({
			"id": opening_id(o), "into": into, "pos": o["pos"],
			"width": float(o.get("width", 80.0)), "front": bool(o.get("front", false)),
		})
	return out


## Every doorway of room `room_key`, outer doors (to outside) included: where something can come
## from. Each `{ id, pos, width }`, in the order the house lists them. A resting NPC watches these
## (`Watch.idle_gaze`).
func room_doorways(room_key: String) -> Array:
	var out: Array = []
	for o in _openings:
		if room_key in (o.get("rooms", []) as Array).map(func(k): return str(k)):
			out.append({
				"id": opening_id(o),
				"pos": o["pos"],
				"width": float(o.get("width", 80.0)),
			})
	return out


## Where member `nth` of `count` holds room `room_key` it was ordered to defend
## (`docs/leadership.md` LD8, D2), and what it watches: the members share out the room's doorways
## (sorted by id; member `nth` takes doorway `nth` mod their number, the extras doubling up on the
## other side of it), each standing back in the room off its doorway's axis, out of every doorway's
## fatal funnel, with a sight line to it and, where there is one, low furniture between (cover it
## sees over); a lone member takes the spot from which it sees the most doorways.
## `{ spot, door, door_pos, doors }`: `door` is the id of the doorway it keeps its gun on ("" for a
## lone member of a room with several: it turns among `doors`, the room's doorways), `door_pos` that
## doorway's centre (INF for none). {} for a room it does not know.
func defend_spot(
	room_key: String,
	nth: int,
	count: int,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	var rect := _room_rect(room_key)
	if rect.size == Vector2.ZERO:
		return {}
	var doors := room_doorways(room_key)
	doors.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	if doors.is_empty():
		return {
			"spot": NavBuilder.snap(map, rect.get_center()),
			"door": "",
			"door_pos": Vector2.INF,
			"doors": doors,
		}
	var lone := count <= 1 and doors.size() > 1
	var own: Dictionary = doors[posmod(nth, doors.size())]
	var round_no := int(float(nth) / float(doors.size()))
	var best := {}
	for d in (doors if lone else [own]):
		var at := _defend_best(_defend_frame(rect, d, doors, round_no, lone), map, space)
		if not at.is_empty() and (best.is_empty() or float(at["score"]) < float(best["score"])):
			best = at
	return {
		"spot": NavBuilder.snap(map, rect.get_center()) if best.is_empty() else best["spot"],
		"door": "" if lone else String(own["id"]),
		"door_pos": Vector2.INF if lone else own["pos"],
		"doors": doors,
	}


## The frame a defend spot by doorway `d` of room `rect` (one of the room's `doors`) is sought in
## (`defend_spot`): `{ id, pos, width, into, along, room, doors, wanted, lone }`, `into` the normal
## into the room, `along` its wall's axis, `wanted` the side of the axis member round `round_no`
## takes (the side with more wall first, then they alternate), `lone` a lone member's.
func _defend_frame(
	rect: Rect2,
	d: Dictionary,
	doors: Array,
	round_no: int,
	lone: bool,
) -> Dictionary:
	var pos: Vector2 = d["pos"]
	var into := normal_into(rect, pos)
	var along := into.orthogonal()
	var first := _first_side(rect, pos, along)
	return {
		"id": d["id"],
		"pos": pos,
		"width": float(d["width"]),
		"into": into,
		"along": along,
		"room": rect,
		"doors": doors,
		"wanted": first if round_no % 2 == 0 else -first,
		"lone": lone,
	}


## The best defend spot in frame `f` (`_defend_frame`): of the candidates `DEFEND_DEPTHS` back and
## `DEFEND_LATERALS` past the jamb either side (`_defend_candidate`), the first with the lowest
## score (`_defend_score`). `{ score, spot }`, or {} when there is none.
func _defend_best(f: Dictionary, map: RID, space: PhysicsDirectSpaceState2D) -> Dictionary:
	var best := {}
	for at: Array in _offsets(DEFEND_DEPTHS, DEFEND_LATERALS):
		var c := _defend_candidate(f["room"], _offset_point(f, at), f["doors"], map, space)
		if c.is_empty():
			continue
		var score := _defend_score(f, c, at)
		if best.is_empty() or score < float(best["score"]):
			best = { "score": score, "spot": c["spot"] }
	return best


## The rank of defend candidate `c` (`_defend_candidate`) found at offset `at` (`_offsets`) in frame
## `f`, the lower the better: nearest the best depth and lateral, out of every funnel; a lone
## member's seeing the most doorways, any other's seeing its own doorway, on its `wanted` side; then
## low furniture on the line (cover seen over).
func _defend_score(f: Dictionary, c: Dictionary, at: Array) -> float:
	var depth: float = at[0]
	var lateral: float = at[1]
	var score: float = (absf(depth - DEFEND_DEPTH) + absf(lateral - DEFEND_LATERAL)
			+ float(c["funnel"]) * 1000.0)
	if f["lone"]:
		score -= float(c["sees"]) * 2000.0
	else:
		score += ((0.0 if c["sees_door"].has(f["id"]) else 3000.0)
				+ (0.0 if at[2] == f["wanted"] else 400.0))
	score += (0.0
			if c["cover"].has(f["id"]) or (f["lone"] and not c["cover"].is_empty())
			else 300.0)
	return score


## Every offset a spot back from a doorway is sought at: `[depth, lateral, side]` for each of
## `depths`, each of `laterals` past the jamb and each side of the axis (1, then -1), in that order.
func _offsets(depths: Array, laterals: Array) -> Array:
	var out: Array = []
	for depth: float in depths:
		for lateral: float in laterals:
			for s: int in [1, -1]:
				out.append([depth, lateral, s])
	return out


## The point at offset `at` (`_offsets`) in frame `f` (its doorway's `pos`, `width`, the normal
## `into` the room and the wall's axis `along`): `depth` into the room, `lateral` past the jamb on
## side `side`.
func _offset_point(f: Dictionary, at: Array) -> Vector2:
	var pos: Vector2 = f["pos"]
	var into: Vector2 = f["into"]
	var along: Vector2 = f["along"]
	var width: float = f["width"]
	var depth: float = at[0]
	var lateral: float = at[1]
	var s: int = at[2]
	return pos + into * depth + along * s * (width * 0.5 + lateral)


## The side (1 / -1 along `along`) with more of room `rect`'s wall from door `pos`, 1 when even.
func _first_side(rect: Rect2, pos: Vector2, along: Vector2) -> int:
	return 1 if _wall_length(rect, pos, along) >= _wall_length(rect, pos, -along) else -1


## A candidate defend spot near `raw` (`defend_spot`): snapped onto the navmesh inside the room
## (dropped when the snap moves it off), with `funnel` (how many of the room's `doors` it stands in
## the fatal funnel of), `sees` / `sees_door` (the doorways it has a sight line to, how many and
## which) and `cover` (the ids of those with low furniture on the line, which it sees over). {} when
## it is no spot.
func _defend_candidate(
	rect: Rect2,
	raw: Vector2,
	doors: Array,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	var inner := rect.grow(-DEFEND_INSET)
	if not inner.has_point(raw):
		return {}
	var p := NavBuilder.snap(map, raw)
	if p.distance_to(raw) > DEFEND_SNAP or not inner.has_point(p):
		return {}
	var funnel := 0
	var sees: Dictionary = {}
	var cover: Dictionary = {}
	for d in doors:
		var pos: Vector2 = d["pos"]
		var into := normal_into(rect, pos)
		var off := p - pos
		if (absf(off.dot(into.orthogonal())) < float(d["width"]) * 0.5 + DEFEND_BODY
				and off.dot(into) < DEFEND_FUNNEL_DEPTH):
			funnel += 1
		var aim := pos + into * DEFEND_DOOR_IN
		if _sees(space, p, aim):
			sees[d["id"]] = true
			var hit: Dictionary = vision.raycast(space, p, aim, []) if space != null else {}
			if hit.get("collider") is RigidBody2D:
				cover[d["id"]] = true
	return { "spot": p, "funnel": funnel, "sees": sees.size(), "sees_door": sees, "cover": cover }


## Where member `nth` of `count` ordered to ambush a doorway from the room it leads into waits, `g`
## being that way in's entry geometry (`geometry(id, room_key, map, space)`) (`docs/leadership.md`
## LD15, D17): a post in the room, off the doorway's axis, back from its wall and inside the room's
## walls, out of the fatal funnel of every doorway of the room, with a sight line to the threshold,
## and unseen from outside: no sight line to it from any slot or pie step of an entry into the room
## by that doorway. Among the hidden posts, one with low furniture on its line to the threshold
## (cover it sees over) wins, then the nearest `AMBUSH_DEPTH` back; with none hidden, the least
## seen. Hidden means hidden wherever within `AMBUSH_SLACK` of the post the ambusher stops. Members
## alternate sides of the axis (member `nth`: the side with more wall first), and two on one side
## stand `AMBUSH_SPACING` apart.
## `{ spot, door_pos, seen }`: `door_pos` is the doorway's centre, where its gun goes, `seen` how
## many of those slots and pie steps see the post (0: hidden). {} for an empty `g` (a doorway or
## room it does not know), or no post.
func ambush_spot(
	g: Dictionary,
	nth: int,
	count: int,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	if g.is_empty():
		return {}
	var posts := _ambush_posts(g, map, space)
	if posts.is_empty():
		return {}
	var first := _first_side(g["room"], g["pos"], g["along"])
	var taken: Array = []
	var pick := {}
	for k in mini(nth, maxi(count - 1, 0)) + 1:
		var wanted := first if k % 2 == 0 else -first
		pick = {}
		for c: Dictionary in posts:
			if taken.any(func(t): return (t as Vector2).distance_to(c["spot"]) < AMBUSH_SPACING):
				continue
			var score := float(c["score"]) + (0.0 if int(c["side"]) == wanted else 50_000.0)
			if pick.is_empty() or score < float(pick["score"]):
				pick = { "score": score, "spot": c["spot"], "seen": c["seen"] }
		if pick.is_empty():
			return {}
		taken.append(pick["spot"])
	return { "spot": pick["spot"], "door_pos": g["pos"], "seen": pick["seen"] }


## The candidate ambush posts of entry geometry `g` (into its room `into`, the side the ambusher
## waits on), kept once worked out on a baked map: `{ spot, side, seen, score }`, `side` the side of
## the axis it lies on, `seen` how many slots and pie steps see it, `score` the post's rank before
## the side is weighed (the lower the better: hidden first, out of every funnel, cover on its line,
## then nearest `AMBUSH_DEPTH`).
func _ambush_posts(g: Dictionary, map: RID, space: PhysicsDirectSpaceState2D) -> Array:
	var room_key := String(g["into"])
	var key := "%s>%s" % [g["id"], room_key]
	if _posts.has(key):
		return _posts[key]
	var f := {
		"id": g["id"],
		"pos": g["pos"],
		"width": float(g["width"]),
		"into": -(g["out"] as Vector2),
		"along": g["along"],
		"room": g["room"],
		"doors": room_doorways(room_key),
	}
	var observers := _observers_of(g)
	var out: Array = []
	for at: Array in _offsets(AMBUSH_DEPTHS, AMBUSH_LATERALS):
		var post := _ambush_post(f, at, observers, map, space)
		if not post.is_empty():
			out.append(post)
	if NavBuilder.ready(map):
		_posts[key] = out  # Only keep what was snapped onto a baked map.
	return out


## The ambush post at offset `at` (`_offsets`) in frame `f` (`_ambush_posts`: the doorway, its room
## and the room's doorways), seen from `observers` (`_observers_of`): `{ spot, side, seen, score }`,
## or {} when it is no post (outside the room's inset, no spot there, no sight line to the doorway,
## or on its axis).
func _ambush_post(
	f: Dictionary,
	at: Array,
	observers: Array,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	var rect: Rect2 = f["room"]
	var raw := _offset_point(f, at)
	if not rect.grow(-AMBUSH_INSET).has_point(raw):
		return {}
	var c := _defend_candidate(rect, raw, f["doors"], map, space)
	if c.is_empty() or not c["sees_door"].has(f["id"]):
		return {}
	var p: Vector2 = c["spot"]
	if absf((p - (f["pos"] as Vector2)).dot(f["along"])) < float(f["width"]) * 0.5 + DEFEND_BODY:
		return {}  # On the axis.
	var seen := _seen_by(space, observers, p)
	var score := (float(seen) * 1000.0 + float(c["funnel"]) * 500.0
			+ (0.0 if c["cover"].has(f["id"]) else 300.0) + absf(float(at[0]) - AMBUSH_DEPTH))
	return { "spot": p, "side": at[2], "seen": seen, "score": score }


## Who could see an ambush post of entry geometry `g` from outside: its `lookouts`, then each side's
## slots and pie steps (side 1 first).
func _observers_of(g: Dictionary) -> Array:
	var observers: Array = (g["lookouts"] as Array).duplicate()
	for side in [1, -1]:
		observers.append_array(g["slots"][side])
		observers.append_array(g["pie"][side])
	return observers


## How many of `observers` see post `p` (`_sees_from`); for a post none sees, the most that see any
## of the 8 points `AMBUSH_SLACK` round it.
func _seen_by(space: PhysicsDirectSpaceState2D, observers: Array, p: Vector2) -> int:
	var seen := observers.filter(func(o): return _sees_from(space, o, p)).size()
	if seen == 0:
		for k in 8:
			var q := p + Vector2.from_angle(TAU * k / 8.0) * AMBUSH_SLACK
			seen = maxi(seen, observers.filter(func(o): return _sees_from(space, o, q)).size())
	return seen


## Whether someone standing at `from` sees `to` (over low cover; walls and tall furniture block it),
## at any distance and whichever way it faces: what a stack outside could see of a post once it
## looks.
func _sees_from(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	return space == null or vision.sight_hit(space, from, to, []).is_empty()


## The doorways out of room `room_key` (one already cleared) that lead on into another room that
## `is_cleared` (a Callable on the room key) says is not cleared, other than doorway `exclude_id`
## (the one the NPC came in by). Doors to outside are left out. Each `{ id, into, pos, width }`.
## What the team covers once it has cleared a room (E8).
func watch_doors(room_key: String, exclude_id: String, is_cleared: Callable) -> Array:
	return entries_from(room_key).filter(
		func(e): return e["id"] != exclude_id and not is_cleared.call(e["into"]),
	)


## Whether a walk from `from` reaches `to` with a body standing at each of `bodies` (world points:
## the body a walk is held by and the others at rest it sees) in its way at body width (`SLOT_BODY`,
## and `NavBuilder.OBSTACLE_MARGIN` round it as the steering map carves a body at rest), by any way
## at all: 1 when the route on the planning map with them carved (an avoid map of its own, kept per
## set of bodies) ends within `AgentDoorViews.AVOID_REACH` of `to`, or within `SLOT_LAST_LEG` of it
## with the plain way on from there that long at most and passing none of `bodies` closer than
## `SLOT_PASS` (a slot between two taken ones lies inside their carved margins, and a walk goes in
## by that last leg); 0 when it does not, -1 while that map is still being baked (asking starts the
## bake). What an entry asks before it reads a hold as sealing its slot for good (E2). 1 when there
## is no planning region to carve.
func slot_reach(from: Vector2, to: Vector2, map: RID, bodies: Array) -> int:
	var region := NavBuilder.planning_region(map)
	if region == null or not NavBuilder.ready(map):
		return 1
	var carved := _bodies_map(region, bodies)
	if not carved.is_valid() or not NavBuilder.ready(carved):
		return -1
	var path := NavBuilder.route(carved, from, to)
	if path.is_empty():
		return 0
	var end := path[path.size() - 1]
	var goal := NavBuilder.snap(map, to)
	if end.distance_to(goal) <= AgentDoorViews.AVOID_REACH:
		return 1
	return 1 if _last_leg_clear(map, end, goal, bodies) else 0


## The avoid map (`NavBuilder.avoid_map`) of planning region `region` with a body carved at each of
## `bodies` (a `BODY_SEGMENTS`-gon of `SLOT_BODY` and `NavBuilder.OBSTACLE_MARGIN`), keyed by the
## bodies on a `SLOT_STEP` grid (`slot_reach`).
func _bodies_map(region: NavigationRegion2D, bodies: Array) -> RID:
	var keys: Array = []
	var holes: Array = []
	for b: Vector2 in bodies:
		keys.append("%d,%d" % [int(b.x / SLOT_STEP), int(b.y / SLOT_STEP)])
		var hole := PackedVector2Array()
		for i in BODY_SEGMENTS:
			hole.append(b + Vector2.from_angle(TAU * i / BODY_SEGMENTS) * (SLOT_BODY
					+ NavBuilder.OBSTACLE_MARGIN))
		holes.append(hole)
	keys.sort()
	return NavBuilder.avoid_map(region, "bodies:" + ";".join(keys), holes)


## Whether the last leg of `slot_reach`, walked plain on `map` from a route's `end` to `goal`, is at
## most `SLOT_LAST_LEG` long and passes none of `bodies` closer than `SLOT_PASS` (one `end` already
## stands by, and walks away from, closer than that is no bar).
func _last_leg_clear(map: RID, end: Vector2, goal: Vector2, bodies: Array) -> bool:
	var leg := NavBuilder.route(map, end, goal)
	if end.distance_to(goal) > SLOT_LAST_LEG or NavBuilder.path_length(leg) > SLOT_LAST_LEG:
		return false
	for b: Vector2 in bodies:
		# One the route's end already stands by, and walks away from, is no bar.
		var limit := minf(SLOT_PASS, end.distance_to(b) - 1.0)
		for i in range(1, leg.size()):
			if (Geometry2D.get_closest_point_to_segment(b, leg[i - 1], leg[i]).distance_to(b)
					< limit):
				return false
	return true


## The rect of room `key`, or an empty Rect2.
func _room_rect(key: String) -> Rect2:
	return HouseRooms.by_key(_rooms, key).get("rect", Rect2())


## The geometry of going through opening `id` into room `into`, or {} when either is unknown. Built
## once on a baked nav map (`map`) and kept: { id, into, pos, width, out (unit normal away from the
## room), along (unit axis along the wall), wall: { 1: px, -1: px } (the room's wall either side of
## the door), side (the side with more wall to stack against, 0 when even), slots: { 1: [..], -1:
## [..] } (stack slots, nearest the door first), pie: { 1: [..], -1: [..] } (pie arc points, from
## the wall toward the axis), lookouts (the slots and pie points as laid out, before they are
## snapped onto the navmesh: where an entry's stack and point stand, or near it), corners: [{ pos,
## near, side, hard }], room (the room's rect), capacity (how many may go in: 2 for a short room,
## else MAX_SLOTS) }.
func geometry(id: String, into: String, map: RID, space: PhysicsDirectSpaceState2D) -> Dictionary:
	var key := "%s>%s" % [id, into]
	if _cache.has(key):
		return _cache[key]
	var shared := _shared_on(map)
	var shared_key := "%s|%s" % [_tuning(), key]
	if shared.has(shared_key):
		_cache[key] = shared[shared_key]
		return _cache[key]
	var opening := _opening(id)
	var room := HouseRooms.by_key(_rooms, into)
	if opening.is_empty() or room.is_empty():
		return {}
	var g := _build(opening, room, map, space)
	if NavBuilder.ready(map):
		_cache[key] = g  # Only keep what was snapped onto a baked map.
		shared[shared_key] = g
	return g


## Lay one way in by a doorway of the house whose geometry nobody on `map` has yet (`geometry`), at
## most one a physics frame among every NPC, once the map is baked: called every SEE pass, so the
## doorways are laid in the first frames after the bake rather than in the middle of a decision.
## Once a pass finds them all laid it looks no more (`_warm_done_in`) until the house, a tunable or
## the map's shared geometry changes.
func warm_geometry(map: RID, space: PhysicsDirectSpaceState2D) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _warmed_frame or space == null:
		return
	var shared := _shared_on(map)
	var inputs := _tuning_inputs()
	if is_same(shared, _warm_done_in) and inputs == _warm_done_for:
		return
	if not NavBuilder.ready(map):
		return
	var tuning := str(inputs)
	for o in _openings:
		for k in o.get("rooms", []):
			if not shared.has("%s|%s>%s" % [tuning, opening_id(o), k]):
				_warmed_frame = frame
				geometry(opening_id(o), str(k), map, space)
				return
	_warm_done_in = shared
	_warm_done_for = inputs


## The geometry shared on `map` (`_shared`), made the first time it is asked for and dropped when
## the map's planning region leaves the tree; a map with no planning region shares nothing (an empty
## dictionary each time).
func _shared_on(map: RID) -> Dictionary:
	if _shared.has(map):
		return _shared[map]
	var region := NavBuilder.planning_region(map)
	if region == null:
		return {}
	_shared[map] = {}
	region.tree_exited.connect(func() -> void: _shared.erase(map), CONNECT_ONE_SHOT)
	return _shared[map]


## What a doorway's geometry is laid from besides the map: the house and the tunables `_build` reads
## (the stack's spacing and standoff, the pie, the corners, the short room, the view's depth, and
## the sight that tells a hard corner). Cheap to make and compare, so `warm_geometry` checks it
## every pass; `_tuning()` is the same as the key the shared geometry is filed under.
func _tuning_inputs() -> Array:
	var out: Array = [
		_house, stack_spacing, wall_standoff, pie_radius, pie_steps, corner_inset, short_room,
		views.door_view_depth,
	]
	out.append_array([
		vision.enabled, vision.view_distance, vision.fov_degrees, vision.awareness_radius,
		vision.see_over_coverage,
	])
	return out


## `_tuning_inputs()` as the shared geometry's key prefix.
func _tuning() -> String:
	return str(_tuning_inputs())


## Lay out one entry: the door's frame from the room edge it sits on, then slots, pie arc and
## corners.
func _build(
	opening: Dictionary,
	room: Dictionary,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	var pos: Vector2 = opening["pos"]
	var rect: Rect2 = room["rect"]
	var out := -normal_into(rect, pos)
	var along := out.orthogonal()
	var wall := { 1: _wall_length(rect, pos, along), -1: _wall_length(rect, pos, -along) }
	var g := {
		"id": opening_id(opening), "into": str(room["key"]), "pos": pos,
		"width": float(opening.get("width", 80.0)), "out": out, "along": along, "wall": wall,
		"side": _longer_side(wall),
	}
	_lay_rows(g, map)
	g["corners"] = _corners(g, rect, map, space)
	g["room"] = rect
	g["capacity"] = (SHORT_ROOM_CAPACITY
			if minf(rect.size.x, rect.size.y) < short_room
			else MAX_SLOTS)
	g["kind"] = "wall"
	g["files"] = {
		1: g["slots"][1].map(func(p): return { "point": p, "row": 1 }),
		-1: g["slots"][-1].map(func(p): return { "point": p, "row": 1 }),
	}
	g["row1"] = { 1: MAX_SLOTS, -1: MAX_SLOTS }
	g["spacing"] = stack_spacing
	if NavBuilder.ready(map) and space != null:
		_lay_slots(g, opening, map, space)
	return g


## The side (1 / -1) with more wall to stack against of `wall` (`{ 1: px, -1: px }`), 0 when even
## (within a px).
func _longer_side(wall: Dictionary) -> int:
	if absf(wall[1] - wall[-1]) >= 1.0:
		return 1 if wall[1] > wall[-1] else -1
	return 0


## Lay the first stack slots and the pie arc of the entry framed in `g` (its `pos`, `width`, `out`
## and `along`) on `map`: sets `slots` and `pie` (`{ 1: [..], -1: [..] }`, snapped) and `lookouts`
## (the points as laid out: side 1's slots and pie, then side -1's).
func _lay_rows(g: Dictionary, map: RID) -> void:
	var pos: Vector2 = g["pos"]
	var out: Vector2 = g["out"]
	var along: Vector2 = g["along"]
	var width: float = g["width"]
	var by_slot := {}
	var pie := {}
	var lookouts: Array = []
	for s in [1, -1]:
		var row: Array = []
		for k in MAX_SLOTS:
			var lateral := width * 0.5 + 18.0 + k * stack_spacing
			lookouts.append(pos + out * wall_standoff + along * s * lateral)
			row.append(NavBuilder.snap(map, lookouts[-1]))
		by_slot[s] = row
		pie[s] = _pie_arc(g, s, lookouts, map)
	g["slots"] = by_slot
	g["pie"] = pie
	g["lookouts"] = lookouts


## The pie arc on side `s` of the entry framed in `g`, snapped onto `map`: `pie_steps` points
## `pie_radius` from the threshold, each laid out point added to `lookouts` too.
func _pie_arc(g: Dictionary, s: int, lookouts: Array, map: RID) -> Array:
	var pos: Vector2 = g["pos"]
	var out: Vector2 = g["out"]
	var along: Vector2 = g["along"]
	var arc: Array = []
	var steps := maxi(pie_steps, 2)
	for i in steps:
		# From 55° off the door's axis (clear of the stack against the wall) toward it (25° off), on
		# side `s`.
		var theta := deg_to_rad(lerpf(55.0, 25.0, float(i) / float(steps - 1)))
		lookouts.append(pos + out * cos(theta) * pie_radius
				+ along * s * sin(theta) * pie_radius)
		arc.append(NavBuilder.snap(map, lookouts[-1]))
	return arc


## The four corners of room `rect` behind the entry framed in `g`, inset `corner_inset` (at most a
## quarter of the room's short side) and snapped onto `map`: `[{ pos, near, side, hard }]`, `near`
## on the door's own wall, `hard` unseen from `ENTRY_POINT_DEPTH` outside the threshold.
func _corners(g: Dictionary, rect: Rect2, map: RID, space: PhysicsDirectSpaceState2D) -> Array:
	var pos: Vector2 = g["pos"]
	var out: Vector2 = g["out"]
	var along: Vector2 = g["along"]
	var inset := minf(corner_inset, minf(rect.size.x, rect.size.y) * 0.25)
	var inner := rect.grow(-inset)
	var entry_point := pos + out * ENTRY_POINT_DEPTH
	var corners: Array = []
	var depth_max := -INF
	var raw := [
		inner.position,
		Vector2(inner.end.x, inner.position.y),
		inner.end,
		Vector2(inner.position.x, inner.end.y),
	]
	for c in raw:
		depth_max = maxf(depth_max, (c - pos).dot(out))
	for c in raw:
		var p := NavBuilder.snap(map, c)
		corners.append({
			"pos": p,
			"near": absf((c - pos).dot(out) - depth_max) < 1.0,  # On the door's own wall.
			"side": 1 if (c - pos).dot(along) >= 0.0 else -1,
			"hard": not _sees(space, entry_point, p),
		})
	return corners


# --- Where a stack stands (E20 to E22) -----------------------------------------------------------


## Lay out where a stack going in by `g` (built for `opening`) stands, the one rule every stack
## reads (`StackLayout.slots`, `side_for`, `point`): E20, every slot in the room (or the outdoor
## area) on the stack side of the doorway's wall, on the navmesh, reached from the stack side
## without going through the doorway, out of every other doorway's view and funnel; E21, a side's
## file runs along the wall to the room's corner, the other side next, then a second file a step
## out; E22, a slot on solid furniture is skipped (the navmesh is carved round the piece). Sets
## `kind` and its layout on `g`:
## - `wall` (a spot against the wall beside the door out of every other doorway's view,
##   `_has_wall_spot`): `files` { 1: [..], -1: [..] }, each side's file nearest the door first
##   (`{ point, row }`, row 1 against the wall, then row 2 a step out): the most bodies the wall
##   band beside the door holds (`_pack`), `row1` how many of each are against the wall;
## - `views` (every spot against the wall beside the door is in another doorway's view):
##   `views_lays`, the stack of each size on each first side, taken from the points of the wall band
##   seen from the fewest other doorways (`_views_lays`);
## - `open_floor` (no spot beside the door at all) and `dead_end` (the same, from a room whose only
##   doorway this is): no wall slots.
## `wall_n` is how many slots the wall (or the fewest-seen spots) holds; the members past them
## follow `seq` (`_overflow`). `from` is the key of the room the stack stands in ("" outside the
## house), `from_room` its rect (zero outside).
func _lay_slots(
	g: Dictionary,
	opening: Dictionary,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> void:
	var from := _other_room(opening, str(g["into"]))
	var c := _stack_context(g, from, map, space)
	var dead_end := from != "" and room_doorways(from).size() <= 1
	var bands := { 1: _band(c, 1, WALL_GRID), -1: _band(c, -1, WALL_GRID) }
	g["wall_n"] = 0
	g["from"] = from
	# The room the stack stands in (a zero rect: the open, outside the house).
	g["from_room"] = c["from_rect"]
	if _has_wall_spot(c, false):
		_lay_wall(g, c, bands, from == "" or dead_end)
	elif _has_wall_spot(c, true):
		_lay_views(g, c, bands, from == "" or dead_end)
	else:
		_lay_open(g, c, dead_end)


## The key of the room doorway `opening` joins other than `key` (the last such it lists), or "" for
## none (an exterior door).
func _other_room(opening: Dictionary, key: String) -> String:
	var other := ""
	for k in opening.get("rooms", []):
		if str(k) != key:
			other = str(k)
	return other


## What laying the stack of entry `g` reads (`_lay_slots`), the stack standing in room `from` (""
## for outside): `{ id, pos, out, along, half, from, from_rect, map, space, start, reach }`, `start`
## the navmesh point `SLOT_REACH_OUT` out from the wall plane its slots are reached from, `reach`
## the cache of `_reached`.
func _stack_context(
	g: Dictionary,
	from: String,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	return {
		"id": g["id"], "pos": g["pos"], "out": g["out"], "along": g["along"],
		"half": float(g["width"]) * 0.5, "from": from, "from_rect": _room_rect(from), "map": map,
		"space": space,
		"start": NavBuilder.snap(
			map,
			(g["pos"] as Vector2) + (g["out"] as Vector2) * SLOT_REACH_OUT,
		),
		"reach": {},
	}


## Lay a `wall` stack on `g` (`_lay_slots`) from its wall bands `bands` (`_band`, per side): each
## side's file the most bodies its spots out of every other doorway's view hold (`_pack`), on the
## finer grid when that is short of a full stack, then the overflow (`_overflow`, `capped` for none
## past the open floor).
func _lay_wall(g: Dictionary, c: Dictionary, bands: Dictionary, capped: bool) -> void:
	var files := {}
	for s in [1, -1]:
		files[s] = _pack((bands[s] as Array).filter(func(x): return x["views"] == 0))
	if (files[1] as Array).size() + (files[-1] as Array).size() < MAX_SLOTS:
		for s in [1, -1]:  # Short of a full stack: the whole wall, on the finer grid.
			files[s] = _pack(_band(c, s, SLOT_STEP).filter(func(x): return x["views"] == 0))
	var laid: Array = []
	var row1 := {}
	for s in [1, -1]:
		row1[s] = (files[s] as Array).filter(func(f): return f["row"] == 1).size()
		laid.append_array((files[s] as Array).map(func(f): return f["point"]))
	g["kind"] = "wall"
	g["files"] = files
	g["row1"] = row1
	g["slots"] = {
		1: files[1].map(func(f): return f["point"]),
		-1: files[-1].map(func(f): return f["point"]),
	}
	g["wall_n"] = mini(MAX_SLOTS, laid.size())
	if row1[1] != row1[-1]:
		g["side"] = 1 if row1[1] > row1[-1] else -1
	# A short wall's overflow: the same room's open floor, then the tail; none outdoors or from a
	# room with no other doorway.
	_overflow(g, c, laid, capped, true)


## Lay a `views` stack on `g` (`_lay_slots`) from its wall bands `bands`: the layouts of the spots
## seen from the fewest other doorways (`_views_lays`, on the finer grid when short of a full
## stack), the slots of a full stack from the side `g` stacks on, then the overflow past them.
func _lay_views(g: Dictionary, c: Dictionary, bands: Dictionary, capped: bool) -> void:
	var lays := _views_lays(bands)
	# Short of a full stack: the whole wall, on the finer grid.
	if (lays[1][MAX_SLOTS - 1] as Array).size() < MAX_SLOTS:
		lays = _views_lays({ 1: _band(c, 1, SLOT_STEP), -1: _band(c, -1, SLOT_STEP) })
	g["kind"] = "views"
	g["views_lays"] = lays
	var lay := views_layout(g, MAX_SLOTS, int(g["side"]) if int(g["side"]) != 0 else 1)
	g["slots"] = {
		1: lay.filter(func(x): return x["side"] == 1).map(func(x): return x["point"]),
		-1: lay.filter(func(x): return x["side"] == -1).map(func(x): return x["point"]),
	}
	g["wall_n"] = lay.size()
	# Past what the fewest-seen spots hold, the same chain as a short wall's (rule 6).
	_overflow(
		g,
		c,
		(lays[1][MAX_SLOTS - 1] as Array).map(func(x): return x["point"]),
		capped,
		true,
	)


## Lay an `open_floor` stack on `g` (`_lay_slots`), a `dead_end` one when `dead_end`: no wall slots,
## its slots the overflow's (`seq`), each on the side of the door it lies on.
func _lay_open(g: Dictionary, c: Dictionary, dead_end: bool) -> void:
	g["kind"] = "dead_end" if dead_end else "open_floor"
	_overflow(g, c, [], dead_end, false)
	var seq: Array = g["seq"]
	var point_of := func(x): return x["point"]
	g["slots"] = {
		1: seq.filter(func(x): return side_of(g, x["point"]) == 1).map(point_of),
		-1: seq.filter(func(x): return side_of(g, x["point"]) == -1).map(point_of),
	}


## Where the members of a stack going in by `g` stand past the `wall_n` the wall holds (`laid`,
## their points; rule 6, E20's fallback): `seq`, slots on the stack side's open floor (off the
## door's axis and out of its funnel, `stack_spacing` from the wall's slots), then the tail's
## (`tail_from` on: the members the room cannot hold, holding in the room they came by at its
## doorway into the small room, never crossing). `capped` (nowhere for a tail: a dead end, whose
## room has no other doorway, or outdoors past a short wall) takes as many as its open floor holds
## (the most, `_most_spaced`) and no more: the members past that get no slot. A short wall's
## overflow, and that of a `views` way in past the spots it holds (`strict`), keeps off its wall
## band and out of every other doorway's view too, and takes the most its open floor holds before
## the tail.
func _overflow(g: Dictionary, c: Dictionary, laid: Array, capped: bool, strict: bool) -> void:
	var wanted := MAX_SLOTS - int(g["wall_n"])
	var open_slots: Array = (_open_floor(c, capped or strict, laid, wanted, strict)
			if wanted > 0
			else [])
	var seq: Array = open_slots.map(func(p): return { "point": p, "row": 1 })
	g["tail_from"] = int(g["wall_n"]) + seq.size() + 1
	if not capped and wanted > open_slots.size():
		seq.append_array(_tail_spots(c, laid + open_slots).map(
			func(p): return { "point": p, "row": 1 },
		))
	g["seq"] = seq
	g["capped"] = capped


## Whether the wall beside the door of `c` has a spot against it (a body's standoff from it, give or
## take a few px) where a body may stand (`_slot_ok`), out of every other doorway's view unless
## `with_views`, on either side from `SLOT_JAMB` past the jamb to the wall's end: the stack side
## room's corner (outdoors `OUTDOOR_REACH`) or another doorway's funnel (E21). With one only in some
## doorway's view the stack takes the spots seen from the fewest other doorways; with none at all it
## stands on the open floor (rule 6).
func _has_wall_spot(c: Dictionary, with_views: bool) -> bool:
	for s in [1, -1]:
		if _has_wall_spot_on(c, s, with_views):
			return true
	return false


## `_has_wall_spot` on side `s` (1 / -1 along the wall) alone: walked from `SLOT_JAMB` past the jamb
## in `SLOT_STEP`s to the wall's end.
func _has_wall_spot_on(c: Dictionary, s: int, with_views: bool) -> bool:
	var pos: Vector2 = c["pos"]
	var out: Vector2 = c["out"]
	var along: Vector2 = (c["along"] as Vector2) * s
	var reach := OUTDOOR_REACH
	if c["from"] != "":
		reach = _edge_along(c["from_rect"], pos + out * wall_standoff, along) - SLOT_ROOM_INSET
	var lateral: float = c["half"] + SLOT_JAMB
	while lateral <= reach:
		if _in_other_funnel(c, pos + out * wall_standoff + along * lateral):
			break  # The wall's end: another doorway's funnel.
		if _wall_spot_at(c, along, lateral, with_views):
			return true
		lateral += SLOT_STEP
	return false


## Whether `lateral` px along `along` (one side's direction along the wall) beside the door of `c`
## has a spot `WALL_SPOT_MIN` to `WALL_SPOT_MAX` out from the wall plane, on the navmesh within
## `SLOT_SNAP`, where a body may stand (`_slot_ok`; out of every other doorway's view unless
## `with_views`).
func _wall_spot_at(c: Dictionary, along: Vector2, lateral: float, with_views: bool) -> bool:
	var pos: Vector2 = c["pos"]
	var out: Vector2 = c["out"]
	var o := WALL_SPOT_MIN
	while o <= WALL_SPOT_MAX:
		var p := pos + out * o + along * lateral
		if (NavBuilder.snap(c["map"], p).distance_to(p) <= SLOT_SNAP
				and _slot_ok(c, p, with_views, false)):
			return true
		o += 2.0
	return false


## One side's wall band (`s`, 1 / -1 along the wall) of the stack of `c` (`_lay_slots`): the points
## of a `step` px grid beside the door, from a body past the jamb along the wall to the stack side
## room's corner (outdoors `OUTDOOR_REACH`), and `SLOT_OUT_MIN` to `SLOT_OUT_MAX` px out from the
## wall plane, within `SLOT_SNAP` of the navmesh, where a body may stand bar the other doorways'
## views (`_slot_ok`): each `{ point, row, lat, off, views }` (row 1 within `ROW1_DEPTH` of the wall
## plane; `off` how far from the wall standoff; `views` how many other doorways see it,
## `_views_on`).
func _band(c: Dictionary, s: int, step: float) -> Array:
	var pos: Vector2 = c["pos"]
	var out: Vector2 = c["out"]
	var along: Vector2 = (c["along"] as Vector2) * s
	var reach := OUTDOOR_REACH
	if c["from"] != "":
		reach = _edge_along(c["from_rect"], pos, along)
	var band: Array = []
	var lateral: float = c["half"] + SLOT_BODY
	while lateral <= reach:
		var o := SLOT_OUT_MIN
		while o <= SLOT_OUT_MAX:
			var p := pos + out * o + along * lateral
			if (NavBuilder.snap(c["map"], p).distance_to(p) <= SLOT_SNAP
					and _slot_ok(c, p, true, false)):
				band.append({
					"point": p, "row": 1 if o <= ROW1_DEPTH else 2, "lat": lateral,
					"off": absf(o - wall_standoff), "views": _views_on(c, p),
				})
			o += step
		lateral += step
	return band


## The file of one side of the stack of `c` from its wall band's points `band` (`_band`): the most
## bodies (at most `MAX_SLOTS`) they hold `stack_spacing` apart, found by a full search
## (`_most_spaced`) over them taken in order of preference (against the wall first, nearest the
## door, nearest the wall standoff), so among the layouts holding the most, the one nearest the door
## against the wall. Each `{ point, row }`, row 1 nearest the door first, then row 2.
func _pack(band: Array) -> Array:
	var cands := band.duplicate()
	cands.sort_custom(func(a, b):
		if a["row"] != b["row"]:
			return a["row"] < b["row"]
		if a["lat"] != b["lat"]:
			return a["lat"] < b["lat"]
		return a["off"] < b["off"])
	var picks: Array = _most_spaced(cands.map(func(x): return x["point"]), MAX_SLOTS).map(
		func(i): return cands[i],
	)
	picks.sort_custom(
		func(a, b): return a["row"] < b["row"] if a["row"] != b["row"] else a["lat"] < b["lat"],
	)
	return picks.map(func(x): return { "point": x["point"], "row": x["row"] })


## The layouts of a `views` way in (`_lay_slots`) from its wall band's points `bands` (`_band`, per
## side): for each first side (1 / -1), the slots of a stack of 1 to `MAX_SLOTS`
## (`[count - 1] -> [{ point, row, side, lat }]`). Of the spots beside the door, those seen from the
## fewest other doorways that hold the stack: the least number of doorways for which the spots seen
## from no more than that hold it (`_most_spaced` over them taken against the wall first, then a
## step out, the first side's file before the other's, each nearest the door first), the first
## `count` of them in that order; the most there are when even every spot does not hold it.
func _views_lays(bands: Dictionary) -> Dictionary:
	var spots := _view_spots(bands)
	var levels := _view_levels(spots)
	var lays := {}
	for first in [1, -1]:
		lays[first] = _lays_by_count(_held_by_level(_lay_order(spots, first), levels))
	_share_full(lays)
	return lays


## The spots of the wall bands `bands` (`_band`, per side) a `views` way in is laid from, side 1's
## first: each `{ point, side, row, views, lat, off }`.
func _view_spots(bands: Dictionary) -> Array:
	var spots: Array = []
	for s in [1, -1]:
		for x: Dictionary in bands[s]:
			spots.append({
				"point": x["point"],
				"side": s,
				"row": x["row"],
				"views": x["views"],
				"lat": x["lat"],
				"off": x["off"],
			})
	return spots


## The numbers of other doorways that see `spots` (`_view_spots`), each once, fewest first.
func _view_levels(spots: Array) -> Array:
	var levels: Array = []
	for x: Dictionary in spots:
		if not levels.has(int(x["views"])):
			levels.append(int(x["views"]))
	levels.sort()
	return levels


## `spots` (`_view_spots`) in the order a `views` way in first on side `first` takes them: against
## the wall first, then a step out; side `first`'s file before the other's; each nearest the door,
## then nearest the wall standoff.
func _lay_order(spots: Array, first: int) -> Array:
	var order := spots.duplicate()
	order.sort_custom(func(a, b):
		if a["row"] != b["row"]:
			return a["row"] < b["row"]
		if a["side"] != b["side"]:
			return a["side"] == first
		if a["lat"] != b["lat"]:
			return a["lat"] < b["lat"]
		return a["off"] < b["off"])
	return order


## Per level of `levels` (`_view_levels`), fewest first, the most of the spots of `order`
## (`_lay_order`) seen from no more doorways than that hold (`_most_spaced`), up to the first level
## whose spots hold a full stack.
func _held_by_level(order: Array, levels: Array) -> Array:
	var held: Array = []  # Per level, the most its spots hold.
	for v: int in levels:
		var level: Array = order.filter(func(x): return int(x["views"]) <= v)
		held.append(_most_spaced(level.map(func(x): return x["point"]), MAX_SLOTS).map(
			func(i): return level[i],
		))
		if (held[-1] as Array).size() >= MAX_SLOTS:
			break
	return held


## The slots of a stack of each size, 1 to `MAX_SLOTS` (`[count - 1] -> [{ point, row, side, lat
## }]`), from the picks per level `held` (`_held_by_level`): the first `count` of the fewest-seen
## level's picks that hold `count`, else of the last level's.
func _lays_by_count(held: Array) -> Array:
	var as_spot := func(x):
		return { "point": x["point"], "row": x["row"], "side": x["side"], "lat": x["lat"] }
	var per: Array = []
	for count in range(1, MAX_SLOTS + 1):
		var lay: Array = held[-1] if not held.is_empty() else []
		for picks: Array in held:
			if picks.size() >= count:
				lay = picks
				break
		per.append(lay.slice(0, count).map(as_spot))
	return per


## Spots too few for a full stack in `lays` (`_views_lays`, per first side): every stack that takes
## them all takes the same ones whichever side it starts on (the overflow stands clear of them),
## that side's file first.
func _share_full(lays: Dictionary) -> void:
	var full: Array = lays[1][MAX_SLOTS - 1]
	for count in range(maxi(full.size(), 1), MAX_SLOTS + 1 if full.size() < MAX_SLOTS else 0):
		var again := full.duplicate()
		again.sort_custom(func(a, b):
			if a["row"] != b["row"]:
				return a["row"] < b["row"]
			if a["side"] != b["side"]:
				return a["side"] == -1
			return a["lat"] < b["lat"])
		lays[-1][count - 1] = again


## The outs (px from the wall plane) a tail member is sought at against its doorway's wall, the wall
## standoff first.
func _row1_outs() -> Array:
	var outs := [wall_standoff, wall_standoff - 4.0, wall_standoff + 4.0, wall_standoff - 8.0,
		wall_standoff + 8.0, wall_standoff + 12.0, wall_standoff + 16.0]
	return outs.filter(func(o): return o >= ROW1_MIN and o <= ROW1_MAX)


## Whether a body of the stack of `c` may stand at navmesh point `p`: in the stack side's room (or
## outdoors, outside every room and out from the wall), out of every other doorway's funnel and
## (unless `with_views`) view, and reached from the stack side by a route that does not go through
## the doorway (`routed`: false leaves the route to the caller). `open` (the open-floor fallback):
## off the door's axis by a body and out of its funnel; else beside the door, clear of its opening.
func _slot_ok(c: Dictionary, p: Vector2, with_views: bool, open: bool, routed := true) -> bool:
	var rel: Vector2 = p - (c["pos"] as Vector2)
	var lateral := absf(rel.dot(c["along"]))
	var outward := rel.dot(c["out"])
	var on_axis_or_funnel: bool = (
		lateral < SLOT_BODY or (lateral < c["half"] and absf(outward) < StackClaim.FUNNEL_DEPTH)
	)
	if open and on_axis_or_funnel:
		return false
	if not open and lateral < c["half"] + SLOT_BODY:
		return false
	if (not _in_stack_side(c, p)
			or _in_other_funnel(c, p)
			or (not with_views and _views_on(c, p) > 0)):
		return false
	return not routed or _reached(c, p)


## Whether `p` lies on the stack side of `c`: inside its room's walls (`SLOT_ROOM_INSET`), or for an
## exterior door outside every room of the house and out from the doorway's wall plane.
func _in_stack_side(c: Dictionary, p: Vector2) -> bool:
	if c["from"] != "":
		return (c["from_rect"] as Rect2).grow(-SLOT_ROOM_INSET).has_point(p)
	if (p - (c["pos"] as Vector2)).dot(c["out"]) < SLOT_ROOM_INSET:
		return false
	return not _rooms.any(func(r): return (r["rect"] as Rect2).grow(SLOT_ROOM_INSET).has_point(p))


## Whether a route from the stack side of `c` (`SLOT_REACH_OUT` out from the wall plane) ends at `p`
## without going through the doorway.
func _reached(c: Dictionary, p: Vector2) -> bool:
	var key := p.round()
	if c["reach"].has(key):
		return c["reach"][key]
	var path := NavBuilder.route(c["map"], c["start"], p)
	var ok := not path.is_empty() and path[path.size() - 1].distance_to(p) <= SLOT_ROUTE_REACH
	if ok:
		var pos: Vector2 = c["pos"]
		var half: Vector2 = (c["along"] as Vector2) * float(c["half"])
		var pts: Array = [c["start"]] + Array(path)
		for i in range(1, pts.size()):
			if (Geometry2D.segment_intersects_segment(pts[i - 1], pts[i], pos - half, pos + half)
					!= null):
				ok = false
				break
	c["reach"][key] = ok
	return ok


## Whether `p` stands in the fatal funnel of a doorway other than `c`'s (within its width and
## `StackClaim.FUNNEL_DEPTH` of its wall plane).
func _in_other_funnel(c: Dictionary, p: Vector2) -> bool:
	for f: Dictionary in _door_frames():
		if f["id"] == c["id"]:
			continue
		var rel: Vector2 = p - (f["pos"] as Vector2)
		if (absf(rel.dot(f["along"])) < f["half"]
				and absf(rel.dot(f["out"])) < StackClaim.FUNNEL_DEPTH):
			return true
	return false


## How many doorways other than `c`'s see a body at `p` from inside a room they lead into: `p` lies
## out from that doorway's wall, inside its view (from the room's far corners past the jambs, the
## views' `door_view_depth` long, by `VIEW_MARGIN`), with a line clear of walls to the doorway.
func _views_on(c: Dictionary, p: Vector2) -> int:
	var ids := {}
	for f: Dictionary in _door_frames():
		if f["id"] == c["id"] or ids.has(f["id"]):
			continue
		var pos: Vector2 = f["pos"]
		if ((p - pos).dot(f["out"]) <= 0.0
				or not Geometry2D.is_point_in_polygon(p, f["quad"])
				or _edge_gap(f["quad"], p) < VIEW_MARGIN):
			continue
		var gap: Vector2 = (f["along"] as Vector2) * (float(f["half"]) - 4.0)
		for target: Vector2 in [pos, pos - gap, pos + gap]:
			if vision.wall_hit(c["space"], p, target).is_empty():
				ids[f["id"]] = true
				break
	return ids.size()


## Every way into a room through every doorway of the house, as a frame:
## `{ id, pos, half, out (away from the room), along, quad (the view out of it, unclipped) }`.
## Worked out once per house.
func _door_frames() -> Array:
	if not _frames.is_empty() or _openings.is_empty():
		return _frames
	for o in _openings:
		for k in o.get("rooms", []):
			var rect := _room_rect(str(k))
			if rect.size == Vector2.ZERO:
				continue
			_frames.append(_door_frame(o, rect))
	return _frames


## The frame of the way through doorway `o` into room `rect` (`_door_frames`).
func _door_frame(o: Dictionary, rect: Rect2) -> Dictionary:
	var pos: Vector2 = o["pos"]
	var out := -normal_into(rect, pos)
	var along := out.orthogonal()
	var half := float(o.get("width", 80.0)) * 0.5
	var corners := [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	corners.sort_custom(func(a, b): return (a - pos).dot(out) < (b - pos).dot(out))
	var jamb_a := pos - along * half
	var jamb_b := pos + along * half
	var for_a: Vector2 = (corners[0]
			if (corners[0] - pos).dot(along) > (corners[1] - pos).dot(along)
			else corners[1])
	var for_b: Vector2 = corners[1] if for_a == corners[0] else corners[0]
	var quad := PackedVector2Array([
		jamb_a, jamb_a + (jamb_a - for_a).normalized() * views.door_view_depth,
		jamb_b + (jamb_b - for_b).normalized() * views.door_view_depth, jamb_b,
	])
	return {
		"id": opening_id(o),
		"pos": pos,
		"half": half,
		"out": out,
		"along": along,
		"quad": quad,
	}


## The open floor of the stack side's room of `c` where a stack may stand past what the wall beside
## the door holds (`taken`, the wall's slots): points of a grid inside its walls (outdoors, a box
## out from the door `OUTDOOR_FLOOR` px along the wall either side and out from it), off the door's
## axis by a body, out of its funnel and every other doorway's (`_slot_ok`), `stack_spacing` from
## `taken` and each other, nearest the door's wall first and then farthest off its axis, reached
## from the stack side (`_reached`); at most `most`. `strict` (a short wall's overflow): off the
## wall band (`_in_band`) and out of every other doorway's view too. `exact` takes the most the
## floor holds (`_most_spaced`, on an `OPEN_GRID_FINE` grid when the coarse one holds fewer than
## `most`); otherwise the first that fit, in that order.
func _open_floor(c: Dictionary, exact: bool, taken: Array, most: int, strict := false) -> Array:
	var picks := _floor_picks(_floor_cands(c, OPEN_GRID, taken, strict), exact, most)
	if exact and picks.size() < most:
		picks = _floor_picks(_floor_cands(c, OPEN_GRID_FINE, taken, strict), exact, most)
	return picks


## The points of `_open_floor`'s grid of `step` px that may hold a slot (`taken` and `strict` as
## there), nearest the door's wall first and then farthest off its axis.
func _floor_cands(c: Dictionary, step: float, taken: Array, strict: bool) -> Array:
	var pos: Vector2 = c["pos"]
	var cands: Array = []
	for p: Vector2 in _floor_grid(c, step):
		var spaced := func(q): return (q as Vector2).distance_to(p) >= stack_spacing
		if (NavBuilder.snap(c["map"], p).distance_to(p) <= SLOT_SNAP
				and not (strict and _in_band(c, p))
				and taken.all(spaced) and _slot_ok(c, p, not strict, true)):
			cands.append(p)
	cands.sort_custom(func(a, b):
		var oa: float = (a - pos).dot(c["out"])
		var ob: float = (b - pos).dot(c["out"])
		if absf(oa - ob) > 0.5:
			return oa < ob
		return absf((a - pos).dot(c["along"])) > absf((b - pos).dot(c["along"])))
	return cands


## The grid of `step` px `_open_floor` is sought on: inside the stack side's room of `c` (by
## `SLOT_ROOM_INSET`), row by row; outdoors, a box out from the door `OUTDOOR_FLOOR` px along the
## wall either side and out from it.
func _floor_grid(c: Dictionary, step: float) -> Array:
	var grid: Array = []
	if c["from"] != "":
		var rect: Rect2 = (c["from_rect"] as Rect2).grow(-SLOT_ROOM_INSET)
		var y := rect.position.y
		while y <= rect.end.y:
			var x := rect.position.x
			while x <= rect.end.x:
				grid.append(Vector2(x, y))
				x += step
			y += step
		return grid
	var pos: Vector2 = c["pos"]
	var lat := -OUTDOOR_FLOOR
	while lat <= OUTDOOR_FLOOR:
		var o := SLOT_ROOM_INSET
		while o <= OUTDOOR_FLOOR:
			grid.append(pos + (c["out"] as Vector2) * o + (c["along"] as Vector2) * lat)
			o += step
		lat += step
	return grid


## At most `most` of `cands` (`_floor_cands`), each `stack_spacing` from the others: with `exact`,
## the most they hold (`_most_spaced`); otherwise the first that fit, in their order.
func _floor_picks(cands: Array, exact: bool, most: int) -> Array:
	if exact:
		return _most_spaced(cands, most).map(func(i): return cands[i])
	var picks: Array = []
	for p: Vector2 in cands:
		if (picks.size() < most
				and picks.all(func(q): return (q as Vector2).distance_to(p) >= stack_spacing)):
			picks.append(p)
	return picks


## Whether `p` lies in the wall band of `c` (`_band`): beside the door (a body past the jamb along
## the wall), `SLOT_OUT_MIN` to `SLOT_OUT_MAX` px out from the wall plane, on the stack side.
func _in_band(c: Dictionary, p: Vector2) -> bool:
	var rel: Vector2 = p - (c["pos"] as Vector2)
	var o := rel.dot(c["out"])
	return (absf(rel.dot(c["along"])) >= float(c["half"]) + SLOT_BODY
			and o >= SLOT_OUT_MIN
			and o <= SLOT_OUT_MAX
			and _in_stack_side(c, p))


## The indices of the most of `points` (at most `most`) each at least `stack_spacing` from the
## others: of the sets that large, the first in their order. An exact search (a Russian-doll
## search): from the last point back, `best[k]` is the most the points from `k` on hold (at most
## `most`), each found by asking whether the points after `k` free of it hold `best[k + 1]` more
## (`_holds`), which the counts already known bound tightly; then the first set in order of that
## many (`_holds` again, keeping it). Within `PACK_BUDGET` steps.
func _most_spaced(points: Array, most: int) -> Array:
	var n := points.size()
	if n == 0 or most <= 0:
		return []
	var best: Array = []
	best.resize(n + 1)
	best.fill(0)
	var search := { "points": points, "best": best, "budget": PACK_BUDGET }
	for k in range(n - 1, -1, -1):
		best[k] = best[k + 1]
		if (best[k + 1] < most
				and _holds(search, _free_after(points, k, range(k + 1, n)), best[k + 1], [])):
			best[k] = best[k + 1] + 1
	var chosen: Array = []
	_holds(search, range(n), best[0], chosen)
	return chosen


## Whether the points `cands` (indices into the search's `points`, ascending) hold `need` each
## `stack_spacing` apart, bounded by its `best` (`_most_spaced`: the points from an index on hold no
## more than `best` of it) and spending its `budget`; the set found is added to `chosen` (an empty
## array to ask only).
func _holds(search: Dictionary, cands: Array, need: int, chosen: Array) -> bool:
	if need <= 0:
		return true
	var best: Array = search["best"]
	for i in cands.size():
		if cands.size() - i < need or best[cands[i]] < need:
			return false
		search["budget"] -= 1
		if search["budget"] <= 0:
			return false
		var size := chosen.size()
		chosen.append(cands[i])
		var after := _free_after(search["points"], cands[i], cands.slice(i + 1))
		if _holds(search, after, need - 1, chosen):
			return true
		chosen.resize(size)
	return false


## Of the indices `cands`, those whose points lie at least `stack_spacing` from point `k`.
func _free_after(points: Array, k: int, cands: Array) -> Array:
	var p: Vector2 = points[k]
	var sq := stack_spacing * stack_spacing
	return cands.filter(func(j): return p.distance_squared_to(points[j]) >= sq)


## Where the tail of the stack of `c` holds (E20's fallback, `open_floor`): in the room it came by
## (the stack side's room's other doorway nearest this one), against its wall beside that doorway,
## taking turns either side of it; once that wall is full, the nearest spots of that room to the
## doorway on a `OPEN_GRID` px grid. Within `TAIL_REACH` of it, off its axis by a body and out of
## its funnel, on the navmesh; never nearer `stack_spacing` to the `open_slots` or each other. At
## most `MAX_SLOTS`.
func _tail_spots(c: Dictionary, open_slots: Array) -> Array:
	var best := _tail_door(c)
	if best.is_empty():
		return []
	var tc := _tail_context(c, best)
	var out := _tail_wall_spots(tc, open_slots)
	if out.size() < MAX_SLOTS:
		_tail_floor_fill(tc, open_slots, out)
	return out


## The frame of the doorway the tail of the stack of `c` holds by (`_tail_spots`): of the stack side
## room's other doorways, framed going into that room, the nearest this one. {} for none.
func _tail_door(c: Dictionary) -> Dictionary:
	var best := {}
	for f: Dictionary in _door_frames():
		if f["id"] == c["id"] or not (c["from_rect"] as Rect2).grow(1.0).has_point(f["pos"]):
			continue
		var into_from: bool = (c["from_rect"] as Rect2).has_point((f["pos"] as Vector2)
				- (f["out"] as Vector2) * 30.0)
		if not into_from:
			# The frame going into the other room: the tail stands on the far side, framed going
			# into the stack's room.
			continue
		if (best.is_empty()
				or (f["pos"] as Vector2).distance_to(c["pos"])
					< (best["pos"] as Vector2).distance_to(c["pos"])):
			best = f
	return best


## The tail's ground, as `_slot_ok` and `_in_stack_side` read a stack's (`_stack_context`): doorway
## frame `best` (`_tail_door`) of the stack of `c`, standing in the room beyond it.
func _tail_context(c: Dictionary, best: Dictionary) -> Dictionary:
	var beyond := _other_room(_opening(best["id"]), c["from"])
	return {
		"id": best["id"], "pos": best["pos"], "out": best["out"], "along": best["along"],
		"half": best["half"], "from": beyond, "from_rect": _room_rect(beyond), "map": c["map"],
		"space": c["space"], "reach": {},
	}


## The tail's spots against its doorway's wall (`tc`, `_tail_context`), taking turns either side of
## it, `stack_spacing` apart along the wall from `SLOT_JAMB` past the jamb: for each, the first of
## `_row1_outs` that is on the navmesh within `SLOT_SNAP`, within `TAIL_REACH` of the doorway, on
## its ground, and `stack_spacing` from `open_slots` and the spots before it. At most `MAX_SLOTS`.
func _tail_wall_spots(tc: Dictionary, open_slots: Array) -> Array:
	var out: Array = []
	for k in MAX_SLOTS:
		var s := 1 if k % 2 == 0 else -1
		var lateral := float(tc["half"]) + SLOT_JAMB + stack_spacing * floorf(k / 2.0)
		var p := _tail_wall_spot(tc, s, lateral, open_slots + out)
		if p != Vector2.INF:
			out.append(p)
	return out


## The first tail spot `lateral` px along the wall on side `s` of the tail's doorway (`tc`) at one
## of `_row1_outs`, at least `stack_spacing` from every point of `near` (`_tail_wall_spots`), or
## INF.
func _tail_wall_spot(tc: Dictionary, s: int, lateral: float, near: Array) -> Vector2:
	var pos: Vector2 = tc["pos"]
	for o: float in _row1_outs():
		var raw: Vector2 = (pos + (tc["out"] as Vector2) * o
				+ (tc["along"] as Vector2) * s * lateral)
		var p := NavBuilder.snap(tc["map"], raw)
		if (p.distance_to(raw) > SLOT_SNAP
				or p.distance_to(pos) > TAIL_REACH
				or not _in_stack_side(tc, p)):
			continue
		if near.any(func(q): return (q as Vector2).distance_to(p) < stack_spacing):
			continue
		return p
	return Vector2.INF


## Fill the tail spots `out` (`_tail_wall_spots`) up to `MAX_SLOTS` from the tail's floor nearest
## its doorway (`_tail_grid`), each `stack_spacing` from `open_slots` and the spots before it.
func _tail_floor_fill(tc: Dictionary, open_slots: Array, out: Array) -> void:
	for p: Vector2 in _tail_grid(tc):
		if out.size() >= MAX_SLOTS:
			break
		if not (open_slots + out).any(
				func(q): return (q as Vector2).distance_to(p) < stack_spacing,
		):
			out.append(p)


## The points of an `OPEN_GRID` px grid round the tail's doorway (`tc`) where a tail member may
## stand (`_tail_floor_ok`), nearest the doorway first.
func _tail_grid(tc: Dictionary) -> Array:
	var pos: Vector2 = tc["pos"]
	var grid: Array = []
	var lat := -TAIL_REACH
	while lat <= TAIL_REACH:
		var o := SLOT_ROOM_INSET
		while o <= TAIL_REACH:
			var p: Vector2 = (pos + (tc["out"] as Vector2) * o + (tc["along"] as Vector2) * lat)
			if _tail_floor_ok(tc, p, lat, o):
				grid.append(p)
			o += OPEN_GRID
		lat += OPEN_GRID
	grid.sort_custom(func(a, b): return a.distance_squared_to(pos) < b.distance_squared_to(pos))
	return grid


## Whether the tail may stand at grid point `p` (`lat` px along the wall, `o` out from it) of its
## doorway (`tc`): within `TAIL_REACH` of it, off its axis by a body and out of its funnel, on the
## navmesh within `SLOT_SNAP`, on its ground and out of every other doorway's funnel.
func _tail_floor_ok(tc: Dictionary, p: Vector2, lat: float, o: float) -> bool:
	return (p.distance_to(tc["pos"]) <= TAIL_REACH
			and absf(lat) >= SLOT_BODY
			and (absf(lat) >= float(tc["half"]) or o >= StackClaim.FUNNEL_DEPTH)
			and NavBuilder.snap(tc["map"], p).distance_to(p) <= SLOT_SNAP
			and _in_stack_side(tc, p)
			and not _in_other_funnel(tc, p))


## How far (px) from `p` along the axis `dir` to the edge of `rect`.
func _edge_along(rect: Rect2, p: Vector2, dir: Vector2) -> float:
	if dir.x > 0.5:
		return rect.end.x - p.x
	if dir.x < -0.5:
		return p.x - rect.position.x
	if dir.y > 0.5:
		return rect.end.y - p.y
	return p.y - rect.position.y


## How far (px) `p` lies from the nearest edge of polygon `poly`.
func _edge_gap(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in poly.size():
		best = minf(
			best,
			p.distance_to(Geometry2D.get_closest_point_to_segment(
				p, poly[i], poly[(i + 1) % poly.size()],
			)),
		)
	return best


## The `count` slots of a `views` layout (`_lay_slots`, `_views_lays`), its first side `side`: of
## the spots beside the door, those seen from the fewest other doorways that hold `count` at
## `stack_spacing`, side `side`'s file nearest the door first, then the other's, then the second
## files. Each `{ point, row, side }`.
static func views_layout(g: Dictionary, count: int, side: int) -> Array:
	var per: Array = (g.get("views_lays", {}) as Dictionary).get(side if side != 0 else 1, [])
	return per[clampi(count, 1, per.size()) - 1] if not per.is_empty() else []


## The unit normal pointing into `rect` from the edge door `pos` lies on (the nearest edge;
## `AgentDoorViews.normal_into`). Also read by the squad (`ai/team/squad.gd`), which tells which
## side of a doorway's wall a leader clicked.
static func normal_into(rect: Rect2, pos: Vector2) -> Vector2:
	return AgentDoorViews.normal_into(rect, pos)


## How much of the room's wall runs from door `pos` toward `dir` (to the room's corner on that
## side).
func _wall_length(rect: Rect2, pos: Vector2, dir: Vector2) -> float:
	if absf(dir.x) > 0.5:
		return (rect.end.x - pos.x) if dir.x > 0.0 else (pos.x - rect.position.x)
	return (rect.end.y - pos.y) if dir.y > 0.0 else (pos.y - rect.position.y)


## Whether the line `from` → `to` is clear for sight (over low cover; walls and tall furniture block
## it).
func _sees(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	return space == null or vision.can_see(from, to - from, to, space, [])


# --- The sides of a stack (its claims and layout: stack/door_stack.gd) -------------------------


## The side of the door (1 / -1 along its wall) point `p` is on.
static func side_of(g: Dictionary, p: Vector2) -> int:
	return 1 if (p - (g["pos"] as Vector2)).dot(g["along"]) >= 0.0 else -1


## The side a member standing at `from` stacks on in `stack` (a doorway's `DoorStack`,
## stack/door_stack.gd) (E19): the team's side (`team_side`), unless its way to the first slot on it
## crosses the doorway's view (`cuts_view`): then its own side, and the stack is split across the
## door.
func stack_side_from(
	stack: RefCounted,
	from: Vector2,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> int:
	var g: Dictionary = stack.geometry
	var team_side: int = stack.team_side(from)
	var own := side_of(g, from)
	var first := StackLayout.point(g, [], 1, StackLayout.side_for(g, [], 1, team_side))
	if own == team_side or first == Vector2.INF or not cuts_view(g, from, first, map, space):
		return team_side
	return own


## Whether the walk from `from` to `to` crosses the view of doorway `g` (E19): it starts outside the
## view (`views.door_view`) and its plain route crosses the door's axis inside it, in front of the
## door. A walk that starts in the view, or goes round it, does not.
func cuts_view(
	g: Dictionary,
	from: Vector2,
	to: Vector2,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> bool:
	var view: PackedVector2Array = views.door_view(g["id"], g["into"], map, space)
	if view.is_empty() or Geometry2D.is_point_in_polygon(from, view):
		return false
	var pos: Vector2 = g["pos"]
	var out: Vector2 = g["out"]
	var axis := PackedVector2Array([
		pos + out * AgentDoorViews.VIEW_APEX_OUT,
		pos + out * views.door_view_depth,
	])
	var route: Array = [from] + Array(NavBuilder.route(map, from, to))
	for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(axis, view):
		if _crosses(route, piece):
			return true
	return false


## Whether polyline `route` crosses polyline `piece` anywhere.
func _crosses(route: Array, piece: PackedVector2Array) -> bool:
	for i in range(1, route.size()):
		for j in range(1, piece.size()):
			if Geometry2D.segment_intersects_segment(route[i - 1], route[i], piece[j - 1],
					piece[j]) != null:
				return true
	return false
