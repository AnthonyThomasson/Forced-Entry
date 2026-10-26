extends RefCounted
## Shared helpers for the tests of where a stack's slots lie (`docs/tactical-entry.md` E20 to E22;
## not a test itself): `const SlotRules := preload("res://tests/_ai/slot_rules_probe.gd")`. The
## rules for one point, each `""` when it holds or a line naming the rule it breaks: in the stack's
## room, on the navmesh, reached from the stack side, clear of the other doorways, out of their
## funnels and views, clear of the carved furniture; whether a side has room for one; and rule 6's
## wall band, view count and tail spot. Judged from the house's own data and the test's own
## geometry, in a frame and a world of `slots_probe.gd`'s (`Slots.frame`, `Slots.world_of`).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")
## A slot on the navmesh is within this many px of where `NavBuilder.snap` puts it.
const SNAP_SLACK := 3.0
## A route that reaches a slot ends within this many px of it.
const REACH_SLACK := 6.0
## How far (px) out from the stack side's wall plane a route to a slot starts (snapped onto the
## navmesh): "from the stack side".
const START_OUT := 60.0
## A body on a slot keeps at least this far (px) from every carved furniture footprint (E22).
const FURNITURE_CLEAR := 10.0


## Whether `p` lies in the stack side of frame `f`: inside the stack side's room (by `ROOM_INSET`),
## or, for an exterior door, outside every room of the house and on the outer side of the doorway's
## wall plane. "" when it does, else why not.
static func in_stack_room(w: Dictionary, f: Dictionary, p: Vector2) -> String:
	if String(f["from"]) != "":
		var rect: Rect2 = f["from_rect"]
		if rect.grow(-Slots.ROOM_INSET).has_point(p):
			return ""
		var other := _room_at(w["rooms"], p)
		if other == String(f["from"]):
			return ("not inside the %s's walls (%.0f px from its rect's edge)"
					% [other, _rect_gap(rect, p)])
		return ("not in the %s (%s)"
				% [f["from"], ("in the " + other) if other != "" else "outside the house"])
	var indoors := _room_at(w["rooms"], p, Slots.ROOM_INSET)
	if indoors != "":
		return "an exterior door's slot inside the house (the %s)" % indoors
	if Entry.outward(f, p) < Slots.ROOM_INSET:
		return ("round the corner of the house (%.0f px out from the door's wall plane)"
				% Entry.outward(f, p))
	return ""


## The key of the room whose rect (grown by `grow`) holds `p`, or "".
static func _room_at(rooms: Array, p: Vector2, grow := 0.0) -> String:
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
		if other["id"] != f["id"] and _in_view(w, other, p):
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
static func _in_view(w: Dictionary, f: Dictionary, p: Vector2) -> bool:
	if Entry.outward(f, p) <= 0.0:
		return false
	var poly := View.polygon(f)
	if not Geometry2D.is_point_in_polygon(p, poly) or _edge_distance(poly, p) < View.EDGE_MARGIN:
		return false
	var pos: Vector2 = f["pos"]
	var along: Vector2 = f["along"]
	var half := float(f["width"]) * 0.5 - 4.0
	for target in [pos, pos - along * half, pos + along * half]:
		if _walls_clear(w["space"], p, target):
			return true
	return false


## Whether no wall (a static body) lies on the line from `a` to `b` in `space`; furniture and
## characters are looked past.
static func _walls_clear(space: PhysicsDirectSpaceState2D, a: Vector2, b: Vector2) -> bool:
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
	var reach := Slots.ROOM_FOR_ONE_REACH
	if String(f["from"]) != "":
		reach = ray_to_edge(f["from_rect"], pos + out * Slots.ROOM_FOR_ONE_OUT, along)
	var past := float(f["width"]) * 0.5 + Slots.ROOM_FOR_ONE_PAST
	while past <= reach:
		for o in [
			Slots.ROOM_FOR_ONE_OUT,
			Slots.ROOM_FOR_ONE_OUT - 6.0,
			Slots.ROOM_FOR_ONE_OUT + 8.0,
		]:
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
		past += Slots.ROOM_FOR_ONE_STEP
	return Vector2.INF


## Whether `p` lies in frame `f`'s wall band, where a `wall` way in's slots stand (as `point_faults`
## judges a wall slot): in the stack side, beside the door (half its width plus a body along the
## wall, either side) and against the wall or a step out from it (the first and the second file,
## `ROW1_MIN` to `ROW2_MAX` out). A slot of a short wall's stack outside it is one of the
## overflow's.
static func in_wall_band(w: Dictionary, f: Dictionary, p: Vector2) -> bool:
	var o := Entry.outward(f, p)
	return (absf(Entry.lateral(f, p)) >= float(f["width"]) * 0.5 + Slots.BESIDE
			and o >= Slots.ROW1_MIN
			and o <= Slots.ROW2_MAX
			and in_stack_room(w, f, p) == "")


## How many other doorways (by id, either framing) have `p` in their view.
static func view_count(w: Dictionary, f: Dictionary, p: Vector2) -> int:
	var ids := {}
	for other: Dictionary in w["frames"]:
		if other["id"] != f["id"] and _in_view(w, other, p):
			ids[other["id"]] = true
	return ids.size()


## "" when `p` is a tail spot of frame `f` (rule 6): in a room joined to the stack-side room by
## another doorway (the room the tail came by, or outside), within `TAIL_REACH` of that doorway, off
## its axis by a body and out of its funnel, on the navmesh and off furniture; else why not.
static func tail_fault(w: Dictionary, f: Dictionary, p: Vector2) -> String:
	var ways := Slots.ways_into_stack_room(w, f)
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
		if d > Slots.TAIL_REACH:
			why.append("%.0f px from the doorway" % d)
		if absf(Entry.lateral(fo, p)) < Slots.BODY:
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


## How far (px) from `p` along `dir` (an axis) to the edge of `rect`, less `ROOM_INSET`.
static func ray_to_edge(rect: Rect2, p: Vector2, dir: Vector2) -> float:
	var d := 0.0
	if dir.x > 0.5:
		d = rect.end.x - p.x
	elif dir.x < -0.5:
		d = p.x - rect.position.x
	elif dir.y > 0.5:
		d = rect.end.y - p.y
	else:
		d = p.y - rect.position.y
	return d - Slots.ROOM_INSET


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
