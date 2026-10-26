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
## Three parts, built once with it, each handed the geometry at the call and holding nothing of it:
## `posts` (where an ordered defender or ambusher stands, entry/entry_posts.gd), `slots` (where a
## stack stands and walks, entry/entry_slots.gd) and `layouts` (where the laid geometry is kept, the
## NPC's own and the map's shared one, entry/entry_layouts.gd).
##
## Pure geometry over the house's openings (Main's `WorldGen.get_openings`, injected), its rooms,
## the nav map (slots and pie points are snapped onto it) and sight rays (via the vision sense). The
## walls never move, so an opening's geometry is built once, the first time it is asked for on a
## baked map, and kept. No policy: it never decides which door, which slot or when to go.

const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const AgentDoorViews := preload("res://scenes/ai/perception/agent_door_views.gd")
## The doorway's fatal funnel and the claims' fields (stack/stack_claim.gd).
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const StackLayout := preload("res://scenes/ai/perception/stack/stack_layout.gd")
const EntrySlots := preload("res://scenes/ai/perception/entry/entry_slots.gd")
const EntryPosts := preload("res://scenes/ai/perception/entry/entry_posts.gd")
const EntryLayouts := preload("res://scenes/ai/perception/entry/entry_layouts.gd")
## How far (px) outside the threshold the "entry point" is that a corner is judged hard or soft
## from.
const ENTRY_POINT_DEPTH := 24.0
## Slots worked out per side: a fuller team queues in the last one.
const MAX_SLOTS := 6
## How many bodies go into a room too small for the team (`short_room`): the point and the second,
## who take its corners.
const SHORT_ROOM_CAPACITY := 2
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
## The step (px) a side's wall is walked along in.
const SLOT_STEP := 4.0

## The sight sense (sight rays over low cover): the perception hands in its own.
var vision: RefCounted = AgentVision.new()
## The doorway views and the walk round them: the perception hands in its own.
var views: RefCounted = AgentDoorViews.new()
## Where a member ordered to defend a room or ambush a doorway stands (`posts.defend_spot(self, …)`,
## `posts.ambush_spot(self, …)`); see entry/entry_posts.gd.
var posts: RefCounted = EntryPosts.new()
## Where a stack may stand and walk at a doorway (`slots.lay(self, …)`, `slots.on_stack_side(self,
## …)`); see entry/entry_slots.gd.
var slots: RefCounted = EntrySlots.new()
## Where the laid geometry is kept, the NPC's and the map's shared one; see entry/entry_layouts.gd.
var layouts: RefCounted = EntryLayouts.new()
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
## The house handed in (`set_house`), as a hash: what the shared geometry is keyed by.
var _house := ""


## Hand in the house: its doorways and rooms (to the views too). Forgets the cached geometry when
## they changed.
func set_house(openings: Array, rooms: Array) -> void:
	views.set_house(openings, rooms)
	if openings == _openings and rooms == _rooms:
		return
	_openings = openings
	_rooms = rooms
	_house = "%d:%d" % [hash(openings), hash(rooms)]
	layouts.cache.clear()
	posts.cache.clear()
	slots.frames = []


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
	if layouts.cache.has(key):
		return layouts.cache[key]
	var shared: Dictionary = layouts.shared_on(map)
	var shared_key := "%s|%s" % [layouts.key(self), key]
	if shared.has(shared_key):
		layouts.cache[key] = shared[shared_key]
		return layouts.cache[key]
	var opening := _opening(id)
	var room := HouseRooms.by_key(_rooms, into)
	if opening.is_empty() or room.is_empty():
		return {}
	var g := _build(opening, room, map, space)
	if NavBuilder.ready(map):
		layouts.cache[key] = g  # Only keep what was snapped onto a baked map.
		shared[shared_key] = g
	return g


## Lay one way in by a doorway of the house whose geometry nobody on `map` has yet (`geometry`), at
## most one a physics frame among every NPC, once the map is baked: called every SEE pass, so the
## doorways are laid in the first frames after the bake rather than in the middle of a decision.
## Once a pass finds them all laid it looks no more (`layouts.warm_done_in`) until the house, a
## tunable or the map's shared geometry changes.
func warm_geometry(map: RID, space: PhysicsDirectSpaceState2D) -> void:
	var frame := Engine.get_physics_frames()
	if frame == EntryLayouts.warmed_frame or space == null:
		return
	var shared: Dictionary = layouts.shared_on(map)
	var inputs: Array = layouts.tuning_inputs(self)
	if is_same(shared, layouts.warm_done_in) and inputs == layouts.warm_done_for:
		return
	if not NavBuilder.ready(map):
		return
	var tuning := str(inputs)
	for o in _openings:
		for k in o.get("rooms", []):
			if not shared.has("%s|%s>%s" % [tuning, opening_id(o), k]):
				EntryLayouts.warmed_frame = frame
				geometry(opening_id(o), str(k), map, space)
				return
	layouts.warm_done_in = shared
	layouts.warm_done_for = inputs


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
		slots.lay(self, g, opening, map, space)
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


## The `count` slots of a `views` layout (`EntrySlots.lay`, its `_views_lays`), its first side
## `side`: of the spots beside the door, those seen from the fewest other doorways that hold `count`
## at `stack_spacing`, side `side`'s file nearest the door first, then the other's, then the second
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
static func _wall_length(rect: Rect2, pos: Vector2, dir: Vector2) -> float:
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
