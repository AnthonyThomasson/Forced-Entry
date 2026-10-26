extends RefCounted
## AI PERCEPTION sub-domain — DOORWAY VIEWS. What an NPC knows about the doorways it walks past
## (`docs/tactical-entry.md` E18): each doorway's VIEW (`door_view`: the area outside it that
## someone inside the room sees through it) and, from the views of the doorways into rooms not clear
## for passing, the walk that keeps out of them (`walk_route`), plus the doorway or view a walk
## comes to first (`threshold_ahead`, `passing_ahead`: what the behaviour's entry guard secures, E9
## / E15).
##
## Pure geometry over the house's openings (Main's `WorldGen.get_openings`, injected), its rooms,
## the nav map (the avoid maps are `NavBuilder.avoid_map`) and wall rays (via the vision sense). The
## walls never move, so a doorway's view is laid out once, the first time it is asked for on a baked
## map, and kept. No policy: it never decides which way to walk. The entry geometry
## (`agent_entry.gd`) reads a doorway's view for a split stack (`cuts_view`); this module never
## reads it.

const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
## How far (px) `threshold_ahead` extends the end of a walk, so a destination in the doorway itself
## crosses it.
const THRESHOLD_EXTEND := 30.0
## How far (px) past the doorway's width a step may cross the wall plane and still count as through
## it.
const THRESHOLD_SLACK := 8.0
## How far (px) off the wall plane a doorway view's rays start (clear of the wall's thickness), and
## how many rays one fan casts along each side edge of the view and across its far edge.
const VIEW_APEX_OUT := 8.0
const VIEW_SIDE_RAYS := 6
const VIEW_FAR_RAYS := 10
## How far (px) the door-avoiding route may end short of the point it was asked for before it counts
## as not reaching it.
const AVOID_REACH := 24.0

## The sight sense (wall rays): the perception hands in its own.
var vision: RefCounted = AgentVision.new()
## How far (px) out of a doorway its view reaches, along its edge rays (E18).
var door_view_depth: float = 450.0
## A walk round the views is taken when no longer than this many times the plain route...
var door_avoid_ratio: float = 2.0
## ... plus this many px.
var door_avoid_slack: float = 300.0
## Whether a walk keeps out of doorway views at all (the NPC's `tuning.entry_guard.enabled`, with
## `entry_enabled` or on an ordered stack's walk).
var avoid_views := true
## Room key -> whether that room counts as safe to walk past (cleared lately enough, or on an
## ordered walk seen empty).
var pass_clear: Callable
## Whether the walk is an ordered stack's (`docs/leadership.md` D4): its approach's way round the
## room being entered and its doorway's view is taken however long it is (no `door_avoid_ratio` cap;
## `walk_route`).
var ordered_approach := false
## The house's doorways (`{ pos, width, front, exit, rooms }`), as injected.
var _openings: Array = []
## The house's rooms (`{ key, type, rect }`).
var _rooms: Array = []
## "<opening id>><room key>@<depth>" -> the view out of that doorway (a polygon).
var _views := {}
## The physics frame `avoided` last worked out its answer in, and for which room...
var _avoided_frame := -1
## ... (`here_key`, "" = outside), for which entry the walk is the approach of...
var _avoided_here := ""
## ... (`entering`, "<opening id>><room key>", "" = none)...
var _avoided_entering := ""
## ... with which `pass_clear` rule...
var _avoided_clear: Callable
## ... and the answer: `{ key, holes, views }`.
var _avoided_set := {}


## Hand in the house: its doorways and rooms. Forgets the views laid out when they changed.
func set_house(openings: Array, rooms: Array) -> void:
	if openings == _openings and rooms == _rooms:
		return
	_openings = openings
	_rooms = rooms
	_views.clear()
	_avoided_frame = -1


## The stable id of doorway `o` ("door_<x>_<y>", its rounded world position): what the snapshot's
## options, the behaviour and the radio call it.
static func opening_id(o: Dictionary) -> String:
	var p: Vector2 = o["pos"]
	return "door_%d_%d" % [roundi(p.x), roundi(p.y)]


