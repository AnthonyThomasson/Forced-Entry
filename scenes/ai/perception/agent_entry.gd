extends RefCounted

## AI PERCEPTION sub-domain — ENTRY GEOMETRY. What an NPC knows about getting through a doorway into a room
## (`docs/tactical-entry.md`): for each opening of the house, entered into one of the rooms it joins, the door's
## frame (its outward normal and the axis along its wall), the stack slots in single file against the wall on
## either side, the pie arc a point man sweeps from, and the four corners of the room behind, each tagged hard
## (unseen from just outside the threshold) or soft. Plus the team's claims on an opening, read off allies'
## radio callouts (the same claim pattern as a flank side, `agent_tactics.side_holder`).
##
## Each doorway's VIEW and the walk that keeps out of the views are `agent_door_views.gd` (`views`), which a split stack reads
## (`cuts_view`, `docs/tactical-entry.md` E19).
##
## Pure geometry over the house's openings (Main's `WorldGen.get_openings`, injected), its rooms, the nav map
## (slots and pie points are snapped onto it) and sight rays (via the vision sense). The walls never move, so
## an opening's geometry is built once, the first time it is asked for on a baked map, and kept. No policy: it
## never decides which door, which slot or when to go.

## How far (px) outside the threshold the "entry point" is that a corner is judged hard or soft from.
const SnapshotVocab := preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const AgentDoorViews := preload("res://scenes/ai/perception/agent_door_views.gd")
const ENTRY_POINT_DEPTH := 24.0
## Slots worked out per side: a fuller team queues in the last one.
const MAX_SLOTS := 6
## How many bodies go into a room too small for the team (`short_room`): the point and the second, who take its corners.
const SHORT_ROOM_CAPACITY := 2
## A defend spot (`defend_spot`, `docs/leadership.md` D2): how far back from its doorway's wall (px) it is sought, at best `DEFEND_DEPTH`...
const DEFEND_DEPTHS := [60.0, 90.0, 120.0, 150.0]
const DEFEND_DEPTH := 100.0
## ... and how far along the wall past the doorway's jamb (px), at best `DEFEND_LATERAL`: off the doorway's axis, out of its funnel.
const DEFEND_LATERALS := [30.0, 50.0, 75.0, 100.0]
const DEFEND_LATERAL := 50.0
## Inset (px) of a defend spot from the room's walls (a body and half a wall), and the most a snap onto the navmesh may move it.
const DEFEND_INSET := 22.0
const DEFEND_SNAP := 10.0
## A spot within a body (px) of a doorway's width and closer than `DEFEND_FUNNEL_DEPTH` (px) to its wall stands in its fatal funnel.
const DEFEND_BODY := 14.0
const DEFEND_FUNNEL_DEPTH := 200.0
## Where (px into the room from the doorway's centre) a defender's sight line to its doorway ends.
const DEFEND_DOOR_IN := 8.0
## An ambush post (`ambush_spot`, `docs/leadership.md` LD15): how far back from the doorway's wall (px) it is sought, at best
## `AMBUSH_DEPTH` (the cover depth of a room's holders, E8)...
const AMBUSH_DEPTHS := [40.0, 70.0, 100.0, 130.0, 160.0]
const AMBUSH_DEPTH := 110.0
## ... and how far along the wall past the doorway's jamb (px): well along it, where the wall hides the post from a stack outside.
const AMBUSH_LATERALS := [30.0, 60.0, 90.0, 120.0, 150.0, 180.0, 220.0, 260.0]
## Inset (px) of an ambush post from the room's walls.
const AMBUSH_INSET := 22.0
## How far apart (px) two ambushers' posts on one side of the doorway stand (a stack's slot spacing: clear of each other's footprint).
const AMBUSH_SPACING := 44.0
## How far (px) round its post an ambusher may stand once there (it stops within a reach of the spot, `Behavior.DEFEND_REACH`, and a
## little): a post is hidden only when it is hidden there too.
const AMBUSH_SLACK := 12.0
## Where a stack may stand (`_lay_slots`, E20 to E22): a slot stays this far (px) inside its room's rect (half a wall and most of a body),
## within this far of where the navmesh snaps it, reached from this far out from the wall plane (ending within `SLOT_ROUTE_REACH`).
const SLOT_ROOM_INSET := 16.0
const SLOT_SNAP := 3.0
const SLOT_REACH_OUT := 60.0
const SLOT_ROUTE_REACH := 6.0
## A body's radius (px): a slot against the wall stands clear of the doorway's opening by it, one on the open floor off its axis.
const SLOT_BODY := 14.0
## Sides of the polygon a body is carved as (`slot_reach`).
const BODY_SEGMENTS := 10
## A route of `slot_reach` that ends short of its point still reaches it by a last leg walked plain, as a walk does (`Locomotion` `LAST_LEG`
## and `PASS_CLEARANCE`): the leg on at most this long (px), passing no body closer than `SLOT_PASS` (px).
const SLOT_LAST_LEG := 64.0
const SLOT_PASS := 32.0
## How far (px) past the jamb the first slot of a file stands, and the step (px) a side's wall is walked along in.
const SLOT_JAMB := 18.0
const SLOT_STEP := 4.0
## A tail member's outs against its doorway's wall (`_row1_outs`): between these (px) out from the wall plane.
const ROW1_MIN := 18.0
const ROW1_MAX := 46.0
## A spot against the wall (`_has_wall_spot`): between these (px) out from the wall plane, a body's standoff give or take a few px.
const WALL_SPOT_MIN := 24.0
const WALL_SPOT_MAX := 38.0
## The band beside the door a wall stack's slots are sought in (px out from the wall plane: against it to a step out), and the depth
## within which a slot counts as against the wall (row 1; past it row 2, the second file).
const SLOT_OUT_MIN := 14.0
const SLOT_OUT_MAX := 110.0
const ROW1_DEPTH := 50.0
## The grid (px) a wall stack's slots are first sought on; a wall short of a full stack is sought again on the `SLOT_STEP` grid.
const WALL_GRID := 8.0
## A doorway's fatal funnel: within its width and this far (px) of its wall plane, either side.
const FUNNEL_DEPTH := 40.0
## A body counts in a doorway's view only this far (px) inside its edges.
const VIEW_MARGIN := 10.0
## Outdoors, how far (px) along the house's wall from the doorway a file may run.
const OUTDOOR_REACH := 320.0
## The open-floor fallback: the grid (px) its spots are sought on, finer (`OPEN_GRID_FINE`) for a dead end whose room holds fewer than a full
## stack on it; the most search steps the dead end's packing takes; how far (px) from its doorway a tail member holds.
const OPEN_GRID := 8.0
const OPEN_GRID_FINE := 4.0
## Outdoors, how far (px) along the house's wall either side of the door, and out from it, a short wall's overflow is sought.
const OUTDOOR_FLOOR := 300.0
const PACK_BUDGET := 200000
const TAIL_REACH := 140.0

var vision: RefCounted = AgentVision.new()  ## The sight sense (sight rays over low cover): the perception hands in its own.
var views: RefCounted = AgentDoorViews.new()  ## The doorway views and the walk round them: the perception hands in its own.
var stack_spacing: float = 44.0       ## Distance (px) between neighbouring stack slots: clear of a neighbour's footprint.
var wall_standoff: float = 28.0       ## Distance (px) of a stack slot off the wall's centreline.
var pie_radius: float = 100.0         ## Distance (px) from the threshold of the pie arc a point man sweeps from.
var pie_steps: int = 5                ## Points on the pie arc (angle steps).
var corner_inset: float = 40.0        ## Inset (px) of a corner point from the room's two walls.
var short_room: float = 150.0         ## A room with a side under this (px) is too small for the team: two go in (E13).

var _openings: Array = []             ## The house's doorways (`{ pos, width, front, exit, rooms }`), as injected.
var _rooms: Array = []                ## The house's rooms (`{ key, type, rect }`).
var _cache := {}                      ## "<opening id>><room key>" -> the geometry of that entry.
var _house := ""                      ## The house handed in (`set_house`), as a hash: what the shared geometry is keyed by.
## The geometry every NPC on a navigation map shares (map RID -> "<house and tuning>|<opening id>><room key>" -> geometry): it is the
## house's and the map's, not the NPC's, and laying a doorway's slots is costly (`_lay_slots`), so it is laid once per map, not once per NPC.
## Forgotten with the map's planning region.
static var _shared := {}
## The physics frame `warm_geometry` last laid a doorway in (one a frame, among every NPC).
static var _warmed_frame := -1
var _warm_done_in := {}               ## The shared geometry (`_shared_on`) in which `warm_geometry` last found every way in laid...
var _warm_done_for: Array = []        ## ... for these `_tuning_inputs()` (the house and the tunables): nothing to look for until either changes.
var _posts := {}                      ## "<opening id>><room key>" -> the ambush post candidates of that doorway, room side (`_ambush_posts`).
var _frames: Array = []               ## Every way into a room through every doorway, framed (`_door_frames`).


