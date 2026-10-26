extends RefCounted
## AI PERCEPTION sub-domain — ENTRY GEOMETRY's slots, a part the entry geometry holds as `slots`:
## where a stack may stand and walk at a doorway (`docs/tactical-entry.md` E20 to E22): `lay`, which
## lays a way in's slots for `AgentEntry.geometry`, and `on_stack_side`. Built once by `AgentEntry`,
## it holds nothing of it: the geometry it reads is handed in at the call (`entry`), so no reference
## cycle forms. Where a helper would take more parameters than the style allows, the entry rides in
## the stack context it already takes (`c["entry"]`, set by `_stack_context`), which dies with the
## call.

## The entry geometry this part is one of, handed in at the call (never held: it holds the part).
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
## How far (px) past the jamb the first slot of a file stands.
const SLOT_JAMB := 18.0
## Where a stack may stand (`lay`, E20 to E22): a slot stays this far (px) inside its room's
## rect (half a wall and most of a body), within this far of where the navmesh snaps it, reached
## from this far out from the wall plane (ending within `SLOT_ROUTE_REACH`).
const SLOT_ROOM_INSET := 16.0
const SLOT_SNAP := 3.0
const SLOT_REACH_OUT := 60.0
const SLOT_ROUTE_REACH := 6.0
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

## Every way into a room through every doorway, framed (`_door_frames`).
var frames: Array = []


