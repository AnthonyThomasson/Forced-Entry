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
## the one rule for where a stack of N stands, `stack_slots(g, count, side)` ->
## `[{ n, point, side, row }]`.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")
const ENTRY_SCRIPT := "res://scenes/ai/perception/agent_entry.gd"
## The doorway's stack, whose `stack_slots` lays a stack out.
const DOOR_STACK_SCRIPT := "res://scenes/ai/perception/stack/door_stack.gd"
## Body radius (px) of a character.
const BODY := 14.0
## A slot inside its room keeps at least this far (px) from the room rect's edges (the walls'
## centrelines): half a wall plus most of a body, so a body standing there is inside the room's
## walls.
const ROOM_INSET := 16.0
## A slot on the navmesh is within this many px of where `NavBuilder.snap` puts it.
const SNAP_SLACK := 3.0
## A route that reaches a slot ends within this many px of it.
const REACH_SLACK := 6.0
## How far (px) out from the stack side's wall plane a route to a slot starts (snapped onto the
## navmesh): "from the stack side".
const START_OUT := 60.0
## A body on a slot keeps at least this far (px) from every carved furniture footprint (E22).
const FURNITURE_CLEAR := 10.0
## `entry_stack_spacing` (44 px) less a few px for snapping: no two slots of a stack are closer than
## this (E2, E22).
const MIN_SPACING := 38.0
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
## `entry_stack_spacing`: how far apart (px) the fewest-views fallback's own picks of spots stand.
const STACK_SPACING := 44.0
## How far (px) from the doorway into the small room a tail member may hold (rule 6's tail: at that
## doorway, in the room it came by).
const TAIL_REACH := 140.0
## The step (px) of the grid of the test's own points a dead-end small room's capacity is counted on
## (rule 6's dead end).
const CAPACITY_GRID := 4.0


# --- The AI's entry geometry, through its published seam ------------------------------------------


## A new entry geometry over the house's `openings` and `rooms` (null when the script is missing).
static func entry_geometry(openings: Array, rooms: Array) -> RefCounted:
	if not ResourceLoader.exists(ENTRY_SCRIPT):
		return null
	var e: RefCounted = (load(ENTRY_SCRIPT) as GDScript).new()
	e.set_house(openings, rooms)
	return e


## The id the AI gives opening `o` (`AgentEntry.opening_id`).
static func opening_id(o: Dictionary) -> String:
	return String((load(ENTRY_SCRIPT) as GDScript).opening_id(o))


## Where a stack of `count` going in by geometry `g` stands, its point on side `side` (1 / -1 along
## the wall), read through the published rule `DoorStack.stack_slots(g, count, side)`:
## `{ slots: [{ n, point, side, row }] }`.
static func layout(g: Dictionary, count: int, side: int) -> Dictionary:
	var raw = (load(DOOR_STACK_SCRIPT) as GDScript).call("stack_slots", g, count, side)
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
static func normal_into(rect: Rect2, pos: Vector2) -> Vector2:
	var edges := [
		[absf(pos.x - rect.position.x), Vector2.RIGHT],
		[absf(pos.x - rect.end.x), Vector2.LEFT],
		[absf(pos.y - rect.position.y), Vector2.DOWN],
		[absf(pos.y - rect.end.y), Vector2.UP],
	]
	edges.sort_custom(func(a, b): return a[0] < b[0])
	return edges[0][1]


## The room `{ key, type, rect }` of `rooms` with key `key`, or {}.
static func room(rooms: Array, key: String) -> Dictionary:
	for r in rooms:
		if String(r["key"]) == key:
			return r
	return {}


## The frame of going through opening `o` into room `into` (an `entry_probe` doorway frame plus the
## stack side): `{ id, pos, width, out (unit normal away from `into`), along (out.orthogonal(), the
## axis the side 1 / -1 is read on), room (into's rect), room_key, from (the stack side's room key,
## "" outdoors), from_rect }`.
static func frame(o: Dictionary, into: String, rooms: Array) -> Dictionary:
	var into_rect: Rect2 = room(rooms, into).get("rect", Rect2())
	var pos: Vector2 = o["pos"]
	var out := -normal_into(into_rect, pos)
	var from := ""
	for k in o.get("rooms", []):
		if String(k) != into:
			from = String(k)
	return {
		"id": opening_id(o), "pos": pos, "width": float(o.get("width", 80.0)), "out": out,
		"along": out.orthogonal(), "room": into_rect, "room_key": into, "from": from,
		"from_rect": room(rooms, from).get("rect", Rect2()),
	}


## The frame of every opening other than frame `f`'s that joins `f`'s stack-side room to another
## room (or to outside), framed going into the stack-side room: the doorways a tail may hold at
## (rule 6), in the room it came by.
static func ways_into_stack_room(w: Dictionary, f: Dictionary) -> Array:
	var out: Array = []
	if String(f["from"]) == "":
		return out
	for o in w["openings"]:
		if opening_id(o) != f["id"] and (o.get("rooms", []) as Array).has(f["from"]):
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


# --- The rules for one point ----------------------------------------------------------------------


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


## Whether `p` lies in the stack side of frame `f`: inside the stack side's room (by `ROOM_INSET`),
## or, for an exterior door, outside every room of the house and on the outer side of the doorway's
## wall plane. "" when it does, else why not.
static func in_stack_room(w: Dictionary, f: Dictionary, p: Vector2) -> String:
	if String(f["from"]) != "":
		var rect: Rect2 = f["from_rect"]
		if rect.grow(-ROOM_INSET).has_point(p):
			return ""
		var other := room_at(w["rooms"], p)
		if other == String(f["from"]):
			return ("not inside the %s's walls (%.0f px from its rect's edge)"
					% [other, _rect_gap(rect, p)])
		return ("not in the %s (%s)"
				% [f["from"], ("in the " + other) if other != "" else "outside the house"])
	var indoors := room_at(w["rooms"], p, ROOM_INSET)
	if indoors != "":
		return "an exterior door's slot inside the house (the %s)" % indoors
	if Entry.outward(f, p) < ROOM_INSET:
		return ("round the corner of the house (%.0f px out from the door's wall plane)"
				% Entry.outward(f, p))
	return ""