## The unit normal pointing into `rect` from the edge door `pos` lies on (the nearest edge). Also
## read, through `AgentEntry.normal_into`, by the entry geometry and the squad (`ai/team/squad.gd`),
## which tells which side of a doorway's wall a leader clicked.
static func normal_into(rect: Rect2, pos: Vector2) -> Vector2:
	var edges := [
		[absf(pos.x - rect.position.x), Vector2.RIGHT],
		[absf(pos.x - rect.end.x), Vector2.LEFT],
		[absf(pos.y - rect.position.y), Vector2.DOWN],
		[absf(pos.y - rect.end.y), Vector2.UP],
	]
	edges.sort_custom(func(a, b): return a[0] < b[0])
	return edges[0][1]


## The house's doorway whose `opening_id` is `id`, or `{}`.
func _opening(id: String) -> Dictionary:
	for o in _openings:
		if opening_id(o) == id:
			return o
	return {}


## The rect of room `key`, or an empty Rect2.
func _room_rect(key: String) -> Rect2:
	return HouseRooms.by_key(_rooms, key).get("rect", Rect2())


## The first doorway on a walk that leads into a room the NPC has not cleared: the polyline from
## `from_pos` through the waypoints of `path` from `from_idx` on, as far as `max_dist` px of
## walking. A doorway counts when a step of the walk crosses its wall plane within the doorway's
## width, heading into a room that is not the one the NPC is in and that `is_cleared` (a Callable on
## the room key) says is not cleared. The walk's last step is extended by a body's length, so a
## destination that is the doorway itself crosses it. `{ opening, into, dist }` (`dist` = px of
## walking to it), or {}. Used by the behaviour's entry guard (E9): any walk, not only the ENTER
## order, goes in by the entry.
func threshold_ahead(
	path: PackedVector2Array,
	from_idx: int,
	from_pos: Vector2,
	is_cleared: Callable,
	max_dist: float,
) -> Dictionary:
	var pts := _walk_points(path, from_idx, from_pos)
	if pts.size() < 2:
		return {}
	var tail: Vector2 = (pts[-1] as Vector2) - (pts[-2] as Vector2)
	if tail.length() > 0.001:
		pts.append((pts[-1] as Vector2) + tail.normalized() * THRESHOLD_EXTEND)
	var here := HouseRooms.key_at(from_pos, _rooms)
	var walked := 0.0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var best := _step_threshold(a, b, here, is_cleared, walked)
		if not best.is_empty():
			return best if best["dist"] <= max_dist else {}
		walked += a.distance_to(b)
		if walked > max_dist:
			break
	return {}


## The walk from `from_pos` through the waypoints of `path` from `from_idx` on, as a polyline.
static func _walk_points(path: PackedVector2Array, from_idx: int, from_pos: Vector2) -> Array:
	var pts: Array = [from_pos]
	for i in range(maxi(from_idx, 0), path.size()):
		pts.append(path[i])
	return pts


## The nearest doorway the step `a` -> `b` of a walk crosses into a room that is not `here` and that
## `is_cleared` says is not cleared: `{ opening, into, dist }` (`dist` = `walked`, the px of walking
## before the step, plus the step's own to the crossing), or {}.
func _step_threshold(
	a: Vector2,
	b: Vector2,
	here: String,
	is_cleared: Callable,
	walked: float,
) -> Dictionary:
	var best := {}
	for o in _openings:
		for key in o.get("rooms", []):
			var into := str(key)
			if into == here or is_cleared.call(into):
				continue
			var step := _crossing(o, into, a, b)
			if step == INF:
				continue
			var d := walked + step
			if best.is_empty() or d < best["dist"]:
				best = { "opening": opening_id(o), "into": into, "dist": d }
	return best