## Hand in the house: its doorways and rooms (to the views too). Forgets the cached geometry when they changed.
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


## The stable id of doorway `o` ("door_<x>_<y>", its rounded world position): what the snapshot's options, the
## behaviour and the radio call it (`AgentDoorViews.opening_id`).
static func opening_id(o: Dictionary) -> String:
	return AgentDoorViews.opening_id(o)


## The house's doorway whose `opening_id` is `id`, or `{}`.
func _opening(id: String) -> Dictionary:
	for o in _openings:
		if opening_id(o) == id:
			return o
	return {}


## The doorways an NPC standing in room `here_key` ("" = outside) can go through into a room: an outer door from
## outside, any door of its room into the room on the far side. Each `{ id, into, pos, width, front }`.
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
		out.append({ "id": opening_id(o), "into": into, "pos": o["pos"], "width": float(o.get("width", 80.0)),
			"front": bool(o.get("front", false)) })
	return out


## Every doorway of room `room_key`, outer doors (to outside) included: where something can come from. Each
## `{ id, pos, width }`, in the order the house lists them. A resting NPC watches these (`Watch.idle_gaze`).
func room_doorways(room_key: String) -> Array:
	var out: Array = []
	for o in _openings:
		if room_key in (o.get("rooms", []) as Array).map(func(k): return str(k)):
			out.append({ "id": opening_id(o), "pos": o["pos"], "width": float(o.get("width", 80.0)) })
	return out


## Where member `nth` of `count` holds room `room_key` it was ordered to defend (`docs/leadership.md` LD8, D2), and what it watches: the
## members share out the room's doorways (sorted by id; member `nth` takes doorway `nth` mod their number, the extras doubling up on
## the other side of it), each standing back in the room off its doorway's axis, out of every doorway's fatal funnel, with a sight line
## to it and, where there is one, low furniture between (cover it sees over); a lone member takes the spot from which it sees the most
## doorways. `{ spot, door, door_pos, doors }`: `door` is the id of the doorway it keeps its gun on ("" for a lone member of a room with
## several: it turns among `doors`, the room's doorways), `door_pos` that doorway's centre (INF for none). {} for a room it does not know.
func defend_spot(room_key: String, nth: int, count: int, map: RID, space) -> Dictionary:
	var rect := _room_rect(room_key)
	if rect.size == Vector2.ZERO:
		return {}
	var doors := room_doorways(room_key)
	doors.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	if doors.is_empty():
		return { "spot": NavBuilder.snap(map, rect.get_center()), "door": "", "door_pos": Vector2.INF, "doors": doors }
	var lone := count <= 1 and doors.size() > 1
	var own: Dictionary = doors[posmod(nth, doors.size())]
	var round_no := int(float(nth) / float(doors.size()))
	var best := {}
	for d in (doors if lone else [own]):
		var pos: Vector2 = d["pos"]
		var width := float(d["width"])
		var into := normal_into(rect, pos)
		var along := into.orthogonal()
		var first := 1 if _wall_length(rect, pos, along) >= _wall_length(rect, pos, -along) else -1
		var wanted := first if round_no % 2 == 0 else -first
		for depth in DEFEND_DEPTHS:
			for lateral in DEFEND_LATERALS:
				for s in [1, -1]:
					var raw: Vector2 = pos + into * depth + along * s * (width * 0.5 + lateral)
					var c := _defend_candidate(rect, raw, doors, map, space)
					if c.is_empty():
						continue
					var score: float = absf(depth - DEFEND_DEPTH) + absf(lateral - DEFEND_LATERAL) + float(c["funnel"]) * 1000.0
					if lone:
						score -= float(c["sees"]) * 2000.0
					else:
						score += (0.0 if c["sees_door"].has(d["id"]) else 3000.0) + (0.0 if s == wanted else 400.0)
					score += 0.0 if c["cover"].has(d["id"]) or (lone and not c["cover"].is_empty()) else 300.0
					if best.is_empty() or score < float(best["score"]):
						best = { "score": score, "spot": c["spot"] }
	if best.is_empty():
		return { "spot": NavBuilder.snap(map, rect.get_center()), "door": "" if lone else String(own["id"]),
			"door_pos": Vector2.INF if lone else own["pos"], "doors": doors }
	return { "spot": best["spot"], "door": "" if lone else String(own["id"]), "door_pos": Vector2.INF if lone else own["pos"], "doors": doors }


## A candidate defend spot near `raw` (`defend_spot`): snapped onto the navmesh inside the room (dropped when the snap moves it off),
## with `funnel` (how many of the room's `doors` it stands in the fatal funnel of), `sees` / `sees_door` (the doorways it has a sight line
## to, how many and which) and `cover` (the ids of those with low furniture on the line, which it sees over). {} when it is no spot.
func _defend_candidate(rect: Rect2, raw: Vector2, doors: Array, map: RID, space) -> Dictionary:
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
		if absf(off.dot(into.orthogonal())) < float(d["width"]) * 0.5 + DEFEND_BODY and off.dot(into) < DEFEND_FUNNEL_DEPTH:
			funnel += 1
		var aim := pos + into * DEFEND_DOOR_IN
		if _sees(space, p, aim):
			sees[d["id"]] = true
			var hit: Dictionary = vision.raycast(space, p, aim, []) if space != null else {}
			if hit.get("collider") is RigidBody2D:
				cover[d["id"]] = true
	return { "spot": p, "funnel": funnel, "sees": sees.size(), "sees_door": sees, "cover": cover }


## Where member `nth` of `count` ordered to ambush doorway `id` from room `room_key` waits (`docs/leadership.md` LD15, D17): a post in the
## room, off the doorway's axis, back from its wall and inside the room's walls, out of the fatal funnel of every doorway of the room, with a
## sight line to the threshold, and unseen from outside: no sight line to it from any slot or pie step of an entry into the room by that
## doorway (`geometry(id, room_key)`). Among the hidden posts, one with low furniture on its line to the threshold (cover it sees over) wins,
## then the nearest `AMBUSH_DEPTH` back; with none hidden, the least seen. Hidden means hidden wherever within `AMBUSH_SLACK` of the post
## the ambusher stops. Members alternate sides of the axis (member `nth`: the side with
## more wall first), and two on one side stand `AMBUSH_SPACING` apart. `{ spot, door_pos, seen }`: `door_pos` is the doorway's centre, where
## its gun goes, `seen` how many of those slots and pie steps see the post (0: hidden). {} for a doorway or room it does not know, or no post.
func ambush_spot(id: String, room_key: String, nth: int, count: int, map: RID, space) -> Dictionary:
	var g := geometry(id, room_key, map, space)
	if g.is_empty():
		return {}
	var posts := _ambush_posts(g, room_key, map, space)
	if posts.is_empty():
		return {}
	var rect: Rect2 = g["room"]
	var along: Vector2 = g["along"]
	var first := 1 if _wall_length(rect, g["pos"], along) >= _wall_length(rect, g["pos"], -along) else -1
	var taken: Array = []
	var pick := {}
	for k in mini(nth, maxi(count - 1, 0)) + 1:
		var wanted := first if k % 2 == 0 else -first
		pick = {}
		for c: Dictionary in posts:
			if taken.any(func(t): return (t as Vector2).distance_to(c["spot"]) < AMBUSH_SPACING):
				continue
			var score := float(c["score"]) + (0.0 if int(c["side"]) == wanted else 50000.0)
			if pick.is_empty() or score < float(pick["score"]):
				pick = { "score": score, "spot": c["spot"], "seen": c["seen"] }
		if pick.is_empty():
			return {}
		taken.append(pick["spot"])
	return { "spot": pick["spot"], "door_pos": g["pos"], "seen": pick["seen"] }