## The key of the room whose rect (grown by `grow`) holds `p`, or "".
static func room_at(rooms: Array, p: Vector2, grow := 0.0) -> String:
	for r in rooms:
		if (r["rect"] as Rect2).grow(grow).has_point(p):
			return String(r["key"])
	return ""


## "" when `p` is on the navmesh (within `SNAP_SLACK` of where it snaps to), else how far off.
static func on_navmesh(w: Dictionary, p: Vector2) -> String:
	var off := NavBuilder.snap(w["map"], p).distance_to(p)
	return "" if off <= SNAP_SLACK else "off the navmesh by %.0f px" % off


## "" when `p` is reached from the stack side of frame `f` (a route from `START_OUT` px out from the
## wall plane, snapped onto the navmesh) that ends at it and never goes through the doorway's gap;
## else why not.
static func reachable(w: Dictionary, f: Dictionary, p: Vector2) -> String:
	var pos: Vector2 = f["pos"]
	var start := NavBuilder.snap(w["map"], pos + (f["out"] as Vector2) * START_OUT)
	var path := NavBuilder.route(w["map"], start, p)
	if path.is_empty() or path[path.size() - 1].distance_to(p) > REACH_SLACK:
		return ("no route from the stack side reaches it (ends %s)"
				% (str(path[path.size() - 1].round()) if not path.is_empty() else "nowhere"))
	var half := float(f["width"]) * 0.5
	var along: Vector2 = f["along"]
	var a := pos - along * half
	var b := pos + along * half
	var pts: Array = [start] + Array(path)
	for i in range(1, pts.size()):
		if Geometry2D.segment_intersects_segment(pts[i - 1], pts[i], a, b) != null:
			return "its route from the stack side goes through the doorway"
	return ""


## "" when `p` is out of every other doorway's view and funnel (both its framings), else which.
static func clear_of_other_doors(w: Dictionary, f: Dictionary, p: Vector2) -> String:
	var hits: Array = []
	for why in [in_other_funnel(w, f, p), in_other_view(w, f, p)]:
		if why != "":
			hits.append(why)
	return ", ".join(hits)


## "" when `p` is out of every other doorway's funnel, else which.
static func in_other_funnel(w: Dictionary, f: Dictionary, p: Vector2) -> String:
	var hits: Array = []
	for other: Dictionary in w["frames"]:
		if (other["id"] != f["id"]
				and Entry.in_funnel(other, p)
				and not hits.has("in the funnel of %s" % other["id"])):
			hits.append("in the funnel of %s" % other["id"])
	return ", ".join(hits)


## "" when `p` is out of every other doorway's view (both its framings), else which.
static func in_other_view(w: Dictionary, f: Dictionary, p: Vector2) -> String:
	var hits: Array = []
	for other: Dictionary in w["frames"]:
		if other["id"] != f["id"] and in_view(w, other, p):
			hits.append("in the view of %s from the %s" % [other["id"], other["room_key"]])
	return ", ".join(hits)


## "" when a body at `p` stands clear of every carved furniture footprint by `FURNITURE_CLEAR`, else
## on or against which.
static func clear_of_furniture(w: Dictionary, p: Vector2) -> String:
	for hole: PackedVector2Array in w["holes"]:
		if Geometry2D.is_point_in_polygon(p, hole):
			return "on solid furniture (footprint round %s)" % str(_centre(hole).round())
		var gap := _edge_distance(hole, p)
		if gap < FURNITURE_CLEAR:
			return ("against solid furniture (%.0f px from the footprint round %s)"
					% [gap, str(_centre(hole).round())])
	return ""


## Whether a body at `p` stands in the view of doorway frame `f` (the test's own copy,
## `door_view_probe.gd`): inside its polygon by `View.EDGE_MARGIN`, on the outer side of its wall,
## with a clear line past the walls of the world `w` to the doorway's gap.
static func in_view(w: Dictionary, f: Dictionary, p: Vector2) -> bool:
	if Entry.outward(f, p) <= 0.0:
		return false
	var poly := View.polygon(f)
	if not Geometry2D.is_point_in_polygon(p, poly) or _edge_distance(poly, p) < View.EDGE_MARGIN:
		return false
	var pos: Vector2 = f["pos"]
	var along: Vector2 = f["along"]
	var half := float(f["width"]) * 0.5 - 4.0
	for target in [pos, pos - along * half, pos + along * half]:
		if walls_clear(w["space"], p, target):
			return true
	return false


## Whether no wall (a static body) lies on the line from `a` to `b` in `space`; furniture and
## characters are looked past.
static func walls_clear(space: PhysicsDirectSpaceState2D, a: Vector2, b: Vector2) -> bool:
	var exclude: Array = []
	for i in 12:
		var query := PhysicsRayQueryParameters2D.create(a, b, PhysicsLayers.SOLID)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		if hit["collider"] is StaticBody2D:
			return false
		exclude.append(hit["rid"])
	return false


## Whether side `side` of frame `f` has room for one (E21's "while it has room"): some spot of the
## test's own along that side's wall passes the rules a slot passes (`room_for_one`).
static func side_has_room(w: Dictionary, f: Dictionary, side: int) -> bool:
	return room_for_one(w, f, side) != Vector2.INF