## The px from `a` to where the step `a` -> `b` crosses the wall plane of doorway `o` from outside
## room `into` to its far side within the doorway's width, or INF when it does not.
func _crossing(o: Dictionary, into: String, a: Vector2, b: Vector2) -> float:
	var room := _room_rect(into)
	if room.size == Vector2.ZERO:
		return INF
	var pos: Vector2 = o["pos"]
	var inward := normal_into(room, pos)
	var sa := (a - pos).dot(inward)
	var sb := (b - pos).dot(inward)
	if sa >= 0.0 or sb < 0.0:
		return INF  # Not a step from outside the wall plane to its far side.
	var q := a + (b - a) * (-sa / (sb - sa))
	if (absf((q - pos).dot(inward.orthogonal()))
			> float(o.get("width", 80.0)) * 0.5 + THRESHOLD_SLACK):
		return INF
	return a.distance_to(q)


## The first doorway view a walk goes into without entering the rooms it belongs to (E15 / E18): the
## walk comes from outside one of the `avoided` views into it, within `max_dist` px of walking. Not
## the view of a doorway of a room the walk goes into (by any of its doors: that is an entry,
## `threshold_ahead`'s, and it clears the room and covers its doorways), nor of the room the NPC
## stands in. `{ opening, into, dist }` (`dist` = px of walking until it is in the view), or {}. The
## view of any doorway counts, outside the house and at its exterior doors too. The views are those
## of `world`'s navigation map and physics space.
func passing_ahead(
	path: PackedVector2Array,
	from_idx: int,
	from_pos: Vector2,
	max_dist: float,
	world: World2D,
) -> Dictionary:
	var pts := _walk_points(path, from_idx, from_pos)
	if pts.size() < 2:
		return {}
	var best := {}
	for v in _crossed_views(
			pts,
			avoided(
				HouseRooms.key_at(from_pos, _rooms),
				world.navigation_map,
				world.direct_space_state,
			)["views"],
			max_dist,
	):
		if best.is_empty() or v["dist"] < best["dist"]:
			best = { "opening": v["id"], "into": v["into"], "dist": v["dist"] }
	return best


## The `views` the walk `pts` comes into from outside within `max_dist` px of walking, each with its
## `dist`; not those of a doorway of a room the walk goes into, but for the approach of entry
## `entering` (`"<opening id>><room key>"`): the room it is into (its approach never goes in by
## another way) and the view of the doorway it stacks at (never walked, though the walk goes through
## that doorway).
func _crossed_views(pts: Array, views: Array, max_dist: float, entering := "") -> Array:
	var entered := _entered_rooms(pts)
	var keep_out := entering.get_slice(">", 1) if entering != "" else ""
	var out: Array = []
	for v in views:
		var own: bool = "%s>%s" % [v["id"], v["into"]] == entering
		if not own and (v["joins"] as Array).any(func(k): return entered.has(k) and k != keep_out):
			continue
		var d := _entering_distance(pts, v["poly"], max_dist)
		if d < INF:
			out.append({ "id": v["id"], "into": v["into"], "poly": v["poly"], "dist": d })
	return out