## The candidate ambush posts of entry geometry `g` (into room `room_key`, the side the ambusher waits on), kept once worked out on a baked
## map: `{ spot, side, seen, score }`, `side` the side of the axis it lies on, `seen` how many slots and pie steps see it, `score` the post's
## rank before the side is weighed (the lower the better: hidden first, out of every funnel, cover on its line, then nearest `AMBUSH_DEPTH`).
func _ambush_posts(g: Dictionary, room_key: String, map: RID, space) -> Array:
	var key := "%s>%s" % [g["id"], room_key]
	if _posts.has(key):
		return _posts[key]
	var rect: Rect2 = g["room"]
	var pos: Vector2 = g["pos"]
	var into := -(g["out"] as Vector2)
	var along: Vector2 = g["along"]
	var width := float(g["width"])
	var doors := room_doorways(room_key)
	var observers: Array = (g["lookouts"] as Array).duplicate()
	for side in [1, -1]:
		observers.append_array(g["slots"][side])
		observers.append_array(g["pie"][side])
	var out: Array = []
	for depth: float in AMBUSH_DEPTHS:
		for lateral: float in AMBUSH_LATERALS:
			for s in [1, -1]:
				var raw: Vector2 = pos + into * depth + along * s * (width * 0.5 + lateral)
				if not rect.grow(-AMBUSH_INSET).has_point(raw):
					continue
				var c := _defend_candidate(rect, raw, doors, map, space)
				if c.is_empty() or not c["sees_door"].has(g["id"]):
					continue
				var p: Vector2 = c["spot"]
				if absf((p - pos).dot(along)) < width * 0.5 + DEFEND_BODY:
					continue  # On the axis.
				var seen := observers.filter(func(o): return _sees_from(space, o, p)).size()
				if seen == 0:
					for k in 8:
						var q := p + Vector2.from_angle(TAU * k / 8.0) * AMBUSH_SLACK
						seen = maxi(seen, observers.filter(func(o): return _sees_from(space, o, q)).size())
				var score := float(seen) * 1000.0 + float(c["funnel"]) * 500.0 + (0.0 if c["cover"].has(g["id"]) else 300.0) \
					+ absf(depth - AMBUSH_DEPTH)
				out.append({ "spot": p, "side": s, "seen": seen, "score": score })
	if NavBuilder.ready(map):
		_posts[key] = out  # Only keep what was snapped onto a baked map.
	return out


## Whether someone standing at `from` sees `to` (over low cover; walls and tall furniture block it), at any distance and whichever way it
## faces: what a stack outside could see of a post once it looks.
func _sees_from(space, from: Vector2, to: Vector2) -> bool:
	return space == null or vision.sight_hit(space, from, to, []).is_empty()


## The doorways out of room `room_key` (one already cleared) that lead on into another room that `is_cleared` (a Callable
## on the room key) says is not cleared, other than doorway `exclude_id` (the one the NPC came in by). Doors to outside
## are left out. Each `{ id, into, pos, width }`. What the team covers once it has cleared a room (E8).
func watch_doors(room_key: String, exclude_id: String, is_cleared: Callable) -> Array:
	return entries_from(room_key).filter(func(e): return e["id"] != exclude_id and not is_cleared.call(e["into"]))


## Whether a walk from `from` reaches `to` with a body standing at each of `bodies` (world points: the body a walk is held by and the others
## at rest it sees) in its way at body width (`SLOT_BODY`, and `NavBuilder.OBSTACLE_MARGIN` round it as the steering map carves a body at
## rest), by any way at all: 1 when the route on the planning map with them carved (an avoid map of its own, kept per set of bodies) ends
## within `AgentDoorViews.AVOID_REACH` of `to`, or within `SLOT_LAST_LEG` of it with the plain way on from there that long at most and passing none of
## `bodies` closer than `SLOT_PASS` (a slot between two taken ones lies inside their carved margins, and a walk goes in by that last leg);
## 0 when it does not, -1 while that map is still being baked (asking starts the bake). What an entry asks before it reads a hold as sealing
## its slot for good (E2). 1 when there is no planning region to carve.
func slot_reach(from: Vector2, to: Vector2, map: RID, bodies: Array) -> int:
	var region := NavBuilder.planning_region(map)
	if region == null or not NavBuilder.ready(map):
		return 1
	var keys: Array = []
	var holes: Array = []
	for b: Vector2 in bodies:
		keys.append("%d,%d" % [int(b.x / SLOT_STEP), int(b.y / SLOT_STEP)])
		var hole := PackedVector2Array()
		for i in BODY_SEGMENTS:
			hole.append(b + Vector2.from_angle(TAU * i / BODY_SEGMENTS) * (SLOT_BODY + NavBuilder.OBSTACLE_MARGIN))
		holes.append(hole)
	keys.sort()
	var carved := NavBuilder.avoid_map(region, "bodies:" + ";".join(keys), holes)
	if not carved.is_valid() or not NavBuilder.ready(carved):
		return -1
	var path := NavBuilder.route(carved, from, to)
	if path.is_empty():
		return 0
	var end := path[path.size() - 1]
	var goal := NavBuilder.snap(map, to)
	if end.distance_to(goal) <= AgentDoorViews.AVOID_REACH:
		return 1
	var leg := NavBuilder.route(map, end, goal)
	if end.distance_to(goal) > SLOT_LAST_LEG or NavBuilder.path_length(leg) > SLOT_LAST_LEG:
		return 0
	for b: Vector2 in bodies:
		var limit := minf(SLOT_PASS, end.distance_to(b) - 1.0)  # One the route's end already stands by, and walks away from, is no bar.
		for i in range(1, leg.size()):
			if Geometry2D.get_closest_point_to_segment(b, leg[i - 1], leg[i]).distance_to(b) < limit:
				return 0
	return 1


## The rect of room `key`, or an empty Rect2.
func _room_rect(key: String) -> Rect2:
	return SnapshotVocab.room_by_key(_rooms, key).get("rect", Rect2())


## The geometry of going through opening `id` into room `into`, or {} when either is unknown. Built once on a
## baked nav map (`map`) and kept: { id, into, pos, width, out (unit normal away from the room), along (unit
## axis along the wall), wall: { 1: px, -1: px } (the room's wall either side of the door), side (the side with
## more wall to stack against, 0 when even), slots: { 1: [..], -1: [..] } (stack slots, nearest the door first),
## pie: { 1: [..], -1: [..] } (pie arc points, from the wall toward the axis), lookouts (the slots and pie points as laid out, before
## they are snapped onto the navmesh: where an entry's stack and point stand, or near it), corners: [{ pos, near, side, hard }],
## room (the room's rect), capacity (how many may go in: 2 for a short room, else MAX_SLOTS) }.
func geometry(id: String, into: String, map: RID, space) -> Dictionary:
	var key := "%s>%s" % [id, into]
	if _cache.has(key):
		return _cache[key]
	var shared := _shared_on(map)
	var shared_key := "%s|%s" % [_tuning(), key]
	if shared.has(shared_key):
		_cache[key] = shared[shared_key]
		return _cache[key]
	var opening := _opening(id)
	var room := SnapshotVocab.room_by_key(_rooms, into)
	if opening.is_empty() or room.is_empty():
		return {}
	var g := _build(opening, room, map, space)
	if NavBuilder.ready(map):
		_cache[key] = g  # Only keep what was snapped onto a baked map.
		shared[shared_key] = g
	return g


## Lay one way in by a doorway of the house whose geometry nobody on `map` has yet (`geometry`), at most one a physics frame among every
## NPC, once the map is baked: called every SEE pass, so the doorways are laid in the first frames after the bake rather than in the
## middle of a decision. Once a pass finds them all laid it looks no more (`_warm_done_in`) until the house, a tunable or the map's shared
## geometry changes.
func warm_geometry(map: RID, space) -> void:
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


## The geometry shared on `map` (`_shared`), made the first time it is asked for and dropped when the map's planning region leaves the
## tree; a map with no planning region shares nothing (an empty dictionary each time).
func _shared_on(map: RID) -> Dictionary:
	if _shared.has(map):
		return _shared[map]
	var region := NavBuilder.planning_region(map)
	if region == null:
		return {}
	_shared[map] = {}
	region.tree_exited.connect(func() -> void: _shared.erase(map), CONNECT_ONE_SHOT)
	return _shared[map]


## What a doorway's geometry is laid from besides the map: the house and the tunables `_build` reads (the stack's spacing and standoff,
## the pie, the corners, the short room, the view's depth, and the sight that tells a hard corner). Cheap to make and compare, so
## `warm_geometry` checks it every pass; `_tuning()` is the same as the key the shared geometry is filed under.
func _tuning_inputs() -> Array:
	var out: Array = [_house, stack_spacing, wall_standoff, pie_radius, pie_steps, corner_inset, short_room, views.door_view_depth]
	out.append_array([vision.enabled, vision.view_distance, vision.fov_degrees, vision.awareness_radius, vision.see_over_coverage])
	return out


## `_tuning_inputs()` as the shared geometry's key prefix.
func _tuning() -> String:
	return str(_tuning_inputs())