## The nearest spot to the door, of the test's own along side `side` of frame `f`'s wall, where one
## could stand by the rules a slot keeps (in the stack side, on the navmesh, reached from the stack
## side, off furniture, out of the other doorways' funnels and, unless `ignore_views`, their views),
## or INF. The spots run against the wall (`ROOM_FOR_ONE_OUT` out, give or take a few px) from
## `ROOM_FOR_ONE_PAST` past the jamb every `ROOM_FOR_ONE_STEP` px along it, skipping furniture
## (E22), to the wall's end: the stack side's room's corner (outdoors, `ROOM_FOR_ONE_REACH` px), or
## another doorway's funnel (E21).
static func room_for_one(w: Dictionary, f: Dictionary, side: int, ignore_views := false) -> Vector2:
	var pos: Vector2 = f["pos"]
	var out: Vector2 = f["out"]
	var along: Vector2 = (f["along"] as Vector2) * side
	var reach := ROOM_FOR_ONE_REACH
	if String(f["from"]) != "":
		reach = _ray_to_edge(f["from_rect"], pos + out * ROOM_FOR_ONE_OUT, along)
	var past := float(f["width"]) * 0.5 + ROOM_FOR_ONE_PAST
	while past <= reach:
		for o in [ROOM_FOR_ONE_OUT, ROOM_FOR_ONE_OUT - 6.0, ROOM_FOR_ONE_OUT + 8.0]:
			var p: Vector2 = pos + out * o + along * past
			if in_other_funnel(w, f, p) != "":
				return Vector2.INF   # The wall's end: another doorway's funnel.
			if (in_stack_room(w, f, p) != ""
					or on_navmesh(w, p) != ""
					or reachable(w, f, p) != ""
					or clear_of_furniture(w, p) != ""):
				continue
			if not ignore_views and in_other_view(w, f, p) != "":
				continue
			return p
		past += ROOM_FOR_ONE_STEP
	return Vector2.INF


# --- Rule 6's fallbacks: ways in with no clear spot against the wall ------------------------------


## Which rule frame `f`'s slots answer to (the ticket's rule 6): `wall` when some spot of the test's
## own beside the door, against its wall, keeps every rule (E20 to E22 as written); `views` when
## every such spot is in some other doorway's view (the stack takes the spots seen from the fewest
## other doorways, never in a funnel, in the same room); `open_floor` when there is no spot against
## the wall at all (slots on the stack side's open floor off the door's axis and out of its funnel;
## the members the room cannot hold are the stack's tail, holding in the room they came by at its
## doorway into the small room); `dead_end` when there is no spot against the wall and the stack
## side is a room whose only doorway is this one, so a tail has nowhere to hold (its open floor
## takes as many slots as it holds at the normal spacing, `dead_end_capacity`, and the members past
## that get none).
static func way_kind(w: Dictionary, f: Dictionary) -> String:
	if side_has_room(w, f, 1) or side_has_room(w, f, -1):
		return "wall"
	if room_for_one(w, f, 1, true) != Vector2.INF or room_for_one(w, f, -1, true) != Vector2.INF:
		return "views"
	if String(f["from"]) != "" and ways_into_stack_room(w, f).is_empty():
		return "dead_end"
	return "open_floor"


## How many members the stack side's room of a `dead_end` way in (`way_kind`) holds, by the test's
## own count: the most points of a `CAPACITY_GRID` px grid over the room, pairwise at least
## `STACK_SPACING` apart (the normal spacing, never squeezed), that each keep the open-floor rules
## (`point_faults` with kind `dead_end`: in the room, on the navmesh, reached from the stack side,
## off furniture, out of the other doorways' funnels, off the door's axis by a body, out of its
## funnel), found by an exhaustive search up to `MAX_STACK`: `{ count, points }` (`points`: one such
## packing). `cache` is `point_faults`'s.
static func dead_end_capacity(w: Dictionary, f: Dictionary, cache: Dictionary) -> Dictionary:
	var rect: Rect2 = (f["from_rect"] as Rect2).grow(-ROOM_INSET)
	var pts := PackedVector2Array()
	var y := rect.position.y
	while y <= rect.end.y:
		var x := rect.position.x
		while x <= rect.end.x:
			var p := Vector2(x, y)
			if point_faults(w, f, p, cache, "dead_end").is_empty():
				pts.append(p)
			x += CAPACITY_GRID
		y += CAPACITY_GRID
	var all := PackedInt32Array()
	for i in pts.size():
		all.append(i)
	var best: Array = []
	for need in range(1, MAX_STACK + 1):
		var found := _packing(pts, all, need)
		if found.is_empty():
			break
		best = found
	return { "count": best.size(), "points": best }


## `need` points of `pts` (by the indices `cands`, in order) pairwise at least `STACK_SPACING`
## apart, or [] when no such set exists (searched exhaustively: each point in turn with the points
## after it that it leaves room for).
static func _packing(pts: PackedVector2Array, cands: PackedInt32Array, need: int) -> Array:
	if cands.size() < need:
		return []
	if need == 1:
		return [pts[cands[0]]]
	if need == 2:
		return _pair(pts, cands)
	var sq := STACK_SPACING * STACK_SPACING
	for i in cands.size() - need + 1:
		var p := pts[cands[i]]
		var rest := PackedInt32Array()
		for j in range(i + 1, cands.size()):
			if p.distance_squared_to(pts[cands[j]]) >= sq:
				rest.append(cands[j])
		var others := _packing(pts, rest, need - 1)
		if not others.is_empty():
			return [p] + others
	return []


## Two points of `pts` (by the indices `cands`) at least `STACK_SPACING` apart, or []. The bounding
## box decides most sets at once: two points as far apart as its width or height are the answer, and
## none exist when its diagonal is shorter than the spacing.
static func _pair(pts: PackedVector2Array, cands: PackedInt32Array) -> Array:
	var lo := pts[cands[0]]
	var hi := lo
	var lo_x := lo
	var hi_x := lo
	var lo_y := lo
	var hi_y := lo
	for c in cands:
		var p := pts[c]
		lo = lo.min(p)
		hi = hi.max(p)
		if p.x < lo_x.x:
			lo_x = p
		if p.x > hi_x.x:
			hi_x = p
		if p.y < lo_y.y:
			lo_y = p
		if p.y > hi_y.y:
			hi_y = p
	if lo.distance_to(hi) < STACK_SPACING:
		return []
	if hi_x.x - lo_x.x >= STACK_SPACING:
		return [lo_x, hi_x]
	if hi_y.y - lo_y.y >= STACK_SPACING:
		return [lo_y, hi_y]
	var sq := STACK_SPACING * STACK_SPACING
	for i in cands.size():
		for j in range(i + 1, cands.size()):
			if pts[cands[i]].distance_squared_to(pts[cands[j]]) >= sq:
				return [pts[cands[i]], pts[cands[j]]]
	return []