## The route from `from` to `to` as the NPC walks it (E18), on the world navigation map `map`: the
## plain route, unless it goes into the view of a doorway into a room not clear for passing
## (`avoided`) and a route that keeps out of every such view reaches `to` within `door_avoid_ratio`
## x the plain length + `door_avoid_slack`: that one, on the avoid map.
## `{ map, path, len, plain_len, doors, pending, views }`: `map` the map the route is on, `doors`
## whether it is the door-avoiding one, `pending` that the plain route goes into a view and the
## avoid map is still being baked (the NPC walks the plain route meanwhile and asks again), `views`
## the views the plain route goes into. `entering` (`"<opening id>><room key>"`) is the entry the
## walk is the approach of: it keeps out of that room (the views of its doorways count though the
## plain route goes in, and its floor is carved too when a way round would go in: `_with_room`) and
## out of the view of the doorway it stacks at, from inside the room too (`avoided`). With no way
## round every view in the cap, it goes round those at least (`_entering_set`); on an ordered
## approach (`ordered_approach`) that way is taken however long it is.
func walk_route(
	from: Vector2,
	to: Vector2,
	map: RID,
	space: PhysicsDirectSpaceState2D,
	entering := "",
) -> Dictionary:
	var plain := NavBuilder.route(map, from, to)
	var plain_len := NavBuilder.path_length(plain)
	var out := {
		"map": map,
		"path": plain,
		"len": plain_len,
		"plain_len": plain_len,
		"doors": false,
		"pending": false,
		"views": [],
	}
	if not avoid_views or not NavBuilder.ready(map):
		return out
	var here := HouseRooms.key_at(from, _rooms)
	var avoid_set := _left_from(avoided(here, map, space, entering), from)
	var crossed := _crossed_views([from] + Array(plain), avoid_set["views"], INF, entering)
	out["views"] = crossed
	var keep_out := (entering.get_slice(">", 1)
			if entering != "" and entering.get_slice(">", 1) != here
			else "")
	if (crossed.is_empty()
			and not (keep_out != "" and _entered_rooms([from] + Array(plain)).has(keep_out))):
		return out
	var sets: Array = [avoid_set]
	if entering != "":
		# No way round them all: round the room being entered and its doorway's view at least.
		sets.append(_entering_set(avoid_set, entering))
	for i in sets.size():
		# An ordered approach takes the way round the entry's own set however long it is.
		var cap := (INF
				if ordered_approach and i == 1
				else door_avoid_ratio * plain_len + door_avoid_slack)
		var way := _round(from, to, map, sets[i], cap)
		if (keep_out != ""
				and way.has("path")
				and _entered_rooms([from] + Array(way["path"])).has(keep_out)):
			# The room being entered is kept out of itself, not only by its doorways' views: a walk
			# that starts in one of those views (dropped from the set, `_left_from`) would otherwise
			# go through the room from there. Its floor is carved (`_with_room`) only for a way
			# round that goes in, so the map with it carved is asked for, and kept, only while an
			# approach needs it.
			way = _round(from, to, map, _with_room(sets[i], keep_out), cap)
		if bool(way.get("pending", false)):
			out["pending"] = true
			return out
		if not way.is_empty():
			out.merge(way, true)
			return out
	return out  # No way round: the walk goes the plain way and the guard secures what it crosses.


## `views_set` (`avoided`) without the views point `from` stands in: a walk that starts in a
## doorway's view leaves it by the way it goes (a map with that view carved would have it start in a
## hole, cut off from where it goes).
func _left_from(views_set: Dictionary, from: Vector2) -> Dictionary:
	var kept: Array = (views_set["views"] as Array).filter(
		func(v): return not Geometry2D.is_point_in_polygon(from, v["poly"]),
	)
	if kept.size() == (views_set["views"] as Array).size():
		return views_set
	var keys: Array = kept.map(func(v): return "%s>%s" % [v["id"], v["into"]])
	return {
		"key": "%d:%s" % [int(door_view_depth), ",".join(keys)],
		"holes": kept.map(func(v): return v["poly"]),
		"views": kept,
	}


## The way from `from` to `to` round the views of `views_set` (`avoided`), on its avoid map:
## `{ map, path, len, doors: true }` when it reaches `to` (in a walk of `cap` px at most: `len` the
## whole walk, from `from` onto the route and from its end on to `to`), `{ pending: true }` while
## the map is being baked, else {}.
func _round(
	from: Vector2,
	to: Vector2,
	map: RID,
	views_set: Dictionary,
	cap: float,
) -> Dictionary:
	var avoid := NavBuilder.avoid_map(
		NavBuilder.planning_region(map),
		views_set["key"],
		views_set["holes"],
	)
	if not avoid.is_valid() or not NavBuilder.ready(avoid):
		return { "pending": true }
	var path := NavBuilder.route(avoid, from, to)
	if path.is_empty() or path[path.size() - 1].distance_to(NavBuilder.snap(map, to)) > AVOID_REACH:
		return {}
	# The walk's length: the route, and the steps onto it and on from its end to `to` (a goal by a
	# view's edge lies off the avoid map, and the walk's last stretch is on the plain map,
	# `Locomotion._last_stretch`), so it is not read as shorter than the plain way it goes round.
	var length := (from.distance_to(path[0]) + NavBuilder.path_length(path)
			+ path[path.size() - 1].distance_to(to))
	if length > cap:
		return {}
	return { "map": avoid, "path": path, "len": length, "doors": true }