## Lay out one entry: the door's frame from the room edge it sits on, then slots, pie arc and corners.
func _build(opening: Dictionary, room: Dictionary, map: RID, space) -> Dictionary:
	var pos: Vector2 = opening["pos"]
	var width := float(opening.get("width", 80.0))
	var rect: Rect2 = room["rect"]
	var inward := normal_into(rect, pos)
	var out := -inward
	var along := out.orthogonal()
	var wall := { 1: _wall_length(rect, pos, along), -1: _wall_length(rect, pos, -along) }
	var side := 0
	if absf(wall[1] - wall[-1]) >= 1.0:
		side = 1 if wall[1] > wall[-1] else -1
	var slots := {}
	var pie := {}
	var lookouts: Array = []
	for s in [1, -1]:
		var row: Array = []
		for k in MAX_SLOTS:
			var lateral := width * 0.5 + 18.0 + k * stack_spacing
			lookouts.append(pos + out * wall_standoff + along * s * lateral)
			row.append(NavBuilder.snap(map, lookouts[-1]))
		slots[s] = row
		var arc: Array = []
		var steps := maxi(pie_steps, 2)
		for i in steps:
			# From 55° off the door's axis (clear of the stack against the wall) toward it (25° off), on side `s`.
			var theta := deg_to_rad(lerpf(55.0, 25.0, float(i) / float(steps - 1)))
			lookouts.append(pos + out * cos(theta) * pie_radius + along * s * sin(theta) * pie_radius)
			arc.append(NavBuilder.snap(map, lookouts[-1]))
		pie[s] = arc
	var inset := minf(corner_inset, minf(rect.size.x, rect.size.y) * 0.25)
	var inner := rect.grow(-inset)
	var entry_point := pos + out * ENTRY_POINT_DEPTH
	var corners: Array = []
	var depth_max := -INF
	var raw := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
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
	var g := { "id": opening_id(opening), "into": str(room["key"]), "pos": pos, "width": width, "out": out,
		"along": along, "wall": wall, "side": side, "slots": slots, "pie": pie, "lookouts": lookouts, "corners": corners, "room": rect,
		"capacity": SHORT_ROOM_CAPACITY if minf(rect.size.x, rect.size.y) < short_room else MAX_SLOTS,
		"kind": "wall", "files": { 1: slots[1].map(func(p): return { "point": p, "row": 1 }), -1: slots[-1].map(func(p): return { "point": p, "row": 1 }) },
		"row1": { 1: MAX_SLOTS, -1: MAX_SLOTS }, "spacing": stack_spacing }
	if NavBuilder.ready(map) and space != null:
		_lay_slots(g, opening, map, space)
	return g


# --- Where a stack stands (E20 to E22) -----------------------------------------------------------

## Lay out where a stack going in by `g` (built for `opening`) stands, the one rule every stack reads (`stack_slots`, `side_for`,
## `stack_point`): E20, every slot in the room (or the outdoor area) on the stack side of the doorway's wall, on the navmesh, reached
## from the stack side without going through the doorway, out of every other doorway's view and funnel; E21, a side's file runs along the
## wall to the room's corner, the other side next, then a second file a step out; E22, a slot on solid furniture is skipped (the navmesh is
## carved round the piece). Sets `kind` and its layout on `g`:
## - `wall` (a spot against the wall beside the door out of every other doorway's view, `_has_wall_spot`): `files` { 1: [..], -1: [..] },
##   each side's file nearest the door first (`{ point, row }`, row 1 against the wall, then row 2 a step out): the most bodies the wall
##   band beside the door holds (`_pack`), `row1` how many of each are against the wall;
## - `views` (every spot against the wall beside the door is in another doorway's view): `views_lays`, the stack of each size on each
##   first side, taken from the points of the wall band seen from the fewest other doorways (`_views_lays`);
## - `open_floor` (no spot beside the door at all) and `dead_end` (the same, from a room whose only doorway this is): no wall slots.
## `wall_n` is how many slots the wall (or the fewest-seen spots) holds; the members past them follow `seq` (`_overflow`). `from` is the key
## of the room the stack stands in ("" outside the house), `from_room` its rect (zero outside).
func _lay_slots(g: Dictionary, opening: Dictionary, map: RID, space) -> void:
	var from := ""
	for k in opening.get("rooms", []):
		if str(k) != str(g["into"]):
			from = str(k)
	var c := { "id": g["id"], "pos": g["pos"], "out": g["out"], "along": g["along"], "half": float(g["width"]) * 0.5, "from": from,
		"from_rect": _room_rect(from), "map": map, "space": space,
		"start": NavBuilder.snap(map, (g["pos"] as Vector2) + (g["out"] as Vector2) * SLOT_REACH_OUT), "reach": {} }
	var dead_end := from != "" and room_doorways(from).size() <= 1
	var bands := { 1: _band(c, 1, WALL_GRID), -1: _band(c, -1, WALL_GRID) }
	g["wall_n"] = 0
	g["from"] = from
	g["from_room"] = c["from_rect"]  # The room the stack stands in (a zero rect: the open, outside the house).
	if _has_wall_spot(c, false):
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
		g["slots"] = { 1: files[1].map(func(f): return f["point"]), -1: files[-1].map(func(f): return f["point"]) }
		g["wall_n"] = mini(MAX_SLOTS, laid.size())
		if row1[1] != row1[-1]:
			g["side"] = 1 if row1[1] > row1[-1] else -1
		# A short wall's overflow: the same room's open floor, then the tail; none outdoors or from a room with no other doorway.
		_overflow(g, c, laid, from == "" or dead_end, true)
		return
	if _has_wall_spot(c, true):
		var lays := _views_lays(bands)
		if (lays[1][MAX_SLOTS - 1] as Array).size() < MAX_SLOTS:  # Short of a full stack: the whole wall, on the finer grid.
			lays = _views_lays({ 1: _band(c, 1, SLOT_STEP), -1: _band(c, -1, SLOT_STEP) })
		g["kind"] = "views"
		g["views_lays"] = lays
		var lay := _views_layout(g, MAX_SLOTS, int(g["side"]) if int(g["side"]) != 0 else 1)
		g["slots"] = { 1: lay.filter(func(x): return x["side"] == 1).map(func(x): return x["point"]),
			-1: lay.filter(func(x): return x["side"] == -1).map(func(x): return x["point"]) }
		g["wall_n"] = lay.size()
		# Past what the fewest-seen spots hold, the same chain as a short wall's (rule 6).
		_overflow(g, c, (lays[1][MAX_SLOTS - 1] as Array).map(func(x): return x["point"]), from == "" or dead_end, true)
		return
	g["kind"] = "dead_end" if dead_end else "open_floor"
	_overflow(g, c, [], dead_end, false)
	var seq: Array = g["seq"]
	g["slots"] = { 1: seq.filter(func(x): return side_of(g, x["point"]) == 1).map(func(x): return x["point"]),
		-1: seq.filter(func(x): return side_of(g, x["point"]) == -1).map(func(x): return x["point"]) }


## Where the members of a stack going in by `g` stand past the `wall_n` the wall holds (`laid`, their points; rule 6, E20's fallback):
## `seq`, slots on the stack side's open floor (off the door's axis and out of its funnel, `stack_spacing` from the wall's slots), then the
## tail's (`tail_from` on: the members the room cannot hold, holding in the room they came by at its doorway into the small room, never
## crossing). `capped` (nowhere for a tail: a dead end, whose room has no other doorway, or outdoors past a short wall) takes as many as its
## open floor holds (the most, `_most_spaced`) and no more: the members past that get no slot. A short wall's overflow, and that of a `views`
## way in past the spots it holds (`strict`), keeps off its wall band and out of every other doorway's view too, and takes the most its
## open floor holds before the tail.
func _overflow(g: Dictionary, c: Dictionary, laid: Array, capped: bool, strict: bool) -> void:
	var wanted := MAX_SLOTS - int(g["wall_n"])
	var open_slots: Array = _open_floor(c, capped or strict, laid, wanted, strict) if wanted > 0 else []
	var seq: Array = open_slots.map(func(p): return { "point": p, "row": 1 })
	g["tail_from"] = int(g["wall_n"]) + seq.size() + 1
	if not capped and wanted > open_slots.size():
		seq.append_array(_tail_spots(c, laid + open_slots).map(func(p): return { "point": p, "row": 1 }))
	g["seq"] = seq
	g["capped"] = capped


## Whether the wall beside the door of `c` has a spot against it (a body's standoff from it, give or take a few px) where a body may stand
## (`_slot_ok`), out of every other doorway's view unless `with_views`, on either side from `SLOT_JAMB` past the jamb to the wall's end:
## the stack side room's corner (outdoors `OUTDOOR_REACH`) or another doorway's funnel (E21). With one only in some doorway's view the
## stack takes the spots seen from the fewest other doorways; with none at all it stands on the open floor (rule 6).
func _has_wall_spot(c: Dictionary, with_views: bool) -> bool:
	var pos: Vector2 = c["pos"]
	var out: Vector2 = c["out"]
	for s in [1, -1]:
		var along: Vector2 = (c["along"] as Vector2) * s
		var reach := OUTDOOR_REACH
		if c["from"] != "":
			reach = _edge_along(c["from_rect"], pos + out * wall_standoff, along) - SLOT_ROOM_INSET
		var lateral: float = c["half"] + SLOT_JAMB
		while lateral <= reach:
			if _in_other_funnel(c, pos + out * wall_standoff + along * lateral):
				break  # The wall's end: another doorway's funnel.
			var o := WALL_SPOT_MIN
			while o <= WALL_SPOT_MAX:
				var p := pos + out * o + along * lateral
				if NavBuilder.snap(c["map"], p).distance_to(p) <= SLOT_SNAP and _slot_ok(c, p, with_views, false):
					return true
				o += 2.0
			lateral += SLOT_STEP
	return false