## Whether `p` lies in frame `f`'s wall band, where a `wall` way in's slots stand (as `point_faults`
## judges a wall slot): in the stack side, beside the door (half its width plus a body along the
## wall, either side) and against the wall or a step out from it (the first and the second file,
## `ROW1_MIN` to `ROW2_MAX` out). A slot of a short wall's stack outside it is one of the
## overflow's.
static func in_wall_band(w: Dictionary, f: Dictionary, p: Vector2) -> bool:
	var o := Entry.outward(f, p)
	return (absf(Entry.lateral(f, p)) >= float(f["width"]) * 0.5 + BESIDE
			and o >= ROW1_MIN
			and o <= ROW2_MAX
			and in_stack_room(w, f, p) == "")


## How many members the wall band of a `wall` way in (`way_kind`) holds, both sides and the second
## file counted, by the test's own count: the most of its valid points (`point_faults` with kind
## `wall` empty), pairwise at least `STACK_SPACING` apart, searched exhaustively up to `MAX_STACK`
## (`_packing`). The points are a `CAPACITY_GRID` px grid over the band, laid from the jamb's
## clearance out along the wall to the stack side's room's edge (outdoors, `ROOM_FOR_ONE_REACH`),
## plus `extra` (the way in's own slots that are valid wall points: a valid point is one wherever it
## lies). `{ count, points }`. With kind `views` and a `bar` (`views_capacity`), a valid point is
## one that keeps the `views` rules at that bar instead, and the result carries the `bar`.
static func wall_capacity(
	w: Dictionary,
	f: Dictionary,
	cache: Dictionary,
	extra: Array = [],
	kind := "wall",
	bar := 0,
) -> Dictionary:
	var pts := PackedVector2Array()
	var pos: Vector2 = f["pos"]
	var out: Vector2 = f["out"]
	var start := float(f["width"]) * 0.5 + BESIDE
	for side in [1, -1]:
		var along: Vector2 = (f["along"] as Vector2) * side
		var reach := ROOM_FOR_ONE_REACH
		if String(f["from"]) != "":
			reach = _ray_to_edge(f["from_rect"], pos, along) + ROOM_INSET
		var lat := start
		while lat <= reach:
			var o := ROW1_MIN
			while o <= ROW2_MAX:
				var p: Vector2 = pos + out * o + along * lat
				if in_wall_band(w, f, p) and point_faults(w, f, p, cache, kind, bar).is_empty():
					pts.append(p)
				o += CAPACITY_GRID
			lat += CAPACITY_GRID
	for p: Vector2 in extra:
		if (in_wall_band(w, f, p)
				and point_faults(w, f, p, cache, kind, bar).is_empty()
				and not pts.has(p)):
			pts.append(p)
	var found := _capacity(pts, MAX_STACK)
	if kind == "views":
		found["bar"] = bar
	return found


## How many members the wall band of a `views` way in (`way_kind`) holds by its fewest-seen spots
## (the user's round-2 decision on rule 6), or {} when the test's own pick of the wall's spots
## (`fewest_views_pick` of `spots`, `wall_spots`) already takes `MAX_STACK`: then no stack outgrows
## it. Else the stacks past that pick answer to the bar of every spot (`fewest_views_bar`), and the
## band holds the most of its points that keep the `views` rules at that bar (never in a funnel,
## seen from no more other doorways than it), searched as `wall_capacity` searches, with the spots
## and `extra` (the way in's own slots) among the points: `{ count, points, bar }`.
static func views_capacity(
	w: Dictionary,
	f: Dictionary,
	cache: Dictionary,
	spots: Array,
	extra: Array = [],
) -> Dictionary:
	if fewest_views_pick(spots, MAX_STACK).size() >= MAX_STACK:
		return {}
	return wall_capacity(
		w,
		f,
		cache,
		spots.map(func(s): return s["point"]) + extra,
		"views",
		fewest_views_bar(spots, MAX_STACK),
	)


## The points of frame `f`'s stack side a short wall's overflow may stand on (the user's round-2
## decision on rule 6): a `CAPACITY_GRID` px grid over the stack side's room (by `ROOM_INSET`;
## outdoors, a box out from the door `ROOM_FOR_ONE_REACH` px along the wall either side and out from
## it), outside the wall band, each keeping the open-floor rules (`point_faults` with kind
## `overflow`). Cached per way in in `cache`.
static func open_floor_points(
	w: Dictionary,
	f: Dictionary,
	cache: Dictionary,
) -> PackedVector2Array:
	var key := "open floor %s>%s" % [f["id"], f["room_key"]]
	if cache.has(key):
		return cache[key]
	var pts := PackedVector2Array()
	var cands: Array = []
	if String(f["from"]) != "":
		var rect: Rect2 = (f["from_rect"] as Rect2).grow(-ROOM_INSET)
		var y := rect.position.y
		while y <= rect.end.y:
			var x := rect.position.x
			while x <= rect.end.x:
				cands.append(Vector2(x, y))
				x += CAPACITY_GRID
			y += CAPACITY_GRID
	else:
		var lat := -ROOM_FOR_ONE_REACH
		while lat <= ROOM_FOR_ONE_REACH:
			var o := ROOM_INSET
			while o <= ROOM_FOR_ONE_REACH:
				cands.append((f["pos"] as Vector2) + (f["out"] as Vector2) * o
						+ (f["along"] as Vector2) * lat)
				o += CAPACITY_GRID
			lat += CAPACITY_GRID
	for p: Vector2 in cands:
		if not in_wall_band(w, f, p) and point_faults(w, f, p, cache, "overflow").is_empty():
			pts.append(p)
	cache[key] = pts
	return pts