## `views_set` (`avoided`) with room `key`'s floor carved out as well (its rect), for an approach
## that keeps out of the room it is entering.
func _with_room(views_set: Dictionary, key: String) -> Dictionary:
	var r := _room_rect(key)
	if r.size == Vector2.ZERO:
		return views_set
	var room := PackedVector2Array([
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
	])
	return {
		"key": "%s|%s" % [views_set["key"], key],
		"holes": (views_set["holes"] as Array) + [room],
		"views": views_set["views"],
	}


## Of the views `views_set` (`avoided` for a walk that is the approach of entry `entering`), the
## view of the doorway it stacks at: with the room being entered carved too (`_with_room`,
## `walk_route`), what keeps the approach out of that room and off its doorway's front when a way
## round every view does not exist (a room not cleared on the way is then gone into by the guard's
## entry, D4). The views of that room's other doorways are not in it: a walk shut in by one (a
## cleared room's end beyond it) crosses it rather than the room.
func _entering_set(views_set: Dictionary, entering: String) -> Dictionary:
	var opening := entering.get_slice(">", 0)
	var into := entering.get_slice(">", 1)
	var keys: Array = []
	var holes: Array = []
	var views: Array = []
	for v: Dictionary in views_set["views"]:
		if v["into"] == into and v["id"] == opening:
			keys.append("%s>%s" % [v["id"], v["into"]])
			holes.append(v["poly"])
			views.append(v)
	return {
		"key": "%d:%s" % [int(door_view_depth), ",".join(keys)],
		"holes": holes,
		"views": views,
	}


## Whether the routes weighed from point `from` can be measured as they would be walked (E18): the
## avoid map for the doorway views from the room it is in exists. Asks for it, which starts its bake
## on the worker thread, so it is under way before a decision is. True when there is nothing to
## avoid (no views, no planning region, door avoidance off) and once the map answers.
func warm(from: Vector2, map: RID, space: PhysicsDirectSpaceState2D) -> bool:
	if not avoid_views or not NavBuilder.ready(map):
		return true
	var avoid_set := avoided(HouseRooms.key_at(from, _rooms), map, space)
	var region := NavBuilder.planning_region(map)
	if avoid_set["views"].is_empty() or region == null:
		return true
	return NavBuilder.ready(NavBuilder.avoid_map(region, avoid_set["key"], avoid_set["holes"]))


## The views a walk from point `from` keeps out of, each `{ id, into, poly }` (see `avoided`).
func views_from(from: Vector2, map: RID, space: PhysicsDirectSpaceState2D) -> Array:
	return avoided(HouseRooms.key_at(from, _rooms), map, space)["views"]


## The doorway views a walk from room `here_key` ("" = outside) keeps out of: the view out of every
## doorway into a room that is not clear for passing (`pass_clear`), other than the room the NPC
## stands in. `{ key, holes, views }`: `key` names the set (for `NavBuilder.avoid_map`), `holes` the
## polygons, `views` each `{ id, into, poly, joins }` (`joins`: the keys of the rooms the doorway
## joins). Empty until the map is baked. With `entering` (`"<opening id>><room key>"`, the entry a
## walk is the approach of), that doorway's view into the room counts even from inside the room, and
## clear or not: the stack never walks its own doorway's view.
func avoided(
	here_key: String,
	map: RID,
	space: PhysicsDirectSpaceState2D,
	entering := "",
) -> Dictionary:
	var frame := Engine.get_physics_frames()
	if (frame == _avoided_frame
			and here_key == _avoided_here
			and entering == _avoided_entering
			and pass_clear == _avoided_clear):
		return _avoided_set
	var keys: Array = []
	var holes: Array = []
	var views: Array = []
	for o in _openings:
		for k in o.get("rooms", []):
			var into := str(k)
			var own := entering == "%s>%s" % [opening_id(o), into]
			if not own and (into == here_key or (pass_clear.is_valid() and pass_clear.call(into))):
				continue
			var poly := door_view(opening_id(o), into, map, space)
			if poly.is_empty():
				continue
			keys.append("%s>%s" % [opening_id(o), into])
			holes.append(poly)
			views.append({
				"id": opening_id(o),
				"into": into,
				"poly": poly,
				"joins": (o.get("rooms", []) as Array).map(func(j): return str(j)),
			})
	_avoided_set = {
		"key": "%d:%s" % [int(door_view_depth), ",".join(keys)],
		"holes": holes,
		"views": views,
	}
	_avoided_frame = frame
	_avoided_here = here_key
	_avoided_entering = entering
	_avoided_clear = pass_clear
	return _avoided_set