## One side's wall band (`s`, 1 / -1 along the wall) of the stack of `c` (`_lay_slots`): the points of a `step` px grid beside the door, from
## a body past the jamb along the wall to the stack side room's corner (outdoors `OUTDOOR_REACH`),
## and `SLOT_OUT_MIN` to `SLOT_OUT_MAX` px out from the wall plane, within `SLOT_SNAP` of the navmesh, where a body may stand bar the other
## doorways' views (`_slot_ok`): each `{ point, row, lat, off, views }` (row 1 within `ROW1_DEPTH` of the wall plane; `off`
## how far from the wall standoff; `views` how many other doorways see it, `_views_on`).
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
			if NavBuilder.snap(c["map"], p).distance_to(p) <= SLOT_SNAP and _slot_ok(c, p, true, false):
				band.append({ "point": p, "row": 1 if o <= ROW1_DEPTH else 2, "lat": lateral, "off": absf(o - wall_standoff),
					"views": _views_on(c, p) })
			o += step
		lateral += step
	return band


## The file of one side of the stack of `c` from its wall band's points `band` (`_band`): the most bodies (at most `MAX_SLOTS`) they hold
## `stack_spacing` apart, found by a full search (`_most_spaced`) over them taken in order of preference (against the wall first, nearest
## the door, nearest the wall standoff), so among the layouts holding the most, the one nearest the door against the wall. Each
## `{ point, row }`, row 1 nearest the door first, then row 2.
func _pack(band: Array) -> Array:
	var cands := band.duplicate()
	cands.sort_custom(func(a, b):
		if a["row"] != b["row"]:
			return a["row"] < b["row"]
		if a["lat"] != b["lat"]:
			return a["lat"] < b["lat"]
		return a["off"] < b["off"])
	var picks: Array = _most_spaced(cands.map(func(x): return x["point"]), MAX_SLOTS).map(func(i): return cands[i])
	picks.sort_custom(func(a, b): return a["row"] < b["row"] if a["row"] != b["row"] else a["lat"] < b["lat"])
	return picks.map(func(x): return { "point": x["point"], "row": x["row"] })


## The layouts of a `views` way in (`_lay_slots`) from its wall band's points `bands` (`_band`, per side): for each first side (1 /
## -1), the slots of a stack of 1 to `MAX_SLOTS` (`[count - 1] -> [{ point, row, side, lat }]`). Of the spots beside the door, those seen from
## the fewest other doorways that hold the stack: the least number of doorways for which the spots seen from no more than that hold it
## (`_most_spaced` over them taken against the wall first, then a step out, the first side's file before the other's, each nearest the
## door first), the first `count` of them in that order; the most there are when even every spot does not hold it.
func _views_lays(bands: Dictionary) -> Dictionary:
	var spots: Array = []
	var levels: Array = []
	for s in [1, -1]:
		for x: Dictionary in bands[s]:
			spots.append({ "point": x["point"], "side": s, "row": x["row"], "views": x["views"], "lat": x["lat"], "off": x["off"] })
			if not levels.has(int(x["views"])):
				levels.append(int(x["views"]))
	levels.sort()
	var lays := {}
	for first in [1, -1]:
		var order := spots.duplicate()
		order.sort_custom(func(a, b):
			if a["row"] != b["row"]:
				return a["row"] < b["row"]
			if a["side"] != b["side"]:
				return a["side"] == first
			if a["lat"] != b["lat"]:
				return a["lat"] < b["lat"]
			return a["off"] < b["off"])
		var held: Array = []   # Per level, the most its spots hold.
		for v: int in levels:
			var level: Array = order.filter(func(x): return int(x["views"]) <= v)
			held.append(_most_spaced(level.map(func(x): return x["point"]), MAX_SLOTS).map(func(i): return level[i]))
			if (held[-1] as Array).size() >= MAX_SLOTS:
				break
		var per: Array = []
		for count in range(1, MAX_SLOTS + 1):
			var lay: Array = held[-1] if not held.is_empty() else []
			for picks: Array in held:
				if picks.size() >= count:
					lay = picks
					break
			per.append(lay.slice(0, count).map(func(x): return { "point": x["point"], "row": x["row"], "side": x["side"], "lat": x["lat"] }))
		lays[first] = per
	# Spots too few for a full stack: every stack that takes them all takes the same ones whichever side it starts on (the overflow stands
	# clear of them), that side's file first.
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
	return lays


## The outs (px from the wall plane) a tail member is sought at against its doorway's wall, the wall standoff first.
func _row1_outs() -> Array:
	return [wall_standoff, wall_standoff - 4.0, wall_standoff + 4.0, wall_standoff - 8.0, wall_standoff + 8.0, wall_standoff + 12.0,
		wall_standoff + 16.0].filter(func(o): return o >= ROW1_MIN and o <= ROW1_MAX)


## Whether a body of the stack of `c` may stand at navmesh point `p`: in the stack side's room (or outdoors, outside every room and out
## from the wall), out of every other doorway's funnel and (unless `with_views`) view, and reached from the stack side by a route that does
## not go through the doorway (`routed`: false leaves the route to the caller). `open` (the open-floor fallback): off the door's axis by a
## body and out of its funnel; else beside the door, clear of its opening.
func _slot_ok(c: Dictionary, p: Vector2, with_views: bool, open: bool, routed := true) -> bool:
	var rel: Vector2 = p - (c["pos"] as Vector2)
	var lateral := absf(rel.dot(c["along"]))
	var outward := rel.dot(c["out"])
	if open:
		if lateral < SLOT_BODY or (lateral < c["half"] and absf(outward) < FUNNEL_DEPTH):
			return false
	elif lateral < c["half"] + SLOT_BODY:
		return false
	if not _in_stack_side(c, p) or _in_other_funnel(c, p) or (not with_views and _views_on(c, p) > 0):
		return false
	return not routed or _reached(c, p)


## Whether point `p` is ground a stack going in by `g` may walk on its way to a slot (E20): on the stack side of the doorway's wall, in the
## room the stack stands in (or out in the open), and with a body there clear of every other doorway's funnel (by `SLOT_BODY` past its jambs).
func on_stack_side(g: Dictionary, p: Vector2) -> bool:
	var c := { "id": g["id"], "pos": g["pos"], "out": g["out"], "along": g["along"], "half": float(g["width"]) * 0.5,
		"from": str(g.get("from", "")), "from_rect": g.get("from_room", Rect2()) }
	if not _in_stack_side(c, p):
		return false
	for f: Dictionary in _door_frames():
		var rel: Vector2 = p - (f["pos"] as Vector2)
		if f["id"] != c["id"] and absf(rel.dot(f["along"])) < float(f["half"]) + SLOT_BODY and absf(rel.dot(f["out"])) < FUNNEL_DEPTH:
			return false
	return true


## Whether `p` lies on the stack side of `c`: inside its room's walls (`SLOT_ROOM_INSET`), or for an exterior door outside every room of
## the house and out from the doorway's wall plane.
func _in_stack_side(c: Dictionary, p: Vector2) -> bool:
	if c["from"] != "":
		return (c["from_rect"] as Rect2).grow(-SLOT_ROOM_INSET).has_point(p)
	if (p - (c["pos"] as Vector2)).dot(c["out"]) < SLOT_ROOM_INSET:
		return false
	return not _rooms.any(func(r): return (r["rect"] as Rect2).grow(SLOT_ROOM_INSET).has_point(p))


## Whether a route from the stack side of `c` (`SLOT_REACH_OUT` out from the wall plane) ends at `p` without going through the doorway.
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
			if Geometry2D.segment_intersects_segment(pts[i - 1], pts[i], pos - half, pos + half) != null:
				ok = false
				break
	c["reach"][key] = ok
	return ok


## Whether `p` stands in the fatal funnel of a doorway other than `c`'s (within its width and `FUNNEL_DEPTH` of its wall plane).
func _in_other_funnel(c: Dictionary, p: Vector2) -> bool:
	for f: Dictionary in _door_frames():
		if f["id"] == c["id"]:
			continue
		var rel: Vector2 = p - (f["pos"] as Vector2)
		if absf(rel.dot(f["along"])) < f["half"] and absf(rel.dot(f["out"])) < FUNNEL_DEPTH:
			return true
	return false


## How many doorways other than `c`'s see a body at `p` from inside a room they lead into: `p` lies out from that doorway's wall, inside its
## view (from the room's far corners past the jambs, the views' `door_view_depth` long, by `VIEW_MARGIN`), with a line clear of walls to the doorway.
func _views_on(c: Dictionary, p: Vector2) -> int:
	var ids := {}
	for f: Dictionary in _door_frames():
		if f["id"] == c["id"] or ids.has(f["id"]):
			continue
		var pos: Vector2 = f["pos"]
		if (p - pos).dot(f["out"]) <= 0.0 or not Geometry2D.is_point_in_polygon(p, f["quad"]) or _edge_gap(f["quad"], p) < VIEW_MARGIN:
			continue
		var gap: Vector2 = (f["along"] as Vector2) * (float(f["half"]) - 4.0)
		for target: Vector2 in [pos, pos - gap, pos + gap]:
			if vision.wall_hit(c["space"], p, target).is_empty():
				ids[f["id"]] = true
				break
	return ids.size()