## How many more members the open floor of a short wall's way in then holds, beside the wall slots
## `taken` (points): the most `open_floor_points` pairwise, and from every taken point, at least
## `STACK_SPACING` apart, searched exhaustively up to `need`: `{ count, points }` (a count of `need`
## means at least that many).
static func open_floor_capacity(
	w: Dictionary,
	f: Dictionary,
	cache: Dictionary,
	taken: Array,
	need: int,
) -> Dictionary:
	var pts := PackedVector2Array()
	for p in open_floor_points(w, f, cache):
		if taken.all(func(q): return (q as Vector2).distance_to(p) >= STACK_SPACING):
			pts.append(p)
	return _capacity(pts, need)


## The most points of `pts` pairwise at least `STACK_SPACING` apart, up to `most` (`_packing`,
## exhaustive): `{ count, points }`.
static func _capacity(pts: PackedVector2Array, most: int) -> Dictionary:
	var all := PackedInt32Array()
	for i in pts.size():
		all.append(i)
	var best: Array = []
	for need in range(1, most + 1):
		var found := _packing(pts, all, need)
		if found.is_empty():
			break
		best = found
	return { "count": best.size(), "points": best }


## How many other doorways (by id, either framing) have `p` in their view.
static func view_count(w: Dictionary, f: Dictionary, p: Vector2) -> int:
	var ids := {}
	for other: Dictionary in w["frames"]:
		if other["id"] != f["id"] and in_view(w, other, p):
			ids[other["id"]] = true
	return ids.size()


## Every spot of the test's own beside the door against its wall, on both sides, that keeps every
## rule but the other doorways' views (`room_for_one`'s spots, all of them):
## `[{ point, side, views }]`.
static func wall_spots(w: Dictionary, f: Dictionary) -> Array:
	var spots: Array = []
	var pos: Vector2 = f["pos"]
	var out: Vector2 = f["out"]
	for side in [1, -1]:
		var along: Vector2 = (f["along"] as Vector2) * side
		var reach := ROOM_FOR_ONE_REACH
		if String(f["from"]) != "":
			reach = _ray_to_edge(f["from_rect"], pos + out * ROOM_FOR_ONE_OUT, along)
		var past := float(f["width"]) * 0.5 + ROOM_FOR_ONE_PAST
		var walled := false
		while past <= reach and not walled:
			for o in [ROOM_FOR_ONE_OUT, ROOM_FOR_ONE_OUT - 6.0, ROOM_FOR_ONE_OUT + 8.0]:
				var p: Vector2 = pos + out * o + along * past
				if in_other_funnel(w, f, p) != "":
					walled = true   # The wall's end: another doorway's funnel.
					break
				if (in_stack_room(w, f, p) != ""
						or on_navmesh(w, p) != ""
						or reachable(w, f, p) != ""
						or clear_of_furniture(w, p) != ""):
					continue
				spots.append({ "point": p, "side": side, "views": view_count(w, f, p) })
				break
			past += ROOM_FOR_ONE_STEP
	return spots


## The most other doorways a slot of a stack of `count` may be seen from on a `views` way in: the
## test's own pick of `count` spots of `spots` (`wall_spots`), `STACK_SPACING` apart, fewest views
## first (nearest the door on a tie); the most-seen of the spots when they cannot take `count`.
static func fewest_views_bar(spots: Array, count: int) -> int:
	var picks := fewest_views_pick(spots, count)
	var pool := picks if picks.size() == count else spots
	var bar := 0
	for s in pool:
		bar = maxi(bar, int(s["views"]))
	return bar


## The test's own pick of up to `count` spots of `spots` (`wall_spots`), `STACK_SPACING` apart,
## fewest views first (nearest the door on a tie): what `fewest_views_bar` reads its bar from (fewer
## than `count` when the spots cannot take them).
static func fewest_views_pick(spots: Array, count: int) -> Array:
	var order := spots.duplicate()
	order.sort_custom(func(a, b): return (
		a["views"] < b["views"]
			if a["views"] != b["views"]
			else a["point"].length_squared() < b["point"].length_squared()
	))
	var picks: Array = []
	for s in order:
		if picks.all(
				func(q): return (q["point"] as Vector2).distance_to(s["point"]) >= STACK_SPACING,
		):
			picks.append(s)
		if picks.size() == count:
			break
	return picks


## "" when `p` is a tail spot of frame `f` (rule 6): in a room joined to the stack-side room by
## another doorway (the room the tail came by, or outside), within `TAIL_REACH` of that doorway, off
## its axis by a body and out of its funnel, on the navmesh and off furniture; else why not.
static func tail_fault(w: Dictionary, f: Dictionary, p: Vector2) -> String:
	var ways := ways_into_stack_room(w, f)
	if ways.is_empty():
		return "not in the %s, which has no other doorway for a tail to hold at" % f["from"]
	var best := ""
	var best_d := INF
	for fo: Dictionary in ways:
		var d := (fo["pos"] as Vector2).distance_to(p)
		if d >= best_d:
			continue
		var why: Array = []
		var where := in_stack_room(w, fo, p)
		if where != "":
			why.append(where)
		if d > TAIL_REACH:
			why.append("%.0f px from the doorway" % d)
		if absf(Entry.lateral(fo, p)) < BODY:
			why.append("on the doorway's axis")
		if Entry.in_funnel(fo, p):
			why.append("in the doorway's funnel")
		for extra in [on_navmesh(w, p), clear_of_furniture(w, p)]:
			if extra != "":
				why.append(extra)
		best_d = d
		best = (""
				if why.is_empty()
				else "not a tail spot at %s (from the %s): %s"
					% [fo["id"], fo["from"] if fo["from"] != "" else "outside", ", ".join(why)])
	return best