## The view out of doorway `id` seen from inside room `into` through it, as a polygon in world space
## (empty when either is unknown or the map is not baked): the area bounded by the rays from the
## room's two far corners through the opposite jambs, `door_view_depth` px long, and stopped at
## walls, and, for a doorway between two rooms, cut at the edge of the room in front of it. It is
## laid out once per doorway (walls do not move) from three points in the gap, the middle and each
## jamb, so what one of them sees past a wall's end counts.
func door_view(
	id: String,
	into: String,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> PackedVector2Array:
	var key := "%s>%s@%d" % [id, into, int(door_view_depth)]
	if _views.has(key):
		return _views[key]
	var opening := _opening(id)
	var room := HouseRooms.by_key(_rooms, into)
	if opening.is_empty() or room.is_empty() or space == null or not NavBuilder.ready(map):
		return PackedVector2Array()
	# A view lies in the room (or the open) in front of the doorway: it does not run on through the
	# next doorway into another room.
	var in_front := Rect2()
	for k in opening.get("rooms", []):
		if str(k) != into:
			in_front = _room_rect(str(k))
	var view := _build_view(opening, room["rect"], space)
	if in_front.size != Vector2.ZERO:
		var front_ring := PackedVector2Array([
			in_front.position,
			Vector2(in_front.end.x, in_front.position.y),
			in_front.end,
			Vector2(in_front.position.x, in_front.end.y),
		])
		var cut: Array = Geometry2D.intersect_polygons(view, front_ring)
		if not cut.is_empty():
			cut.sort_custom(func(a, b): return absf(_area(a)) > absf(_area(b)))
			view = cut[0]
	_views[key] = view
	return view


## The area of polygon `ring` (positive or negative by its winding).
func _area(ring: PackedVector2Array) -> float:
	var total := 0.0
	for i in ring.size():
		total += ring[i].cross(ring[(i + 1) % ring.size()])
	return total * 0.5


## The view of `opening` into the room `rect`: see `door_view`.
func _build_view(
	opening: Dictionary,
	rect: Rect2,
	space: PhysicsDirectSpaceState2D,
) -> PackedVector2Array:
	var pos: Vector2 = opening["pos"]
	var out := -normal_into(rect, pos)
	var along := out.orthogonal()
	var half := float(opening.get("width", 80.0)) * 0.5
	var jambs := [pos - along * half, pos + along * half]
	var boundary := _view_boundary(rect, pos, out, jambs)
	var merged: Array = []
	for apex in [pos, jambs[0] + along * 2.0, jambs[1] - along * 2.0]:
		var ring := _view_fan(space, apex + out * VIEW_APEX_OUT, jambs, boundary)
		if merged.is_empty():
			merged = [ring]
			continue
		var fused := Geometry2D.merge_polygons(merged[0], ring)
		var outer: Array = fused.filter(
			func(poly: PackedVector2Array) -> bool:
				return not Geometry2D.is_polygon_clockwise(poly)
		)
		if outer.size() == 1:
			merged = [outer[0]]
	return merged[0]


## The outline of a doorway view, from jamb to jamb (`jambs`, of the doorway at `pos` whose wall
## faces `out`, away from room `rect`) the long way round, sampled for the rays: each jamb is seen
## past by the far corner of the room on the other side of the door's axis, `door_view_depth` px
## out.
func _view_boundary(rect: Rect2, pos: Vector2, out: Vector2, jambs: Array) -> Array:
	var seen_by := _far_corners(rect, pos, out)
	var jamb_a: Vector2 = jambs[0]
	var jamb_b: Vector2 = jambs[1]
	var end_a := jamb_a + (jamb_a - (seen_by[0] as Vector2)).normalized() * door_view_depth
	var end_b := jamb_b + (jamb_b - (seen_by[1] as Vector2)).normalized() * door_view_depth
	var boundary: Array = []
	for i in range(1, VIEW_SIDE_RAYS + 1):
		boundary.append(jamb_a.lerp(end_a, float(i) / VIEW_SIDE_RAYS))
	for i in range(1, VIEW_FAR_RAYS):
		boundary.append(end_a.lerp(end_b, float(i) / VIEW_FAR_RAYS))
	for i in range(VIEW_SIDE_RAYS, 0, -1):
		boundary.append(jamb_b.lerp(end_b, float(i) / VIEW_SIDE_RAYS))
	return boundary


## The two corners of room `rect` farthest from the doorway at `pos` (whose wall faces `out`), as
## `[seeing jamb a, seeing jamb b]`: each jamb is seen past by the far corner on the other side of
## the door's axis.
static func _far_corners(rect: Rect2, pos: Vector2, out: Vector2) -> Array:
	var along := out.orthogonal()
	var corners := [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	corners.sort_custom(func(a, b): return (a - pos).dot(out) < (b - pos).dot(out))
	var far_a: Vector2 = corners[0]
	var far_b: Vector2 = corners[1]
	var for_a: Vector2 = far_a if (far_a - pos).dot(along) > (far_b - pos).dot(along) else far_b
	var for_b: Vector2 = far_b if for_a == far_a else far_a
	return [for_a, for_b]


## One fan of a doorway view: from `eye`, a ray to each point of `boundary`, stopped at the first
## wall, between the two `jambs`.
func _view_fan(
	space: PhysicsDirectSpaceState2D,
	eye: Vector2,
	jambs: Array,
	boundary: Array,
) -> PackedVector2Array:
	var ring := PackedVector2Array([jambs[0]])
	for target in boundary:
		var hit: Dictionary = vision.wall_hit(space, eye, target)
		ring.append(hit["position"] if not hit.is_empty() else target)
	ring.append(jambs[1])
	return ring


## The keys of the rooms the walk `pts` goes into, by any of their doorways.
func _entered_rooms(pts: Array) -> Dictionary:
	var entered := {}
	for o in _openings:
		for k in o.get("rooms", []):
			var key := str(k)
			if entered.has(key):
				continue
			if _enters_room(pts, o, key):
				entered[key] = true
	return entered


## Whether the walk `pts` goes into room `key` by doorway `o`.
func _enters_room(pts: Array, o: Dictionary, key: String) -> bool:
	var room := _room_rect(key)
	return (room.size != Vector2.ZERO
			and _walk_enters(
				pts,
				o["pos"],
				normal_into(room, o["pos"]),
				float(o.get("width", 80.0)),
			))


## The px of walking along the polyline `pts` until it comes into `poly` from outside it, or INF
## when it does not within `max_dist`. A walk that starts in the polygon has not come into it: its
## first stretch inside is not counted.
func _entering_distance(pts: Array, poly: PackedVector2Array, max_dist: float) -> float:
	var line := PackedVector2Array(pts)
	var inside: Array = Geometry2D.intersect_polyline_with_polygon(line, poly)
	var best := INF
	for piece in inside:
		var first: Vector2 = piece[0]
		if first.distance_to(pts[0]) < 0.5:
			continue
		var walked := 0.0
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			if first.distance_to(Geometry2D.get_closest_point_to_segment(first, a, b)) < 0.5:
				best = minf(best, walked + a.distance_to(first))
				break
			walked += a.distance_to(b)
	return best if best <= max_dist else INF


## Whether the walk `pts` crosses the wall plane of a doorway at `pos` (into the room that lies
## along `inward`) within its width: it goes in by it somewhere.
func _walk_enters(pts: Array, pos: Vector2, inward: Vector2, width: float) -> bool:
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var sa := (a - pos).dot(inward)
		var sb := (b - pos).dot(inward)
		if sa >= 0.0 or sb < 0.0:
			continue
		var q := a + (b - a) * (-sa / (sb - sa))
		if absf((q - pos).dot(inward.orthogonal())) <= width * 0.5 + THRESHOLD_SLACK:
			return true
	return false