## Every way into a room through every doorway of the house, as a frame: `{ id, pos, half, out (away from the room), along, quad (the
## view out of it, unclipped) }`. Worked out once per house.
func _door_frames() -> Array:
	if not _frames.is_empty() or _openings.is_empty():
		return _frames
	for o in _openings:
		for k in o.get("rooms", []):
			var rect := _room_rect(str(k))
			if rect.size == Vector2.ZERO:
				continue
			var pos: Vector2 = o["pos"]
			var out := -normal_into(rect, pos)
			var along := out.orthogonal()
			var half := float(o.get("width", 80.0)) * 0.5
			var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
			corners.sort_custom(func(a, b): return (a - pos).dot(out) < (b - pos).dot(out))
			var jamb_a := pos - along * half
			var jamb_b := pos + along * half
			var for_a: Vector2 = corners[0] if (corners[0] - pos).dot(along) > (corners[1] - pos).dot(along) else corners[1]
			var for_b: Vector2 = corners[1] if for_a == corners[0] else corners[0]
			var quad := PackedVector2Array([jamb_a, jamb_a + (jamb_a - for_a).normalized() * views.door_view_depth,
				jamb_b + (jamb_b - for_b).normalized() * views.door_view_depth, jamb_b])
			_frames.append({ "id": opening_id(o), "pos": pos, "half": half, "out": out, "along": along, "quad": quad })
	return _frames


## The open floor of the stack side's room of `c` where a stack may stand past what the wall beside the door holds (`taken`, the wall's
## slots): points of a grid inside its walls (outdoors, a box out from the door `OUTDOOR_FLOOR` px along the wall either side and out
## from it), off the door's axis by a body, out of its funnel and every other doorway's (`_slot_ok`), `stack_spacing` from `taken` and each
## other, nearest the door's wall first and then farthest off its axis, reached from the stack side (`_reached`); at most `most`.
## `strict` (a short wall's overflow): off the wall band (`_in_band`) and out of every other doorway's view too. `exact` takes the most
## the floor holds (`_most_spaced`, on an `OPEN_GRID_FINE` grid when the coarse one holds fewer than `most`); otherwise the first that
## fit, in that order.
func _open_floor(c: Dictionary, exact: bool, taken: Array, most: int, strict := false) -> Array:
	var picks := _floor_picks(c, exact, OPEN_GRID, taken, most, strict)
	if exact and picks.size() < most:
		picks = _floor_picks(c, exact, OPEN_GRID_FINE, taken, most, strict)
	return picks


## `_open_floor` on a grid of `step` px.
func _floor_picks(c: Dictionary, exact: bool, step: float, taken: Array, most: int, strict: bool) -> Array:
	var pos: Vector2 = c["pos"]
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
	else:
		var lat := -OUTDOOR_FLOOR
		while lat <= OUTDOOR_FLOOR:
			var o := SLOT_ROOM_INSET
			while o <= OUTDOOR_FLOOR:
				grid.append(pos + (c["out"] as Vector2) * o + (c["along"] as Vector2) * lat)
				o += step
			lat += step
	var cands: Array = []
	for p: Vector2 in grid:
		if NavBuilder.snap(c["map"], p).distance_to(p) <= SLOT_SNAP and not (strict and _in_band(c, p)) \
				and taken.all(func(q): return (q as Vector2).distance_to(p) >= stack_spacing) and _slot_ok(c, p, not strict, true):
			cands.append(p)
	cands.sort_custom(func(a, b):
		var oa: float = (a - pos).dot(c["out"])
		var ob: float = (b - pos).dot(c["out"])
		if absf(oa - ob) > 0.5:
			return oa < ob
		return absf((a - pos).dot(c["along"])) > absf((b - pos).dot(c["along"])))
	if exact:
		return _most_spaced(cands, most).map(func(i): return cands[i])
	var picks: Array = []
	for p: Vector2 in cands:
		if picks.size() < most and picks.all(func(q): return (q as Vector2).distance_to(p) >= stack_spacing):
			picks.append(p)
	return picks


## Whether `p` lies in the wall band of `c` (`_band`): beside the door (a body past the jamb along the wall), `SLOT_OUT_MIN` to
## `SLOT_OUT_MAX` px out from the wall plane, on the stack side.
func _in_band(c: Dictionary, p: Vector2) -> bool:
	var rel: Vector2 = p - (c["pos"] as Vector2)
	var o := rel.dot(c["out"])
	return absf(rel.dot(c["along"])) >= float(c["half"]) + SLOT_BODY and o >= SLOT_OUT_MIN and o <= SLOT_OUT_MAX and _in_stack_side(c, p)


## The indices of the most of `points` (at most `most`) each at least `stack_spacing` from the others: of the sets that large, the first in
## their order. An exact search (a Russian-doll search): from the last point back, `best[k]` is the most the points from `k` on hold (at
## most `most`), each found by asking whether the points after `k` free of it hold `best[k + 1]` more (`_holds`), which the counts already
## known bound tightly; then the first set in order of that many (`_holds` again, keeping it). Within `PACK_BUDGET` steps.
func _most_spaced(points: Array, most: int) -> Array:
	var n := points.size()
	if n == 0 or most <= 0:
		return []
	var best := PackedInt32Array()
	best.resize(n + 1)
	best.fill(0)
	var budget := [PACK_BUDGET]
	for k in range(n - 1, -1, -1):
		best[k] = best[k + 1]
		if best[k + 1] < most and _holds(points, _free_after(points, k, range(k + 1, n)), best[k + 1], best, budget, []):
			best[k] = best[k + 1] + 1
	var chosen: Array = []
	_holds(points, range(n), best[0], best, budget, chosen)
	return chosen


## Whether the points `cands` (indices into `points`, ascending) hold `need` each `stack_spacing` apart, bounded by `best` (`_most_spaced`:
## the points from an index on hold no more than `best` of it); the set found is added to `chosen` (an empty array to ask only).
func _holds(points: Array, cands: Array, need: int, best: PackedInt32Array, budget: Array, chosen: Array) -> bool:
	if need <= 0:
		return true
	for i in cands.size():
		if cands.size() - i < need or best[cands[i]] < need:
			return false
		budget[0] -= 1
		if budget[0] <= 0:
			return false
		var size := chosen.size()
		chosen.append(cands[i])
		if _holds(points, _free_after(points, cands[i], cands.slice(i + 1)), need - 1, best, budget, chosen):
			return true
		chosen.resize(size)
	return false


## Of the indices `cands`, those whose points lie at least `stack_spacing` from point `k`.
func _free_after(points: Array, k: int, cands: Array) -> Array:
	var p: Vector2 = points[k]
	var sq := stack_spacing * stack_spacing
	return cands.filter(func(j): return p.distance_squared_to(points[j]) >= sq)