## Every rule one slot `p` breaks, as `[rule, why]` pairs (empty when it keeps them all), on a way
## in of kind `kind` (`way_kind`):
## - `wall`: E20 (in the stack side's room, on the navmesh, reached from the stack side, out of the
##   other doorways' views and funnels), E22 (off furniture), E2 / E21 (beside the door, against the
##   wall or a step out from it);
## - `views`: the same, but seen from no more other doorways than `bar` (`fewest_views_bar`) instead
##   of out of every view;
## - `open_floor`: in the stack side's room on its open floor (on the navmesh, reached, off
##   furniture, out of the other doorways' funnels, off the door's axis by a body, out of its
##   funnel), or else a tail spot (`tail_fault`);
## - `dead_end`: the same open floor, and never a tail spot: the room has no other doorway for a
##   tail to hold at;
## - `overflow` (a short wall's slot outside its wall band, `in_wall_band`, on a `wall` way in or a
##   `views` one): the same open floor and out of every other doorway's view too, or else a tail
##   spot (`tail_fault`), or, from a room with no other doorway, nothing (the dead-end cap).
## Cached per point, kind and bar in `cache`.
static func point_faults(
	w: Dictionary,
	f: Dictionary,
	p: Vector2,
	cache: Dictionary,
	kind := "wall",
	bar := 0,
) -> Array:
	var key := "%s>%s@%s %s %d" % [f["id"], f["room_key"], str(p.round()), kind, bar]
	if cache.has(key):
		return cache[key]
	var out: Array = []
	var why := in_stack_room(w, f, p)
	if why != "" and kind == "open_floor":
		var tail := tail_fault(w, f, p)
		if tail != "":
			out.append([
				"E20 fallback: the tail in the room it came by",
				"%s, and %s" % [why, tail],
			])
		cache[key] = out
		return out
	if why != "" and kind == "dead_end":
		out.append([
			"E20 fallback: a dead end's slots all in its room",
			"%s, and the %s has no other doorway for a tail to hold at" % [why, f["from"]],
		])
		cache[key] = out
		return out
	if why != "" and kind == "overflow" and String(f["from"]) != "":
		if ways_into_stack_room(w, f).is_empty():
			out.append([
				"E20 fallback: a dead end's slots all in its room",
				"%s, and the %s has no other doorway for a tail to hold at" % [why, f["from"]],
			])
		else:
			var tail := tail_fault(w, f, p)
			if tail != "":
				out.append([
					"E20 fallback: the tail in the room it came by",
					"%s, and %s" % [why, tail],
				])
		cache[key] = out
		return out
	if why != "":
		out.append(["E20 in the stack's room", why])
	why = on_navmesh(w, p)
	if why != "":
		out.append(["E20 on the navmesh", why])
	why = reachable(w, f, p)
	if why != "":
		out.append(["E20 reachable from the stack side", why])
	why = (clear_of_other_doors(w, f, p)
			if kind == "wall" or kind == "overflow"
			else in_other_funnel(w, f, p))
	if why != "":
		out.append(["E20 out of other doorways' view and funnel", why])
	if kind == "views":
		var seen := view_count(w, f, p)
		if seen > bar:
			out.append([
				"E20 fallback: seen from the fewest other doorways",
				("seen from %d other doorway(s) (%s) where the wall's spots seen from %d would "
						+ "hold the stack") % [seen, in_other_view(w, f, p), bar],
			])
	why = clear_of_furniture(w, p)
	if why != "":
		out.append(["E22 off furniture", why])
	var lateral := absf(Entry.lateral(f, p))
	if kind == "open_floor" or kind == "dead_end" or kind == "overflow":
		if lateral < BODY:
			out.append([
				"E20 fallback: open floor off the door's axis",
				"%.0f px from the door's axis" % lateral,
			])
		if Entry.in_funnel(f, p):
			out.append([
				"E20 fallback: open floor out of the door's funnel",
				"in the funnel (%.0f px out, %.0f px along)" % [Entry.outward(f, p), lateral],
			])
		cache[key] = out
		return out
	if lateral < float(f["width"]) * 0.5 + BESIDE:
		out.append([
			"E2 beside the door",
			"%.0f px along the wall from the door's centre, in front of its %.0f px opening"
				% [lateral, f["width"]],
		])
	var o := Entry.outward(f, p)
	if o < ROW1_MIN or o > ROW2_MAX:
		out.append(["E2/E21 against the wall or a step out", "%.0f px out from the wall plane" % o])
	cache[key] = out
	return out