## Whether point `p` is ground a stack going in by `g` may walk on its way to a slot (E20): on the
## stack side of the doorway's wall, in the room the stack stands in (or out in the open), and with
## a body there clear of every other doorway's funnel (by `SLOT_BODY` past its jambs).
func on_stack_side(entry: AgentEntry, g: Dictionary, p: Vector2) -> bool:
	var c := {
		"id": g["id"], "pos": g["pos"], "out": g["out"], "along": g["along"],
		"half": float(g["width"]) * 0.5, "from": str(g.get("from", "")),
		"from_rect": g.get("from_room", Rect2()),
	}
	if not _in_stack_side(entry, c, p):
		return false
	for f: Dictionary in _door_frames(entry):
		var rel: Vector2 = p - (f["pos"] as Vector2)
		if (f["id"] != c["id"]
				and absf(rel.dot(f["along"])) < float(f["half"]) + AgentEntry.SLOT_BODY
				and absf(rel.dot(f["out"])) < StackClaim.FUNNEL_DEPTH):
			return false
	return true


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
func lay(
	entry: AgentEntry,
	g: Dictionary,
	opening: Dictionary,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> void:
	var from := _other_room(opening, str(g["into"]))
	var c := _stack_context(entry, g, from, map, space)
	var dead_end := from != "" and entry.room_doorways(from).size() <= 1
	var bands := { 1: _band(entry, c, 1, WALL_GRID), -1: _band(entry, c, -1, WALL_GRID) }
	g["wall_n"] = 0
	g["from"] = from
	# The room the stack stands in (a zero rect: the open, outside the house).
	g["from_room"] = c["from_rect"]
	if _has_wall_spot(entry, c, false):
		_lay_wall(entry, g, c, bands, from == "" or dead_end)
	elif _has_wall_spot(entry, c, true):
		_lay_views(entry, g, c, bands, from == "" or dead_end)
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


## What laying the stack of entry `g` reads (`lay`), the stack standing in room `from` (""
## for outside): `{ id, pos, out, along, half, from, from_rect, map, space, start, reach }`, `start`
## the navmesh point `SLOT_REACH_OUT` out from the wall plane its slots are reached from, `reach`
## the cache of `_reached`, `entry` the entry geometry, for the call (`_slot_ok`, `_overflow` and
## `_open_floor` read it there).
func _stack_context(
	entry: AgentEntry,
	g: Dictionary,
	from: String,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	return {
		"id": g["id"], "pos": g["pos"], "out": g["out"], "along": g["along"],
		"half": float(g["width"]) * 0.5, "from": from, "from_rect": entry._room_rect(from),
		"map": map, "space": space,
		"start": NavBuilder.snap(
			map,
			(g["pos"] as Vector2) + (g["out"] as Vector2) * SLOT_REACH_OUT,
		),
		"reach": {},
		"entry": entry,
	}


## Lay a `wall` stack on `g` (`lay`) from its wall bands `bands` (`_band`, per side): each
## side's file the most bodies its spots out of every other doorway's view hold (`_pack`), on the
## finer grid when that is short of a full stack, then the overflow (`_overflow`, `capped` for none
## past the open floor).
func _lay_wall(
	entry: AgentEntry,
	g: Dictionary,
	c: Dictionary,
	bands: Dictionary,
	capped: bool,
) -> void:
	var files := {}
	for s in [1, -1]:
		files[s] = _pack(entry, (bands[s] as Array).filter(func(x): return x["views"] == 0))
	if (files[1] as Array).size() + (files[-1] as Array).size() < AgentEntry.MAX_SLOTS:
		for s in [1, -1]:  # Short of a full stack: the whole wall, on the finer grid.
			files[s] = _pack(entry, _band(entry, c, s, AgentEntry.SLOT_STEP).filter(
				func(x): return x["views"] == 0,
			))
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
	g["wall_n"] = mini(AgentEntry.MAX_SLOTS, laid.size())
	if row1[1] != row1[-1]:
		g["side"] = 1 if row1[1] > row1[-1] else -1
	# A short wall's overflow: the same room's open floor, then the tail; none outdoors or from a
	# room with no other doorway.
	_overflow(g, c, laid, capped, true)


## Lay a `views` stack on `g` (`lay`) from its wall bands `bands`: the layouts of the spots
## seen from the fewest other doorways (`_views_lays`, on the finer grid when short of a full
## stack), the slots of a full stack from the side `g` stacks on, then the overflow past them.
func _lay_views(
	entry: AgentEntry,
	g: Dictionary,
	c: Dictionary,
	bands: Dictionary,
	capped: bool,
) -> void:
	var lays := _views_lays(entry, bands)
	# Short of a full stack: the whole wall, on the finer grid.
	if (lays[1][AgentEntry.MAX_SLOTS - 1] as Array).size() < AgentEntry.MAX_SLOTS:
		lays = _views_lays(
			entry,
			{
				1: _band(entry, c, 1, AgentEntry.SLOT_STEP),
				-1: _band(entry, c, -1, AgentEntry.SLOT_STEP),
			},
		)
	g["kind"] = "views"
	g["views_lays"] = lays
	var layout := AgentEntry.views_layout(
		g,
		AgentEntry.MAX_SLOTS,
		int(g["side"]) if int(g["side"]) != 0 else 1,
	)
	g["slots"] = {
		1: layout.filter(func(x): return x["side"] == 1).map(func(x): return x["point"]),
		-1: layout.filter(func(x): return x["side"] == -1).map(func(x): return x["point"]),
	}
	g["wall_n"] = layout.size()
	# Past what the fewest-seen spots hold, the same chain as a short wall's (rule 6).
	_overflow(
		g,
		c,
		(lays[1][AgentEntry.MAX_SLOTS - 1] as Array).map(func(x): return x["point"]),
		capped,
		true,
	)


## Lay an `open_floor` stack on `g` (`lay`), a `dead_end` one when `dead_end`: no wall slots,
## its slots the overflow's (`seq`), each on the side of the door it lies on.
func _lay_open(g: Dictionary, c: Dictionary, dead_end: bool) -> void:
	g["kind"] = "dead_end" if dead_end else "open_floor"
	_overflow(g, c, [], dead_end, false)
	var seq: Array = g["seq"]
	var point_of := func(x): return x["point"]
	g["slots"] = {
		1: seq.filter(func(x): return AgentEntry.side_of(g, x["point"]) == 1).map(point_of),
		-1: seq.filter(func(x): return AgentEntry.side_of(g, x["point"]) == -1).map(point_of),
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
	var entry: AgentEntry = c["entry"]
	var wanted := AgentEntry.MAX_SLOTS - int(g["wall_n"])
	var open_slots: Array = (_open_floor(c, capped or strict, laid, wanted, strict)
			if wanted > 0
			else [])
	var seq: Array = open_slots.map(func(p): return { "point": p, "row": 1 })
	g["tail_from"] = int(g["wall_n"]) + seq.size() + 1
	if not capped and wanted > open_slots.size():
		seq.append_array(_tail_spots(entry, c, laid + open_slots).map(
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
func _has_wall_spot(entry: AgentEntry, c: Dictionary, with_views: bool) -> bool:
	for s in [1, -1]:
		if _has_wall_spot_on(entry, c, s, with_views):
			return true
	return false


## `_has_wall_spot` on side `s` (1 / -1 along the wall) alone: walked from `SLOT_JAMB` past the jamb
## in `SLOT_STEP`s to the wall's end.
func _has_wall_spot_on(entry: AgentEntry, c: Dictionary, s: int, with_views: bool) -> bool:
	var pos: Vector2 = c["pos"]
	var out: Vector2 = c["out"]
	var along: Vector2 = (c["along"] as Vector2) * s
	var reach := OUTDOOR_REACH
	if c["from"] != "":
		reach = _edge_along(
			c["from_rect"],
			pos + out * entry.wall_standoff,
			along,
		) - SLOT_ROOM_INSET
	var lateral: float = c["half"] + SLOT_JAMB
	while lateral <= reach:
		if _in_other_funnel(entry, c, pos + out * entry.wall_standoff + along * lateral):
			break  # The wall's end: another doorway's funnel.
		if _wall_spot_at(c, along, lateral, with_views):
			return true
		lateral += AgentEntry.SLOT_STEP
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


## One side's wall band (`s`, 1 / -1 along the wall) of the stack of `c` (`lay`): the points
## of a `step` px grid beside the door, from a body past the jamb along the wall to the stack side
## room's corner (outdoors `OUTDOOR_REACH`), and `SLOT_OUT_MIN` to `SLOT_OUT_MAX` px out from the
## wall plane, within `SLOT_SNAP` of the navmesh, where a body may stand bar the other doorways'
## views (`_slot_ok`): each `{ point, row, lat, off, views }` (row 1 within `ROW1_DEPTH` of the wall
## plane; `off` how far from the wall standoff; `views` how many other doorways see it,
## `_views_on`).
func _band(entry: AgentEntry, c: Dictionary, s: int, step: float) -> Array:
	var pos: Vector2 = c["pos"]
	var out: Vector2 = c["out"]
	var along: Vector2 = (c["along"] as Vector2) * s
	var reach := OUTDOOR_REACH
	if c["from"] != "":
		reach = _edge_along(c["from_rect"], pos, along)
	var band: Array = []
	var lateral: float = c["half"] + AgentEntry.SLOT_BODY
	while lateral <= reach:
		var o := SLOT_OUT_MIN
		while o <= SLOT_OUT_MAX:
			var p := pos + out * o + along * lateral
			if (NavBuilder.snap(c["map"], p).distance_to(p) <= SLOT_SNAP
					and _slot_ok(c, p, true, false)):
				band.append({
					"point": p, "row": 1 if o <= ROW1_DEPTH else 2, "lat": lateral,
					"off": absf(o - entry.wall_standoff), "views": _views_on(entry, c, p),
				})
			o += step
		lateral += step
	return band


## The file of one side of the stack of `c` from its wall band's points `band` (`_band`): the most
## bodies (at most `MAX_SLOTS`) they hold `stack_spacing` apart, found by a full search
## (`_most_spaced`) over them taken in order of preference (against the wall first, nearest the
## door, nearest the wall standoff), so among the layouts holding the most, the one nearest the door
## against the wall. Each `{ point, row }`, row 1 nearest the door first, then row 2.
func _pack(entry: AgentEntry, band: Array) -> Array:
	var cands := band.duplicate()
	cands.sort_custom(func(a, b):
		if a["row"] != b["row"]:
			return a["row"] < b["row"]
		if a["lat"] != b["lat"]:
			return a["lat"] < b["lat"]
		return a["off"] < b["off"])
	var picks: Array = _most_spaced(
		entry,
		cands.map(func(x): return x["point"]),
		AgentEntry.MAX_SLOTS,
	).map(
		func(i): return cands[i],
	)
	picks.sort_custom(
		func(a, b): return a["row"] < b["row"] if a["row"] != b["row"] else a["lat"] < b["lat"],
	)
	return picks.map(func(x): return { "point": x["point"], "row": x["row"] })


## The layouts of a `views` way in (`lay`) from its wall band's points `bands` (`_band`, per
## side): for each first side (1 / -1), the slots of a stack of 1 to `MAX_SLOTS`
## (`[count - 1] -> [{ point, row, side, lat }]`). Of the spots beside the door, those seen from the
## fewest other doorways that hold the stack: the least number of doorways for which the spots seen
## from no more than that hold it (`_most_spaced` over them taken against the wall first, then a
## step out, the first side's file before the other's, each nearest the door first), the first
## `count` of them in that order; the most there are when even every spot does not hold it.
func _views_lays(entry: AgentEntry, bands: Dictionary) -> Dictionary:
	var spots := _view_spots(bands)
	var levels := _view_levels(spots)
	var lays := {}
	for first in [1, -1]:
		lays[first] = _lays_by_count(_held_by_level(entry, _lay_order(spots, first), levels))
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
func _held_by_level(entry: AgentEntry, order: Array, levels: Array) -> Array:
	var held: Array = []  # Per level, the most its spots hold.
	for v: int in levels:
		var level: Array = order.filter(func(x): return int(x["views"]) <= v)
		var points: Array = level.map(func(x): return x["point"])
		held.append(_most_spaced(entry, points, AgentEntry.MAX_SLOTS).map(
			func(i): return level[i],
		))
		if (held[-1] as Array).size() >= AgentEntry.MAX_SLOTS:
			break
	return held


## The slots of a stack of each size, 1 to `MAX_SLOTS` (`[count - 1] -> [{ point, row, side, lat
## }]`), from the picks per level `held` (`_held_by_level`): the first `count` of the fewest-seen
## level's picks that hold `count`, else of the last level's.
func _lays_by_count(held: Array) -> Array:
	var as_spot := func(x):
		return { "point": x["point"], "row": x["row"], "side": x["side"], "lat": x["lat"] }
	var per: Array = []
	for count in range(1, AgentEntry.MAX_SLOTS + 1):
		var layout: Array = held[-1] if not held.is_empty() else []
		for picks: Array in held:
			if picks.size() >= count:
				layout = picks
				break
		per.append(layout.slice(0, count).map(as_spot))
	return per


## Spots too few for a full stack in `lays` (`_views_lays`, per first side): every stack that takes
## them all takes the same ones whichever side it starts on (the overflow stands clear of them),
## that side's file first.
func _share_full(lays: Dictionary) -> void:
	var full: Array = lays[1][AgentEntry.MAX_SLOTS - 1]
	for count in range(
		maxi(full.size(), 1),
		AgentEntry.MAX_SLOTS + 1 if full.size() < AgentEntry.MAX_SLOTS else 0,
	):
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
func _row1_outs(entry: AgentEntry) -> Array:
	var outs := [entry.wall_standoff, entry.wall_standoff - 4.0, entry.wall_standoff + 4.0,
		entry.wall_standoff - 8.0, entry.wall_standoff + 8.0, entry.wall_standoff + 12.0,
		entry.wall_standoff + 16.0]
	return outs.filter(func(o): return o >= ROW1_MIN and o <= ROW1_MAX)


## Whether a body of the stack of `c` may stand at navmesh point `p`: in the stack side's room (or
## outdoors, outside every room and out from the wall), out of every other doorway's funnel and
## (unless `with_views`) view, and reached from the stack side by a route that does not go through
## the doorway (`routed`: false leaves the route to the caller). `open` (the open-floor fallback):
## off the door's axis by a body and out of its funnel; else beside the door, clear of its opening.
func _slot_ok(c: Dictionary, p: Vector2, with_views: bool, open: bool, routed := true) -> bool:
	var entry: AgentEntry = c["entry"]
	var rel: Vector2 = p - (c["pos"] as Vector2)
	var lateral := absf(rel.dot(c["along"]))
	var outward := rel.dot(c["out"])
	var on_axis_or_funnel: bool = (
		lateral < AgentEntry.SLOT_BODY
		or (lateral < c["half"] and absf(outward) < StackClaim.FUNNEL_DEPTH)
	)
	if open and on_axis_or_funnel:
		return false
	if not open and lateral < c["half"] + AgentEntry.SLOT_BODY:
		return false
	if (not _in_stack_side(entry, c, p)
			or _in_other_funnel(entry, c, p)
			or (not with_views and _views_on(entry, c, p) > 0)):
		return false
	return not routed or _reached(c, p)


## Whether `p` lies on the stack side of `c`: inside its room's walls (`SLOT_ROOM_INSET`), or for an
## exterior door outside every room of the house and out from the doorway's wall plane.
func _in_stack_side(entry: AgentEntry, c: Dictionary, p: Vector2) -> bool:
	if c["from"] != "":
		return (c["from_rect"] as Rect2).grow(-SLOT_ROOM_INSET).has_point(p)
	if (p - (c["pos"] as Vector2)).dot(c["out"]) < SLOT_ROOM_INSET:
		return false
	return not entry._rooms.any(
		func(r): return (r["rect"] as Rect2).grow(SLOT_ROOM_INSET).has_point(p),
	)


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
func _in_other_funnel(entry: AgentEntry, c: Dictionary, p: Vector2) -> bool:
	for f: Dictionary in _door_frames(entry):
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
func _views_on(entry: AgentEntry, c: Dictionary, p: Vector2) -> int:
	var ids := {}
	for f: Dictionary in _door_frames(entry):
		if f["id"] == c["id"] or ids.has(f["id"]):
			continue
		var pos: Vector2 = f["pos"]
		if ((p - pos).dot(f["out"]) <= 0.0
				or not Geometry2D.is_point_in_polygon(p, f["quad"])
				or _edge_gap(f["quad"], p) < VIEW_MARGIN):
			continue
		var gap: Vector2 = (f["along"] as Vector2) * (float(f["half"]) - 4.0)
		for target: Vector2 in [pos, pos - gap, pos + gap]:
			if entry.vision.wall_hit(c["space"], p, target).is_empty():
				ids[f["id"]] = true
				break
	return ids.size()


## Every way into a room through every doorway of the house, as a frame:
## `{ id, pos, half, out (away from the room), along, quad (the view out of it, unclipped) }`.
## Worked out once per house.
func _door_frames(entry: AgentEntry) -> Array:
	if not frames.is_empty() or entry._openings.is_empty():
		return frames
	for o in entry._openings:
		for k in o.get("rooms", []):
			var rect := entry._room_rect(str(k))
			if rect.size == Vector2.ZERO:
				continue
			frames.append(_door_frame(entry, o, rect))
	return frames


## The frame of the way through doorway `o` into room `rect` (`_door_frames`).
func _door_frame(entry: AgentEntry, o: Dictionary, rect: Rect2) -> Dictionary:
	var pos: Vector2 = o["pos"]
	var out := -AgentEntry.normal_into(rect, pos)
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
		jamb_a, jamb_a + (jamb_a - for_a).normalized() * entry.views.door_view_depth,
		jamb_b + (jamb_b - for_b).normalized() * entry.views.door_view_depth, jamb_b,
	])
	return {
		"id": AgentEntry.opening_id(o),
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
	var entry: AgentEntry = c["entry"]
	var picks := _floor_picks(entry, _floor_cands(entry, c, OPEN_GRID, taken, strict), exact, most)
	if exact and picks.size() < most:
		picks = _floor_picks(
			entry,
			_floor_cands(entry, c, OPEN_GRID_FINE, taken, strict),
			exact,
			most,
		)
	return picks


## The points of `_open_floor`'s grid of `step` px that may hold a slot (`taken` and `strict` as
## there), nearest the door's wall first and then farthest off its axis.
func _floor_cands(
	entry: AgentEntry,
	c: Dictionary,
	step: float,
	taken: Array,
	strict: bool,
) -> Array:
	var pos: Vector2 = c["pos"]
	var cands: Array = []
	for p: Vector2 in _floor_grid(c, step):
		var spaced := func(q): return (q as Vector2).distance_to(p) >= entry.stack_spacing
		if (NavBuilder.snap(c["map"], p).distance_to(p) <= SLOT_SNAP
				and not (strict and _in_band(entry, c, p))
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
func _floor_picks(entry: AgentEntry, cands: Array, exact: bool, most: int) -> Array:
	if exact:
		return _most_spaced(entry, cands, most).map(func(i): return cands[i])
	var picks: Array = []
	for p: Vector2 in cands:
		if (picks.size() < most
				and picks.all(
					func(q): return (q as Vector2).distance_to(p) >= entry.stack_spacing,
				)):
			picks.append(p)
	return picks


## Whether `p` lies in the wall band of `c` (`_band`): beside the door (a body past the jamb along
## the wall), `SLOT_OUT_MIN` to `SLOT_OUT_MAX` px out from the wall plane, on the stack side.
func _in_band(entry: AgentEntry, c: Dictionary, p: Vector2) -> bool:
	var rel: Vector2 = p - (c["pos"] as Vector2)
	var o := rel.dot(c["out"])
	return (absf(rel.dot(c["along"])) >= float(c["half"]) + AgentEntry.SLOT_BODY
			and o >= SLOT_OUT_MIN
			and o <= SLOT_OUT_MAX
			and _in_stack_side(entry, c, p))


## The indices of the most of `points` (at most `most`) each at least `stack_spacing` from the
## others: of the sets that large, the first in their order. An exact search (a Russian-doll
## search): from the last point back, `best[k]` is the most the points from `k` on hold (at most
## `most`), each found by asking whether the points after `k` free of it hold `best[k + 1]` more
## (`_holds`), which the counts already known bound tightly; then the first set in order of that
## many (`_holds` again, keeping it). Within `PACK_BUDGET` steps.
func _most_spaced(entry: AgentEntry, points: Array, most: int) -> Array:
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
				and _holds(
					entry,
					search,
					_free_after(entry, points, k, range(k + 1, n)),
					best[k + 1],
					[],
				)):
			best[k] = best[k + 1] + 1
	var chosen: Array = []
	_holds(entry, search, range(n), best[0], chosen)
	return chosen


## Whether the points `cands` (indices into the search's `points`, ascending) hold `need` each
## `stack_spacing` apart, bounded by its `best` (`_most_spaced`: the points from an index on hold no
## more than `best` of it) and spending its `budget`; the set found is added to `chosen` (an empty
## array to ask only).
func _holds(entry: AgentEntry, search: Dictionary, cands: Array, need: int, chosen: Array) -> bool:
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
		var after := _free_after(entry, search["points"], cands[i], cands.slice(i + 1))
		if _holds(entry, search, after, need - 1, chosen):
			return true
		chosen.resize(size)
	return false


## Of the indices `cands`, those whose points lie at least `stack_spacing` from point `k`.
func _free_after(entry: AgentEntry, points: Array, k: int, cands: Array) -> Array:
	var p: Vector2 = points[k]
	var sq := entry.stack_spacing * entry.stack_spacing
	return cands.filter(func(j): return p.distance_squared_to(points[j]) >= sq)


## Where the tail of the stack of `c` holds (E20's fallback, `open_floor`): in the room it came by
## (the stack side's room's other doorway nearest this one), against its wall beside that doorway,
## taking turns either side of it; once that wall is full, the nearest spots of that room to the
## doorway on a `OPEN_GRID` px grid. Within `TAIL_REACH` of it, off its axis by a body and out of
## its funnel, on the navmesh; never nearer `stack_spacing` to the `open_slots` or each other. At
## most `MAX_SLOTS`.
func _tail_spots(entry: AgentEntry, c: Dictionary, open_slots: Array) -> Array:
	var best := _tail_door(entry, c)
	if best.is_empty():
		return []
	var tc := _tail_context(entry, c, best)
	var out := _tail_wall_spots(entry, tc, open_slots)
	if out.size() < AgentEntry.MAX_SLOTS:
		_tail_floor_fill(entry, tc, open_slots, out)
	return out


## The frame of the doorway the tail of the stack of `c` holds by (`_tail_spots`): of the stack side
## room's other doorways, framed going into that room, the nearest this one. {} for none.
func _tail_door(entry: AgentEntry, c: Dictionary) -> Dictionary:
	var best := {}
	for f: Dictionary in _door_frames(entry):
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
func _tail_context(entry: AgentEntry, c: Dictionary, best: Dictionary) -> Dictionary:
	var beyond := _other_room(entry._opening(best["id"]), c["from"])
	return {
		"id": best["id"], "pos": best["pos"], "out": best["out"], "along": best["along"],
		"half": best["half"], "from": beyond, "from_rect": entry._room_rect(beyond),
		"map": c["map"], "space": c["space"], "reach": {},
	}


## The tail's spots against its doorway's wall (`tc`, `_tail_context`), taking turns either side of
## it, `stack_spacing` apart along the wall from `SLOT_JAMB` past the jamb: for each, the first of
## `_row1_outs` that is on the navmesh within `SLOT_SNAP`, within `TAIL_REACH` of the doorway, on
## its ground, and `stack_spacing` from `open_slots` and the spots before it. At most `MAX_SLOTS`.
func _tail_wall_spots(entry: AgentEntry, tc: Dictionary, open_slots: Array) -> Array:
	var out: Array = []
	for k in AgentEntry.MAX_SLOTS:
		var s := 1 if k % 2 == 0 else -1
		var lateral := float(tc["half"]) + SLOT_JAMB + entry.stack_spacing * floorf(k / 2.0)
		var p := _tail_wall_spot(entry, tc, s, lateral, open_slots + out)
		if p != Vector2.INF:
			out.append(p)
	return out


## The first tail spot `lateral` px along the wall on side `s` of the tail's doorway (`tc`) at one
## of `_row1_outs`, at least `stack_spacing` from every point of `near` (`_tail_wall_spots`), or
## INF.
func _tail_wall_spot(
	entry: AgentEntry,
	tc: Dictionary,
	s: int,
	lateral: float,
	near: Array,
) -> Vector2:
	var pos: Vector2 = tc["pos"]
	for o: float in _row1_outs(entry):
		var raw: Vector2 = (pos + (tc["out"] as Vector2) * o
				+ (tc["along"] as Vector2) * s * lateral)
		var p := NavBuilder.snap(tc["map"], raw)
		if (p.distance_to(raw) > SLOT_SNAP
				or p.distance_to(pos) > TAIL_REACH
				or not _in_stack_side(entry, tc, p)):
			continue
		if near.any(func(q): return (q as Vector2).distance_to(p) < entry.stack_spacing):
			continue
		return p
	return Vector2.INF


## Fill the tail spots `out` (`_tail_wall_spots`) up to `MAX_SLOTS` from the tail's floor nearest
## its doorway (`_tail_grid`), each `stack_spacing` from `open_slots` and the spots before it.
func _tail_floor_fill(entry: AgentEntry, tc: Dictionary, open_slots: Array, out: Array) -> void:
	for p: Vector2 in _tail_grid(entry, tc):
		if out.size() >= AgentEntry.MAX_SLOTS:
			break
		if not (open_slots + out).any(
				func(q): return (q as Vector2).distance_to(p) < entry.stack_spacing,
		):
			out.append(p)


## The points of an `OPEN_GRID` px grid round the tail's doorway (`tc`) where a tail member may
## stand (`_tail_floor_ok`), nearest the doorway first.
func _tail_grid(entry: AgentEntry, tc: Dictionary) -> Array:
	var pos: Vector2 = tc["pos"]
	var grid: Array = []
	var lat := -TAIL_REACH
	while lat <= TAIL_REACH:
		var o := SLOT_ROOM_INSET
		while o <= TAIL_REACH:
			var p: Vector2 = (pos + (tc["out"] as Vector2) * o + (tc["along"] as Vector2) * lat)
			if _tail_floor_ok(entry, tc, p, lat, o):
				grid.append(p)
			o += OPEN_GRID
		lat += OPEN_GRID
	grid.sort_custom(func(a, b): return a.distance_squared_to(pos) < b.distance_squared_to(pos))
	return grid


## Whether the tail may stand at grid point `p` (`lat` px along the wall, `o` out from it) of its
## doorway (`tc`): within `TAIL_REACH` of it, off its axis by a body and out of its funnel, on the
## navmesh within `SLOT_SNAP`, on its ground and out of every other doorway's funnel.
func _tail_floor_ok(entry: AgentEntry, tc: Dictionary, p: Vector2, lat: float, o: float) -> bool:
	return (p.distance_to(tc["pos"]) <= TAIL_REACH
			and absf(lat) >= AgentEntry.SLOT_BODY
			and (absf(lat) >= float(tc["half"]) or o >= StackClaim.FUNNEL_DEPTH)
			and NavBuilder.snap(tc["map"], p).distance_to(p) <= SLOT_SNAP
			and _in_stack_side(entry, tc, p)
			and not _in_other_funnel(entry, tc, p))


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