## Where the tail of the stack of `c` holds (E20's fallback, `open_floor`): in the room it came by (the stack side's room's other doorway
## nearest this one), against its wall beside that doorway, taking turns either side of it; once that wall is full, the nearest spots of
## that room to the doorway on a `OPEN_GRID` px grid. Within `TAIL_REACH` of it, off its axis by a body and out of its funnel, on the
## navmesh; never nearer `stack_spacing` to the `open_slots` or each other. At most `MAX_SLOTS`.
func _tail_spots(c: Dictionary, open_slots: Array) -> Array:
	var best := {}
	for f: Dictionary in _door_frames():
		if f["id"] == c["id"] or not (c["from_rect"] as Rect2).grow(1.0).has_point(f["pos"]):
			continue
		var into_from: bool = (c["from_rect"] as Rect2).has_point((f["pos"] as Vector2) - (f["out"] as Vector2) * 30.0)
		if not into_from:
			continue  # The frame going into the other room: the tail stands on the far side, framed going into the stack's room.
		if best.is_empty() or (f["pos"] as Vector2).distance_to(c["pos"]) < (best["pos"] as Vector2).distance_to(c["pos"]):
			best = f
	if best.is_empty():
		return []
	var pos: Vector2 = best["pos"]
	var beyond := ""
	for k in _opening(best["id"]).get("rooms", []):
		if str(k) != c["from"]:
			beyond = str(k)
	var tc := { "id": best["id"], "pos": pos, "out": best["out"], "along": best["along"], "half": best["half"], "from": beyond,
		"from_rect": _room_rect(beyond), "map": c["map"], "space": c["space"], "reach": {} }
	var out: Array = []
	for k in MAX_SLOTS:
		var s := 1 if k % 2 == 0 else -1
		var lateral := float(best["half"]) + SLOT_JAMB + stack_spacing * floorf(k / 2.0)
		for o: float in _row1_outs():
			var raw: Vector2 = pos + (best["out"] as Vector2) * o + (best["along"] as Vector2) * s * lateral
			var p := NavBuilder.snap(c["map"], raw)
			if p.distance_to(raw) > SLOT_SNAP or p.distance_to(pos) > TAIL_REACH or not _in_stack_side(tc, p):
				continue
			if (open_slots + out).any(func(q): return (q as Vector2).distance_to(p) < stack_spacing):
				continue
			out.append(p)
			break
	if out.size() < MAX_SLOTS:
		var grid: Array = []
		var lat := -TAIL_REACH
		while lat <= TAIL_REACH:
			var o := SLOT_ROOM_INSET
			while o <= TAIL_REACH:
				var p: Vector2 = pos + (best["out"] as Vector2) * o + (best["along"] as Vector2) * lat
				if p.distance_to(pos) <= TAIL_REACH and absf(lat) >= SLOT_BODY and (absf(lat) >= float(best["half"]) or o >= FUNNEL_DEPTH) \
						and NavBuilder.snap(c["map"], p).distance_to(p) <= SLOT_SNAP and _in_stack_side(tc, p) and not _in_other_funnel(tc, p):
					grid.append(p)
				o += OPEN_GRID
			lat += OPEN_GRID
		grid.sort_custom(func(a, b): return a.distance_squared_to(pos) < b.distance_squared_to(pos))
		for p: Vector2 in grid:
			if out.size() >= MAX_SLOTS:
				break
			if not (open_slots + out).any(func(q): return (q as Vector2).distance_to(p) < stack_spacing):
				out.append(p)
	return out


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
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return best


## Where a stack of `count` going in by geometry `g` stands, its point on side `side` (1 / -1 along the wall) where that side has room:
## `[{ n, point, side, row }]`, slot 1 (the point) first. The one rule every stack is laid out by (E20 to E22, `_lay_slots`): one slot
## per member, but on a dead end only as many as its room holds.
static func stack_slots(g: Dictionary, count: int, side: int) -> Array:
	var members: Array = []
	var out: Array = []
	for n in range(1, count + 1):
		if not holds_slot(g, n):
			break
		var on := side_for(g, members, n, side)
		members.append({ "id": n, "slot": n, "side": on })
	for m: Dictionary in members:
		var at := _laid(g, members, int(m["slot"]), int(m["side"]))
		var on_wall: bool = g.get("kind", "wall") == "wall" and int(m["slot"]) <= int(g.get("wall_n", MAX_SLOTS))
		out.append({ "n": m["slot"], "point": at["point"], "side": m["side"] if on_wall else side_of(g, at["point"]), "row": at["row"] })
	return out


## The side of the door the member holding slot `slot` stacks on, wanting side `preferred` (the team's, its own on a split stack, the
## order's), among the claims `team` (E21): its side while that side's wall has room for it, else the other side's while it has, else a
## second file on its side, then on the other. Past what the wall holds (`seq`), and on a layout with no files (`views`, `open_floor`,
## `dead_end`), the side its slot lies on.
static func side_for(g: Dictionary, team: Array, slot: int, preferred: int) -> int:
	var pref := preferred if preferred != 0 else 1
	if g.get("kind", "wall") != "wall" or slot > int(g.get("wall_n", MAX_SLOTS)):
		var at := _laid(g, team, slot, pref)
		return side_of(g, at["point"]) if at["point"] != Vector2.INF else pref
	var files: Dictionary = g["files"]
	var row1: Dictionary = g["row1"]
	var here := place(team, pref, slot)
	var there := place(team, -pref, slot)
	if here <= int(row1[pref]):
		return pref
	if there <= int(row1[-pref]):
		return -pref
	if here <= (files[pref] as Array).size():
		return pref
	if there <= (files[-pref] as Array).size():
		return -pref
	return pref


## Where the member holding slot `slot` on side `side` stands, among the stack's `members` (the claims, its own among them or not); INF for
## a slot a dead end does not hold.
static func stack_point(g: Dictionary, members: Array, slot: int, side: int) -> Vector2:
	return _laid(g, members, slot, side)["point"]


## Whether a stack going in by `g` has a slot `slot` at all: a dead end holds only as many as its wall and open floor do (E20); any slot
## elsewhere.
static func holds_slot(g: Dictionary, slot: int) -> bool:
	return not g.get("capped", false) or slot <= int(g.get("wall_n", 0)) + (g.get("seq", []) as Array).size()


## Whether slot `slot` of a stack going in by `g` is one of its tail (E20's fallback: the members a small room cannot hold, who hold in the
## room they came by as rear security and never cross).
static func is_tail(g: Dictionary, slot: int) -> bool:
	return not g.get("capped", false) and g.has("seq") and slot >= int(g.get("tail_from", 999))


## `{ point, row }` of slot `slot` on side `side` among `members` (see `stack_point`).
static func _laid(g: Dictionary, members: Array, slot: int, side: int) -> Dictionary:
	var wall_n := int(g.get("wall_n", MAX_SLOTS))
	if slot > wall_n and g.has("seq"):
		var seq: Array = g["seq"]
		var i := slot - wall_n - 1
		if seq.is_empty() or (g.get("capped", false) and i >= seq.size()):
			return { "point": Vector2.INF, "row": 1 }
		return seq[mini(i, seq.size() - 1)]
	if g.get("kind", "wall") == "views":
		var count := mini(maxi(members.filter(func(m): return int(m["slot"]) != slot and int(m["slot"]) <= wall_n).size() + 1, slot), wall_n)
		var lead := side
		for m in members:
			if int(m["slot"]) == 1 and int(m["side"]) != 0:
				lead = int(m["side"])
		var lay := _views_layout(g, count, lead if lead != 0 else 1)
		if lay.is_empty():
			return { "point": g["pos"] + (g["out"] as Vector2) * 28.0, "row": 1 }
		return lay[clampi(slot - 1, 0, lay.size() - 1)]
	var file: Array = g["files"][side if side != 0 else 1]
	if file.is_empty():
		file = g["files"][-side if side != 0 else -1]
	if file.is_empty():
		return { "point": g["pos"] + (g["out"] as Vector2) * 28.0, "row": 1 }
	return file[clampi(place(members, side, slot) - 1, 0, file.size() - 1)]


## The `count` slots of a `views` layout (`_lay_slots`, `_views_lays`), its first side `side`: of the spots beside the door, those seen
## from the fewest other doorways that hold `count` at `stack_spacing`, side `side`'s file nearest the door first, then the other's, then
## the second files. Each `{ point, row, side }`.
static func _views_layout(g: Dictionary, count: int, side: int) -> Array:
	var per: Array = (g.get("views_lays", {}) as Dictionary).get(side if side != 0 else 1, [])
	return per[clampi(count, 1, per.size()) - 1] if not per.is_empty() else []


## The unit normal pointing into `rect` from the edge door `pos` lies on (the nearest edge; `AgentDoorViews.normal_into`). Also read by the
## squad (`ai/team/squad.gd`), which tells which side of a doorway's wall a leader clicked.
static func normal_into(rect: Rect2, pos: Vector2) -> Vector2:
	return AgentDoorViews.normal_into(rect, pos)


## How much of the room's wall runs from door `pos` toward `dir` (to the room's corner on that side).
func _wall_length(rect: Rect2, pos: Vector2, dir: Vector2) -> float:
	if absf(dir.x) > 0.5:
		return (rect.end.x - pos.x) if dir.x > 0.0 else (pos.x - rect.position.x)
	return (rect.end.y - pos.y) if dir.y > 0.0 else (pos.y - rect.position.y)


## Whether the line `from` → `to` is clear for sight (over low cover; walls and tall furniture block it).
func _sees(space, from: Vector2, to: Vector2) -> bool:
	return space == null or vision.can_see(from, to - from, to, space, [])


# --- The team, off the radio -------------------------------------------------------------------