## The rules a whole stack's layout (`slots`, from `layout`) breaks as a stack, for a stack of
## `count` on side `side` of frame `f`: one slot per member numbered 1..count, spacing kept (E2,
## E22), each file nearest the door first (E2), the point on the asked side when it has room (E21:
## an ordered stack starts on the order's side), a second file only once neither side has room
## (E21). `[n, rule, why]` triples (`n` 0 for the stack as a whole). On an `open_floor` way in
## (`way_kind`) the files give way to rule 6's: the tail (the slots outside the stack side's room)
## comes after every slot in it. On a `dead_end` way in the stack takes as many slots as the room
## holds (`capacity`, from `dead_end_capacity`): exactly min(count, its count), numbered 1.., and no
## more; the members past it get none. Only there may a stack have fewer slots than members, and on
## a short wall's way in from a room with no other doorway (below).
##
## A `wall` way in whose wall band holds fewer than the stack, or a `views` one whose band's
## fewest-seen spots do (`capacity` `{ wall, open }`: `wall_capacity` / `views_capacity`, and
## `open_floor_capacity` beside this layout's wall slots, up to the members past the wall; the
## user's round-2 decisions on rule 6) takes the chain instead (`short_wall_faults`); the file rules
## then apply to its wall slots alone.
static func stack_faults(
	w: Dictionary,
	f: Dictionary,
	slots: Array,
	count: int,
	side: int,
	kind := "wall",
	capacity := {},
) -> Array:
	var out: Array = []
	var numbers: Array = slots.map(func(s): return int(s["n"]))
	var sorted_numbers := numbers.duplicate()
	sorted_numbers.sort()
	if is_short_wall(kind, capacity, count):
		out.append_array(short_wall_faults(w, f, slots, count, capacity))
	elif kind == "dead_end":
		var holds := int(capacity.get("count", 0))
		var wanted_here: Array = range(1, mini(count, holds) + 1)
		if sorted_numbers != wanted_here:
			var points: Array = (capacity.get("points", []) as Array).map(
				func(p): return str((p as Vector2).round()),
			)
			out.append([
				0,
				"E20 fallback: a dead end takes as many slots as its room holds",
				("slots %s for a stack of %d, where the %s holds %d at %.0f px apart (the test's "
						+ "own packing: %s), so slots %s")
					% [
						str(numbers),
						count,
						f["from"],
						holds,
						STACK_SPACING,
						", ".join(points)
							if not points.is_empty()
							else "no point keeps the open-floor rules",
						str(wanted_here),
					],
			])
	elif sorted_numbers != range(1, count + 1):
		out.append([0, "one slot per member", "slots %s for a stack of %d" % [str(numbers), count]])
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			var d := (slots[i]["point"] as Vector2).distance_to(slots[j]["point"])
			if d < MIN_SPACING:
				out.append([
					int(slots[j]["n"]),
					"E2/E22 spacing kept",
					"%.0f px from slot %d" % [d, int(slots[i]["n"])],
				])
	if kind == "dead_end":
		# Every slot in the room (`point_faults`), spacing kept (above): no files, no tail.
		return out
	if kind == "open_floor":
		for s in slots:
			if in_stack_room(w, f, s["point"]) == "":
				continue   # In the room; `s` is the tail's below.
			for o in slots:
				if int(o["n"]) > int(s["n"]) and in_stack_room(w, f, o["point"]) == "":
					out.append([
						int(o["n"]),
						"E20 fallback: the tail last",
						"in the %s, after slot %d of the tail" % [f["from"], int(s["n"])],
					])
		return out
	if is_short_wall(kind, capacity, count):
		# The files are the wall's; the overflow is judged above.
		slots = slots.filter(func(s): return in_wall_band(w, f, s["point"]))
	for s in slots:
		for o in slots:
			if (int(o["n"]) <= int(s["n"])
					or side_of(f, o["point"]) != side_of(f, s["point"])
					or _row(f, o["point"]) != _row(f, s["point"])):
				continue
			if absf(Entry.lateral(f, o["point"])) < absf(Entry.lateral(f, s["point"])):
				out.append([
					int(o["n"]),
					"E2 file nearest the door first",
					"nearer the door than slot %d in its file" % int(s["n"]),
				])
	var first: Array = slots.filter(func(s): return int(s["n"]) == 1)
	if not first.is_empty() and side_of(f, first[0]["point"]) != side and side_has_room(w, f, side):
		out.append([
			1,
			"E21 the point on the order's side",
			"on side %+d though side %+d has room" % [side_of(f, first[0]["point"]), side],
		])
	var second: Array = slots.filter(
		func(s): return _row(f, s["point"]) == 2 and in_stack_room(w, f, s["point"]) == "",
	)
	if not second.is_empty():
		for s in [1, -1]:
			var used: bool = slots.any(
				func(x): return _row(f, x["point"]) == 1 and side_of(f, x["point"]) == s,
			)
			if not used and side_has_room(w, f, s):
				out.append([
					int(second[0]["n"]),
					"E21 the other side before a second file",
					"a second file while side %+d has room and no slot" % s,
				])
	return out


## Whether a stack of `count` on a way in of kind `kind` outgrows its wall band: a `wall` way in
## whose wall holds fewer (`capacity["wall"]`, `wall_capacity`), or a `views` way in whose wall's
## fewest-seen spots do (`views_capacity`).
static func is_short_wall(kind: String, capacity: Dictionary, count: int) -> bool:
	return ((kind == "wall" or kind == "views")
			and capacity.has("wall")
			and count > int(capacity["wall"]["count"]))


## The capacities the test found for a short wall's stack, as its failure lines name them: what the
## wall holds (and the test's own packing; on a `views` way in, its spots seen from no more other
## doorways than the bar), what the open floor then holds beside this layout's wall slots
## (`capacity["open"]`: `{ count, points, need }`, a count of `need` meaning at least that many),
## and whether a tail may hold.
static func capacity_text(w: Dictionary, f: Dictionary, capacity: Dictionary) -> String:
	var wall: Dictionary = capacity["wall"]
	var open: Dictionary = capacity.get("open", {})
	var pts := func(a: Array) -> String:
		return ", ".join(a.map(func(p): return str((p as Vector2).round())))
	var opens := "the open floor then holds %s%d more%s" % [
		"at least "
			if int(open.get("count", 0)) >= int(open.get("need", 0))
				and int(open.get("need", 0)) > 0
			else "",
		int(open.get("count", 0)),
		(" (%s)" % pts.call(open["points"]))
			if not (open.get("points", []) as Array).is_empty()
			else "",
	]
	var ways := ways_into_stack_room(w, f)
	var tail := "no tail outdoors"
	if not ways.is_empty():
		tail = "the tail holds at %s" % ", ".join(ways.map(func(fo): return fo["id"]))
	elif String(f["from"]) != "":
		tail = "no tail: the %s has no other doorway" % f["from"]
	var walls := "the wall holds"
	if wall.has("bar"):
		walls = "the wall's spots seen from at most %d other doorway(s) hold" % int(wall["bar"])
	return ("[%s %d at %.0f px apart (the test's packing: %s), %s, %s]"
			% [walls, int(wall["count"]), STACK_SPACING, pts.call(wall["points"]), opens, tail])


