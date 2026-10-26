extends RefCounted
## Shared helpers for the tests of where a stack's slots lie (`docs/tactical-entry.md` E20 to E22;
## not a test itself): `const SlotCapacity := preload("res://tests/_ai/slot_capacity_probe.gd")`.
## Rule 6's ways in with no clear spot against the wall: which rule a way in's slots answer to
## (`way_kind`), what each holds (`dead_end_capacity`, `wall_capacity`, `views_capacity`,
## `open_floor_capacity`), the spots against the wall (`wall_spots`) and the fewest-views bar
## (`fewest_views_bar`), on the rules of `slot_rules_probe.gd`, the faults of
## `slot_faults_probe.gd` and the frame, world and spec numbers of `slots_probe.gd`.

const SlotFaults := preload("res://tests/_ai/slot_faults_probe.gd")
const SlotRules := preload("res://tests/_ai/slot_rules_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
## The step (px) of the grid of the test's own points a dead-end small room's capacity is counted on
## (rule 6's dead end).
const CAPACITY_GRID := 4.0


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
	if SlotRules.side_has_room(w, f, 1) or SlotRules.side_has_room(w, f, -1):
		return "wall"
	if (SlotRules.room_for_one(w, f, 1, true) != Vector2.INF
			or SlotRules.room_for_one(w, f, -1, true) != Vector2.INF):
		return "views"
	if String(f["from"]) != "" and Slots.ways_into_stack_room(w, f).is_empty():
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
	var rect: Rect2 = (f["from_rect"] as Rect2).grow(-Slots.ROOM_INSET)
	var pts := PackedVector2Array()
	var y := rect.position.y
	while y <= rect.end.y:
		var x := rect.position.x
		while x <= rect.end.x:
			var p := Vector2(x, y)
			if SlotFaults.point_faults(w, f, p, cache, { "kind": "dead_end" }).is_empty():
				pts.append(p)
			x += CAPACITY_GRID
		y += CAPACITY_GRID
	var all := PackedInt32Array()
	for i in pts.size():
		all.append(i)
	var best: Array = []
	for need in range(1, Slots.MAX_STACK + 1):
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
	var sq := Slots.STACK_SPACING * Slots.STACK_SPACING
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
	if lo.distance_to(hi) < Slots.STACK_SPACING:
		return []
	if hi_x.x - lo_x.x >= Slots.STACK_SPACING:
		return [lo_x, hi_x]
	if hi_y.y - lo_y.y >= Slots.STACK_SPACING:
		return [lo_y, hi_y]
	var sq := Slots.STACK_SPACING * Slots.STACK_SPACING
	for i in cands.size():
		for j in range(i + 1, cands.size()):
			if pts[cands[i]].distance_squared_to(pts[cands[j]]) >= sq:
				return [pts[cands[i]], pts[cands[j]]]
	return []


## How many members the wall band of a `wall` way in (`way_kind`) holds, both sides and the second
## file counted, by the test's own count: the most of its valid points (`point_faults` with kind
## `wall` empty), pairwise at least `STACK_SPACING` apart, searched exhaustively up to `MAX_STACK`
## (`_packing`). The points are a `CAPACITY_GRID` px grid over the band, laid from the jamb's
## clearance out along the wall to the stack side's room's edge (outdoors, `ROOM_FOR_ONE_REACH`),
## plus `extra` (the way in's own slots that are valid wall points: a valid point is one wherever it
## lies). `{ count, points }`. With `rules` `{ kind: "views", bar }` (`views_capacity`), a valid
## point is one that keeps the `views` rules at that bar instead, and the result carries the `bar`.
static func wall_capacity(
	w: Dictionary,
	f: Dictionary,
	cache: Dictionary,
	extra: Array = [],
	rules: Dictionary = {},
) -> Dictionary:
	var pts := PackedVector2Array()
	for side in [1, -1]:
		pts.append_array(_band_grid(w, f, cache, rules, side))
	for p: Vector2 in extra:
		if (SlotRules.in_wall_band(w, f, p)
				and SlotFaults.point_faults(w, f, p, cache, rules).is_empty()
				and not pts.has(p)):
			pts.append(p)
	var found := _capacity(pts, Slots.MAX_STACK)
	if String(rules.get("kind", "wall")) == "views":
		found["bar"] = int(rules.get("bar", 0))
	return found


## `wall_capacity`'s grid on side `side` of frame `f`: its points in the wall band that keep
## `rules` (`point_faults`).
static func _band_grid(
		w: Dictionary, f: Dictionary, cache: Dictionary, rules: Dictionary, side: int
) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var pos: Vector2 = f["pos"]
	var out: Vector2 = f["out"]
	var along: Vector2 = (f["along"] as Vector2) * side
	var reach := Slots.ROOM_FOR_ONE_REACH
	if String(f["from"]) != "":
		reach = SlotRules.ray_to_edge(f["from_rect"], pos, along) + Slots.ROOM_INSET
	var lat := float(f["width"]) * 0.5 + Slots.BESIDE
	while lat <= reach:
		var o := Slots.ROW1_MIN
		while o <= Slots.ROW2_MAX:
			var p: Vector2 = pos + out * o + along * lat
			if SlotRules.in_wall_band(
				w,
				f,
				p,
			) and SlotFaults.point_faults(w, f, p, cache, rules).is_empty():
				pts.append(p)
			o += CAPACITY_GRID
		lat += CAPACITY_GRID
	return pts


## How many members the wall band of a `views` way in (`way_kind`) holds by its fewest-seen spots
## (the user's round-2 decision on rule 6), or {} when the test's own pick of the wall's spots
## (`_fewest_views_pick` of `spots`, `wall_spots`) already takes `MAX_STACK`: then no stack outgrows
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
	if _fewest_views_pick(spots, Slots.MAX_STACK).size() >= Slots.MAX_STACK:
		return {}
	return wall_capacity(
		w,
		f,
		cache,
		spots.map(func(s): return s["point"]) + extra,
		{ "kind": "views", "bar": fewest_views_bar(spots, Slots.MAX_STACK) },
	)


## The points of frame `f`'s stack side a short wall's overflow may stand on (the user's round-2
## decision on rule 6): a `CAPACITY_GRID` px grid over the stack side's room (by `ROOM_INSET`;
## outdoors, a box out from the door `ROOM_FOR_ONE_REACH` px along the wall either side and out from
## it), outside the wall band, each keeping the open-floor rules (`point_faults` with kind
## `overflow`). Cached per way in in `cache`.
static func _open_floor_points(
	w: Dictionary,
	f: Dictionary,
	cache: Dictionary,
) -> PackedVector2Array:
	var key := "open floor %s>%s" % [f["id"], f["room_key"]]
	if cache.has(key):
		return cache[key]
	var pts := PackedVector2Array()
	for p: Vector2 in _floor_grid(f):
		if (not SlotRules.in_wall_band(w, f, p)
				and SlotFaults.point_faults(w, f, p, cache, { "kind": "overflow" }).is_empty()):
			pts.append(p)
	cache[key] = pts
	return pts


## `_open_floor_points`' grid: a `CAPACITY_GRID` px grid over frame `f`'s stack side's room (by
## `ROOM_INSET`), or outdoors over a box out from the door `ROOM_FOR_ONE_REACH` px along the wall
## either side and out from it.
static func _floor_grid(f: Dictionary) -> Array:
	var cands: Array = []
	if String(f["from"]) != "":
		var rect: Rect2 = (f["from_rect"] as Rect2).grow(-Slots.ROOM_INSET)
		var y := rect.position.y
		while y <= rect.end.y:
			var x := rect.position.x
			while x <= rect.end.x:
				cands.append(Vector2(x, y))
				x += CAPACITY_GRID
			y += CAPACITY_GRID
		return cands
	var pos: Vector2 = f["pos"]
	var out: Vector2 = f["out"]
	var along: Vector2 = f["along"]
	var lat := -Slots.ROOM_FOR_ONE_REACH
	while lat <= Slots.ROOM_FOR_ONE_REACH:
		var o := Slots.ROOM_INSET
		while o <= Slots.ROOM_FOR_ONE_REACH:
			cands.append(pos + out * o + along * lat)
			o += CAPACITY_GRID
		lat += CAPACITY_GRID
	return cands


## How many more members the open floor of a short wall's way in then holds, beside the wall slots
## `taken` (points): the most `_open_floor_points` pairwise, and from every taken point, at least
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
	for p in _open_floor_points(w, f, cache):
		if taken.all(func(q): return (q as Vector2).distance_to(p) >= Slots.STACK_SPACING):
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


## Every spot of the test's own beside the door against its wall, on both sides, that keeps every
## rule but the other doorways' views (`room_for_one`'s spots, all of them):
## `[{ point, side, views }]`.
static func wall_spots(w: Dictionary, f: Dictionary) -> Array:
	var spots: Array = []
	for side in [1, -1]:
		spots.append_array(_wall_spots_on(w, f, side))
	return spots


## `wall_spots` on side `side` of the door, nearest the door first, up to the wall's end (another
## doorway's funnel).
static func _wall_spots_on(w: Dictionary, f: Dictionary, side: int) -> Array:
	var spots: Array = []
	var pos: Vector2 = f["pos"]
	var out: Vector2 = f["out"]
	var along: Vector2 = (f["along"] as Vector2) * side
	var reach := Slots.ROOM_FOR_ONE_REACH
	if String(f["from"]) != "":
		reach = SlotRules.ray_to_edge(f["from_rect"], pos + out * Slots.ROOM_FOR_ONE_OUT, along)
	var past := float(f["width"]) * 0.5 + Slots.ROOM_FOR_ONE_PAST
	var walled := false
	while past <= reach and not walled:
		for o in [
			Slots.ROOM_FOR_ONE_OUT,
			Slots.ROOM_FOR_ONE_OUT - 6.0,
			Slots.ROOM_FOR_ONE_OUT + 8.0,
		]:
			var p: Vector2 = pos + out * o + along * past
			if SlotRules.in_other_funnel(w, f, p) != "":
				walled = true   # The wall's end: another doorway's funnel.
				break
			if _not_a_spot(w, f, p):
				continue
			spots.append({ "point": p, "side": side, "views": SlotRules.view_count(w, f, p) })
			break
		past += Slots.ROOM_FOR_ONE_STEP
	return spots


## Whether `p` breaks a rule of `wall_spots` but the other doorways' views: outside the stack side,
## off the navmesh, unreached from the stack side, or on furniture.
static func _not_a_spot(w: Dictionary, f: Dictionary, p: Vector2) -> bool:
	return (SlotRules.in_stack_room(w, f, p) != ""
			or SlotRules.on_navmesh(w, p) != ""
			or SlotRules.reachable(w, f, p) != ""
			or SlotRules.clear_of_furniture(w, p) != "")


## The most other doorways a slot of a stack of `count` may be seen from on a `views` way in: the
## test's own pick of `count` spots of `spots` (`wall_spots`), `STACK_SPACING` apart, fewest views
## first (nearest the door on a tie); the most-seen of the spots when they cannot take `count`.
static func fewest_views_bar(spots: Array, count: int) -> int:
	var picks := _fewest_views_pick(spots, count)
	var pool := picks if picks.size() == count else spots
	var bar := 0
	for s in pool:
		bar = maxi(bar, int(s["views"]))
	return bar


## The test's own pick of up to `count` spots of `spots` (`wall_spots`), `STACK_SPACING` apart,
## fewest views first (nearest the door on a tie): what `fewest_views_bar` reads its bar from (fewer
## than `count` when the spots cannot take them).
static func _fewest_views_pick(spots: Array, count: int) -> Array:
	var order := spots.duplicate()
	order.sort_custom(func(a, b): return (
		a["views"] < b["views"]
			if a["views"] != b["views"]
			else a["point"].length_squared() < b["point"].length_squared()
	))
	var picks: Array = []
	for s in order:
		if picks.all(
				func(q): return (
					(q["point"] as Vector2).distance_to(s["point"]) >= Slots.STACK_SPACING
				),
		):
			picks.append(s)
		if picks.size() == count:
			break
	return picks