## The allies' live claims on opening `id`, from the callouts heard (latest per speaker, see the perception's
## `_callouts()`): `{ id (speaker instance id), name, slot, side, step, covering, pos, age }`, lowest slot first
## (`covering` = the doorway a member holding the cleared room watches, with step `cover`; `bang` = it goes in with a stun thrown first, true
## for a member that says nothing of it, such as the human; `stuns` / `frags` = how many stun / frag grenades it carries; `order_id` = the
## order it stacks under, "" for none, with the order's `order_bang` (a grenade first), `order_mode` (`quiet` / `stun` / `frag`, LD14;
## `quiet` for a claim under no order), `order_hold` (the order holds for the leader's go, LD13) and `order_go` (that go has
## come), and its side `order_side`, 1 / -1 along the wall or 0 for a split stack: `docs/leadership.md` LD9). A member who aborted or is
## done with the doorway, or whose latest call is about something else, holds no claim.
static func claims(id: String, callouts: Array) -> Array:
	var out: Array = []
	for c in callouts:
		if str(c.get("opening", "")) != id:
			continue
		var step := str(c.get("entry_step", ""))
		if step == "" or step == "abort" or step == "done":
			continue
		out.append({ "id": c["id"], "name": c.get("name", ""), "slot": int(c.get("slot", 0)), "side": int(c.get("side", 0)),
			"step": step, "covering": str(c.get("covering", "")), "pos": c.get("position", Vector2.ZERO), "age": c.get("age", 0.0),
			"bang": bool(c.get("bang", true)), "bang_off": bool(c.get("bang_off", false)), "stuns": int(c.get("stuns", 0)),
			"frags": int(c.get("frags", 0)), "order_id": str(c.get("order_id", "")), "order_bang": bool(c.get("order_bang", false)),
			"order_mode": str(c.get("order_mode", "quiet")), "order_hold": bool(c.get("order_hold", false)),
			"order_go": bool(c.get("order_go", false)), "order_side": int(c.get("order_side", 0)), "leader": bool(c.get("leader", false)),
			"claim_frame": int(c.get("claim_frame", -1)), "claim_pos": c.get("claim_pos", c.get("position", Vector2.ZERO)),
			"move_up": int(c.get("move_up", 0)), "pie": bool(c.get("pie", false)), "human": bool(c.get("human", false)) })
	out.sort_custom(func(a, b): return a["slot"] < b["slot"] if a["slot"] != b["slot"] else a["id"] < b["id"])
	return out


## The lowest stack slot (1 = the point) not claimed by an ally in `team` (see `claims`), for the NPC with instance id `self_id` that holds
## `current` (0: it is claiming now). Claims made on the same physics frame settle by distance (E2), so their walks do not
## cross: with `mine` (`{ frame, pos, g, side }`: the frame this NPC claims or claimed on, where it stood then, the doorway's geometry and,
## for `current`, its side), a slot claimed on that same frame by an ally farther from the slot's point than this NPC is taken from it,
## and of two such claims on one slot the nearer keeps it (each reads the other's `claim_frame` and `claim_pos` off the radio, so both
## settle the same way; a slot given up for another keeps the claim's frame and spot, so the settling goes on down the stack).
## Otherwise, or at an even distance, the lower instance id keeps a slot two claim. A claim that moved up into a slot (E2: its `move_up`, the slot
## it came from, which `mine` carries for this NPC's own) holds it against one that did not, and the NPC that held it takes the freed one.
static func free_slot(team: Array, self_id: int, current := 0, mine := {}) -> int:
	var taken := {}
	for m in team:
		taken[m["slot"]] = taken.get(m["slot"], []) + [m]
	if current > 0 and (not taken.has(current) \
			or taken[current].all(func(other): return _wins(team, current, int(mine.get("side", 0)), other, self_id, mine))):
		return current
	for other in taken.get(current, []):
		var freed := int(other.get("move_up", 0))
		if freed > 0 and not taken.has(freed) and int(mine.get("move_up", 0)) == 0:
			return freed  # An ally moved up into this slot (E2): this NPC takes the one it freed.
	var slot := 1
	while taken.has(slot):
		if taken[slot].all(func(other): return int(other["claim_frame"]) == int(mine.get("frame", -2)) \
				and _wins(team, slot, int(other["side"]), other, self_id, mine)):
			return slot  # Claimed on the frame this NPC claimed on, by someone farther from it: this NPC takes it, and the other gives it up.
		slot += 1
	return slot


## Whether this NPC (`self_id`, `mine`: see `free_slot`) holds slot `slot` on side `side` against ally `other`'s claim on it: the one that moved
## up into it, of a move-up and a claim that is not one (E2); else by distance to the slot's point (laid among the claims but these two) when
## both claimed it on the same frame on the same side, else (and at an even distance) by instance id.
static func _wins(team: Array, slot: int, side: int, other: Dictionary, self_id: int, mine: Dictionary) -> bool:
	if (int(other.get("move_up", 0)) > 0) != (int(mine.get("move_up", 0)) > 0):
		return int(mine.get("move_up", 0)) > 0  # A move-up (E2) holds the slot it stepped into against the claim it moved up past.
	if not mine.is_empty() and int(other["claim_frame"]) >= 0 and int(other["claim_frame"]) == int(mine["frame"]) \
			and (side == 0 or side == int(other["side"])):
		var rest: Array = team.filter(func(m): return m["id"] != other["id"])
		var at := stack_point(mine["g"], rest, slot, int(other["side"]))
		if at != Vector2.INF:
			var own: float = (mine["pos"] as Vector2).distance_to(at)
			var theirs: float = (other["claim_pos"] as Vector2).distance_to(at)
			if absf(own - theirs) > 0.5:
				return own < theirs
	return self_id < int(other["id"])


## The side of the door (1 / -1 along its wall, see `geometry`) the team stacks on: the side the point (the slot 1 claim
## in `team`) stacks on; with no point yet, the side with more wall to stack against; when both have the same, the side
## `self_pos` is on. Every member works it out the same way, so the stack forms on one side unless a member cannot get
## there (`stack_side_from`, E19).
static func stack_side(g: Dictionary, team: Array, self_pos: Vector2) -> int:
	for m in team:
		if m["slot"] == 1 and m["side"] != 0:
			return m["side"]
	if int(g["side"]) != 0:
		return int(g["side"])
	return side_of(g, self_pos)


## The side of the door (1 / -1 along its wall) point `p` is on.
static func side_of(g: Dictionary, p: Vector2) -> int:
	return 1 if (p - (g["pos"] as Vector2)).dot(g["along"]) >= 0.0 else -1


## The side a member standing at `from` stacks on (E19): the team's side (`stack_side`), unless its way there crosses the
## doorway's view (`cuts_view`): then its own side, and the stack is split across the door.
func stack_side_from(g: Dictionary, team: Array, from: Vector2, map: RID, space) -> int:
	var team_side := stack_side(g, team, from)
	var own := side_of(g, from)
	var first := stack_point(g, [], 1, side_for(g, [], 1, team_side))
	if own == team_side or first == Vector2.INF or not cuts_view(g, from, first, map, space):
		return team_side
	return own


## Whether the walk from `from` to `to` crosses the view of doorway `g` (E19): it starts outside the view (`views.door_view`) and its
## plain route crosses the door's axis inside it, in front of the door. A walk that starts in the view, or goes round it, does not.
func cuts_view(g: Dictionary, from: Vector2, to: Vector2, map: RID, space) -> bool:
	var view: PackedVector2Array = views.door_view(g["id"], g["into"], map, space)
	if view.is_empty() or Geometry2D.is_point_in_polygon(from, view):
		return false
	var pos: Vector2 = g["pos"]
	var out: Vector2 = g["out"]
	var axis := PackedVector2Array([pos + out * AgentDoorViews.VIEW_APEX_OUT, pos + out * views.door_view_depth])
	var route: Array = [from] + Array(NavBuilder.route(map, from, to))
	for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(axis, view):
		for i in range(1, route.size()):
			for j in range(1, piece.size()):
				if Geometry2D.segment_intersects_segment(route[i - 1], route[i], piece[j - 1], piece[j]) != null:
					return true
	return false


## The members of a stack (`members`: claims with `id`, `slot` and `side`, this member's own among them) in the order they
## cross (E6, E19): by slot on a one-sided stack; on a split one the point (the lowest slot), then the front man of the other
## side, then the sides take turns, each side's file in slot order (one that runs out leaves the rest to the other).
static func crossing_order(members: Array) -> Array:
	var sorted := members.duplicate()
	sorted.sort_custom(func(a, b): return a["slot"] < b["slot"] if a["slot"] != b["slot"] else a["id"] < b["id"])
	if sorted.is_empty():
		return sorted
	var lead_side := int(sorted[0]["side"])
	var lead: Array = sorted.filter(func(m): return int(m["side"]) == lead_side or int(m["side"]) == 0)
	var other: Array = sorted.filter(func(m): return int(m["side"]) != lead_side and int(m["side"]) != 0)
	if other.is_empty():
		return sorted
	var out: Array = []
	for i in maxi(lead.size(), other.size()):
		if i < lead.size():
			out.append(lead[i])
		if i < other.size():
			out.append(other[i])
	return out


## The place (1 = nearest the door) in its side's file of the member holding stack slot `slot` on side `side`: the slots are
## numbered across both sides in the order they were claimed, so a split stack (E19) leaves out the claims on the other side
## ahead of it (`team`, the claims, this member's own left out or not). On a one-sided stack the place is the slot.
static func place(team: Array, side: int, slot: int) -> int:
	var across := 0
	for m in team:
		if int(m["side"]) != side and int(m["side"]) != 0 and int(m["slot"]) < slot:
			across += 1
	return maxi(slot - across, 1)