## The chain a short wall's stack of `count` keeps (the user's round-2 decisions on rule 6, for a
## `wall` way in and a `views` one alike), as `[n, rule, why]` triples: its wall band
## (`in_wall_band`) takes exactly min(count, W) slots, W what the wall holds (`capacity["wall"]`; on
## a `views` way in, its fewest-seen spots), numbered before every other slot; the members past
## those stand on the open floor of the same room, as many as it then holds (O, `capacity["open"]`),
## numbered after the wall slots; then the tail at the room's other doorway, numbered last; or, from
## a room with no other doorway (and outdoors, where no tail holds), no more slots: exactly
## min(count, W + O). Each slot's own rules are `point_faults`'s (the way in's kind, `wall` or
## `views` at its bar, in the band, `overflow` outside it); the spacing is `stack_faults`'s.
static func short_wall_faults(
	w: Dictionary,
	f: Dictionary,
	slots: Array,
	count: int,
	capacity: Dictionary,
) -> Array:
	var out: Array = []
	var holds := int(capacity["wall"]["count"])
	var opens := int((capacity.get("open", {}) as Dictionary).get("count", 0))
	var want_wall := mini(count, holds)
	var want_floor := mini(count - want_wall, opens)
	var tail_ok := String(f["from"]) != "" and not ways_into_stack_room(w, f).is_empty()
	var want_total := count if tail_ok else want_wall + want_floor
	var caps := capacity_text(w, f, capacity)
	var ordered := slots.duplicate()
	ordered.sort_custom(func(a, b): return int(a["n"]) < int(b["n"]))
	var walls: Array = ordered.filter(func(s): return in_wall_band(w, f, s["point"]))
	var on_floor: Array = ordered.filter(
		func(s): return not in_wall_band(w, f, s["point"]) and in_stack_room(w, f, s["point"]) == ""
	)
	var tail: Array = ordered.filter(func(s): return in_stack_room(w, f, s["point"]) != "")
	var overflow: Array = ordered.filter(func(s): return not in_wall_band(w, f, s["point"]))
	if walls.size() < want_wall and not overflow.is_empty():
		out.append([
			int(overflow[0]["n"]),
			"E20 fallback: a short wall full before its overflow",
			"off the wall with %d wall slot(s) where the wall takes %d %s"
				% [walls.size(), want_wall, caps],
		])
	for i in range(want_wall, walls.size()):
		out.append([
			int(walls[i]["n"]),
			"E20 fallback: no more wall slots than the wall holds",
			"wall slot %d of %d where the wall takes %d %s"
				% [i + 1, walls.size(), want_wall, caps],
		])
	if not walls.is_empty():
		var last_wall := int(walls[walls.size() - 1]["n"])
		for o in overflow:
			if int(o["n"]) < last_wall:
				out.append([
					int(o["n"]),
					"E20 fallback: the overflow numbered after every wall slot",
					"%s before wall slot %d %s" % [
						"on the open floor"
							if in_stack_room(w, f, o["point"]) == ""
							else "in the tail",
						last_wall,
						caps,
					],
				])
	for i in range(opens, on_floor.size()):
		out.append([
			int(on_floor[i]["n"]),
			"E20 fallback: no more open-floor slots than the open floor holds",
			"open-floor slot %d of %d where it holds %d %s" % [i + 1, on_floor.size(), opens, caps],
		])
	if not tail.is_empty() and on_floor.size() < want_floor:
		out.append([
			int(tail[0]["n"]),
			"E20 fallback: the open floor full before the tail",
			"a tail slot with %d open-floor slot(s) where it takes %d %s"
				% [on_floor.size(), want_floor, caps],
		])
	for t in tail:
		for s in on_floor:
			if int(s["n"]) > int(t["n"]):
				out.append([
					int(s["n"]),
					"E20 fallback: the tail last",
					"in the %s, after slot %d of the tail %s" % [f["from"], int(t["n"]), caps],
				])
	var numbers: Array = ordered.map(func(s): return int(s["n"]))
	if numbers != range(1, want_total + 1):
		if tail_ok:
			out.append([
				0,
				"one slot per member",
				"slots %s for a stack of %d %s" % [str(numbers), count, caps],
			])
		else:
			out.append([
				0,
				"E20 fallback: a short wall's dead end takes as many as its wall and open floor "
					+ "hold",
				"slots %s for a stack of %d, so slots %s %s"
					% [str(numbers), count, str(range(1, want_total + 1)), caps],
			])
	return out


## Which file `p` stands in by its distance from the wall plane: 1 against the wall, 2 a step out.
static func _row(f: Dictionary, p: Vector2) -> int:
	return 1 if Entry.outward(f, p) <= ROW1_MAX else 2


## How far (px) from `p` along `dir` (an axis) to the edge of `rect`, less `ROOM_INSET`.
static func _ray_to_edge(rect: Rect2, p: Vector2, dir: Vector2) -> float:
	var d := 0.0
	if dir.x > 0.5:
		d = rect.end.x - p.x
	elif dir.x < -0.5:
		d = p.x - rect.position.x
	elif dir.y > 0.5:
		d = rect.end.y - p.y
	else:
		d = p.y - rect.position.y
	return d - ROOM_INSET


## How far (px) `p` lies inside `rect` from its nearest edge (negative outside).
static func _rect_gap(rect: Rect2, p: Vector2) -> float:
	return minf(
		minf(p.x - rect.position.x, rect.end.x - p.x),
		minf(p.y - rect.position.y, rect.end.y - p.y),
	)


static func _edge_distance(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in poly.size():
		best = minf(
			best,
			p.distance_to(Geometry2D.get_closest_point_to_segment(
				p, poly[i], poly[(i + 1) % poly.size()],
			)),
		)
	return best


static func _centre(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for q in poly:
		sum += q
	return sum / maxf(poly.size(), 1)
