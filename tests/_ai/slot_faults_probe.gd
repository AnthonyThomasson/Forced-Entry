extends RefCounted
## Shared helpers for the tests of where a stack's slots lie (`docs/tactical-entry.md` E20 to E22;
## not a test itself): `const SlotFaults := preload("res://tests/_ai/slot_faults_probe.gd")`. The
## faults a slot (`point_faults`), a whole stack (`stack_faults`) or a short wall's chain
## (`short_wall_faults`) breaks, each a line naming the rule, with `is_short_wall` and
## `capacity_text`; judged by the rules of `slot_rules_probe.gd`.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const SlotRules := preload("res://tests/_ai/slot_rules_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
## `tuning.entry_geometry.stack_spacing` (44 px) less a few px for snapping: no two slots of a stack
## are closer than this (E2, E22).
const MIN_SPACING := 38.0


## Every rule one slot `p` breaks, as `[rule, why]` pairs (empty when it keeps them all), on a way
## in of kind `rules.kind` (`way_kind`; `wall` when not given):
## - `wall`: E20 (in the stack side's room, on the navmesh, reached from the stack side, out of the
##   other doorways' views and funnels), E22 (off furniture), E2 / E21 (beside the door, against the
##   wall or a step out from it);
## - `views`: the same, but seen from no more other doorways than `rules.bar` (`fewest_views_bar`)
##   instead of out of every view;
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
	rules: Dictionary = {},
) -> Array:
	var kind := String(rules.get("kind", "wall"))
	var bar := int(rules.get("bar", 0))
	var key := "%s>%s@%s %s %d" % [f["id"], f["room_key"], str(p.round()), kind, bar]
	if cache.has(key):
		return cache[key]
	var why := SlotRules.in_stack_room(w, f, p)
	var out: Array
	if (why != ""
			and (kind == "open_floor"
				or kind == "dead_end"
				or (kind == "overflow" and String(f["from"]) != ""))):
		out = _outside_room_faults(w, f, p, kind, why)
	else:
		out = _point_rule_faults(w, f, p, rules, why)
		out.append_array(_placement_faults(f, p, kind))
	cache[key] = out
	return out


## `point_faults` for a slot `p` outside the stack side's room (`why`) on an `open_floor`,
## `dead_end` or `overflow` way in: a tail spot's faults, or the dead end's.
static func _outside_room_faults(
		w: Dictionary, f: Dictionary, p: Vector2, kind: String, why: String
) -> Array:
	var out: Array = []
	if kind == "dead_end" or (kind == "overflow" and Slots.ways_into_stack_room(w, f).is_empty()):
		out.append([
			"E20 fallback: a dead end's slots all in its room",
			"%s, and the %s has no other doorway for a tail to hold at" % [why, f["from"]],
		])
		return out
	var tail := SlotRules.tail_fault(w, f, p)
	if tail != "":
		out.append([
			"E20 fallback: the tail in the room it came by",
			"%s, and %s" % [why, tail],
		])
	return out


## `point_faults`' E20 and E22 rules for slot `p` (`why`: why it is not in the stack side's room,
## or ""), by `rules`.
static func _point_rule_faults(
		w: Dictionary, f: Dictionary, p: Vector2, rules: Dictionary, why: String
) -> Array:
	var kind := String(rules.get("kind", "wall"))
	var out: Array = []
	if why != "":
		out.append(["E20 in the stack's room", why])
	why = SlotRules.on_navmesh(w, p)
	if why != "":
		out.append(["E20 on the navmesh", why])
	why = SlotRules.reachable(w, f, p)
	if why != "":
		out.append(["E20 reachable from the stack side", why])
	why = (SlotRules.clear_of_other_doors(w, f, p)
			if kind == "wall" or kind == "overflow"
			else SlotRules.in_other_funnel(w, f, p))
	if why != "":
		out.append(["E20 out of other doorways' view and funnel", why])
	if kind == "views":
		out.append_array(_views_faults(w, f, p, int(rules.get("bar", 0))))
	why = SlotRules.clear_of_furniture(w, p)
	if why != "":
		out.append(["E22 off furniture", why])
	return out


## `point_faults`' `views` rule for slot `p`: seen from no more other doorways than `bar`.
static func _views_faults(w: Dictionary, f: Dictionary, p: Vector2, bar: int) -> Array:
	var seen := SlotRules.view_count(w, f, p)
	if seen <= bar:
		return []
	return [[
		"E20 fallback: seen from the fewest other doorways",
		("seen from %d other doorway(s) (%s) where the wall's spots seen from %d would "
				+ "hold the stack") % [seen, SlotRules.in_other_view(w, f, p), bar],
	]]


## `point_faults`' rules for where slot `p` stands against the door on a way in of kind `kind`: on
## the open floor off the door's axis and out of its funnel, else beside the door against the wall
## or a step out from it.
static func _placement_faults(f: Dictionary, p: Vector2, kind: String) -> Array:
	var out: Array = []
	var lateral := absf(Entry.lateral(f, p))
	if kind == "open_floor" or kind == "dead_end" or kind == "overflow":
		if lateral < Slots.BODY:
			out.append([
				"E20 fallback: open floor off the door's axis",
				"%.0f px from the door's axis" % lateral,
			])
		if Entry.in_funnel(f, p):
			out.append([
				"E20 fallback: open floor out of the door's funnel",
				"in the funnel (%.0f px out, %.0f px along)" % [Entry.outward(f, p), lateral],
			])
		return out
	if lateral < float(f["width"]) * 0.5 + Slots.BESIDE:
		out.append([
			"E2 beside the door",
			"%.0f px along the wall from the door's centre, in front of its %.0f px opening"
				% [lateral, f["width"]],
		])
	var o := Entry.outward(f, p)
	if o < Slots.ROW1_MIN or o > Slots.ROW2_MAX:
		out.append(["E2/E21 against the wall or a step out", "%.0f px out from the wall plane" % o])
	return out


## The rules a whole stack's layout (`stack.slots`, from `layout`) breaks as a stack, for a stack of
## `stack.count` on side `stack.side` of frame `f`: one slot per member numbered 1..count, spacing
## kept (E2, E22), each file nearest the door first (E2), the point on the asked side when it has
## room (E21: an ordered stack starts on the order's side), a second file only once neither side has
## room (E21). `[n, rule, why]` triples (`n` 0 for the stack as a whole). On an `open_floor` way in
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
	stack: Dictionary,
	kind := "wall",
	capacity := {},
) -> Array:
	var slots: Array = stack["slots"]
	var out := _count_faults(w, f, stack, kind, capacity)
	out.append_array(_spacing_faults(slots))
	if kind == "dead_end":
		# Every slot in the room (`point_faults`), spacing kept (above): no files, no tail.
		return out
	if kind == "open_floor":
		out.append_array(_tail_last_faults(w, f, slots))
		return out
	if is_short_wall(kind, capacity, int(stack["count"])):
		# The files are the wall's; the overflow is judged above.
		slots = slots.filter(func(s): return SlotRules.in_wall_band(w, f, s["point"]))
	out.append_array(_file_faults(f, slots))
	out.append_array(_side_faults(w, f, slots, int(stack["side"])))
	return out


## `stack_faults`' rules on how many slots `stack` has and their numbers: a short wall's chain
## (`short_wall_faults`), a dead end's cap, else one slot per member.
static func _count_faults(
		w: Dictionary, f: Dictionary, stack: Dictionary, kind: String, capacity: Dictionary
) -> Array:
	var slots: Array = stack["slots"]
	var count := int(stack["count"])
	var numbers: Array = slots.map(func(s): return int(s["n"]))
	var sorted_numbers := numbers.duplicate()
	sorted_numbers.sort()
	if is_short_wall(kind, capacity, count):
		return short_wall_faults(w, f, slots, count, capacity)
	if kind == "dead_end":
		return _dead_end_faults(f, numbers, count, capacity)
	if sorted_numbers != range(1, count + 1):
		return [[0, "one slot per member", "slots %s for a stack of %d" % [str(numbers), count]]]
	return []


## `stack_faults`' dead-end cap: the slots numbered `numbers` of a stack of `count` are exactly
## 1..min(count, what the room holds) (`capacity`, `dead_end_capacity`).
static func _dead_end_faults(
		f: Dictionary, numbers: Array, count: int, capacity: Dictionary
) -> Array:
	var holds := int(capacity.get("count", 0))
	var wanted_here: Array = range(1, mini(count, holds) + 1)
	var sorted_numbers := numbers.duplicate()
	sorted_numbers.sort()
	if sorted_numbers == wanted_here:
		return []
	var points: Array = (capacity.get("points", []) as Array).map(
		func(p): return str((p as Vector2).round()),
	)
	var packing := (", ".join(points)
			if not points.is_empty()
			else "no point keeps the open-floor rules")
	return [[
		0,
		"E20 fallback: a dead end takes as many slots as its room holds",
		("slots %s for a stack of %d, where the %s holds %d at %.0f px apart (the test's "
				+ "own packing: %s), so slots %s")
			% [
				str(numbers),
				count,
				f["from"],
				holds,
				Slots.STACK_SPACING,
				packing,
				str(wanted_here),
			],
	]]


## `stack_faults`' spacing rule: every slot of `slots` at least `MIN_SPACING` from each earlier one.
static func _spacing_faults(slots: Array) -> Array:
	var out: Array = []
	for i in slots.size():
		out.append_array(_too_close_to(slots, i))
	return out


## The slots after slot `slots[i]` closer to it than `MIN_SPACING`, as `_spacing_faults`' faults.
static func _too_close_to(slots: Array, i: int) -> Array:
	var out: Array = []
	for j in range(i + 1, slots.size()):
		var d := (slots[i]["point"] as Vector2).distance_to(slots[j]["point"])
		if d < MIN_SPACING:
			out.append([
				int(slots[j]["n"]),
				"E2/E22 spacing kept",
				"%.0f px from slot %d" % [d, int(slots[i]["n"])],
			])
	return out


## `stack_faults`' open-floor rule: every slot in the stack side's room is numbered before every
## slot of the tail (outside it).
static func _tail_last_faults(w: Dictionary, f: Dictionary, slots: Array) -> Array:
	var out: Array = []
	for s in slots:
		if SlotRules.in_stack_room(w, f, s["point"]) == "":
			continue   # In the room; `s` is the tail's below.
		for o in slots:
			if int(o["n"]) > int(s["n"]) and SlotRules.in_stack_room(w, f, o["point"]) == "":
				out.append([
					int(o["n"]),
					"E20 fallback: the tail last",
					"in the %s, after slot %d of the tail" % [f["from"], int(s["n"])],
				])
	return out


## `stack_faults`' file rule: in each file (a side and a row), the slots nearest the door first.
static func _file_faults(f: Dictionary, slots: Array) -> Array:
	var out: Array = []
	for s in slots:
		out.append_array(_nearer_in_file(f, slots, s))
	return out


## The slots of `slots` numbered after slot `s` in its file yet nearer the door, as `_file_faults`'
## faults.
static func _nearer_in_file(f: Dictionary, slots: Array, s: Dictionary) -> Array:
	var out: Array = []
	for o in slots:
		if (int(o["n"]) <= int(s["n"])
				or Slots.side_of(f, o["point"]) != Slots.side_of(f, s["point"])
				or _row(f, o["point"]) != _row(f, s["point"])):
			continue
		if absf(Entry.lateral(f, o["point"])) < absf(Entry.lateral(f, s["point"])):
			out.append([
				int(o["n"]),
				"E2 file nearest the door first",
				"nearer the door than slot %d in its file" % int(s["n"]),
			])
	return out


## `stack_faults`' E21 rules for a stack ordered on side `side`: its point on that side when it has
## room, and a second file only once neither side has room and no slot.
static func _side_faults(w: Dictionary, f: Dictionary, slots: Array, side: int) -> Array:
	var out: Array = []
	var first: Array = slots.filter(func(s): return int(s["n"]) == 1)
	if (not first.is_empty()
			and Slots.side_of(f, first[0]["point"]) != side
			and SlotRules.side_has_room(w, f, side)):
		out.append([
			1,
			"E21 the point on the order's side",
			"on side %+d though side %+d has room" % [Slots.side_of(f, first[0]["point"]), side],
		])
	var second: Array = slots.filter(
		func(s): return (
			_row(f, s["point"]) == 2 and SlotRules.in_stack_room(w, f, s["point"]) == ""
		),
	)
	if second.is_empty():
		return out
	for s in [1, -1]:
		var used: bool = slots.any(
			func(x): return _row(f, x["point"]) == 1 and Slots.side_of(f, x["point"]) == s,
		)
		if not used and SlotRules.side_has_room(w, f, s):
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
	var ways := Slots.ways_into_stack_room(w, f)
	var tail := "no tail outdoors"
	if not ways.is_empty():
		tail = "the tail holds at %s" % ", ".join(ways.map(func(fo): return fo["id"]))
	elif String(f["from"]) != "":
		tail = "no tail: the %s has no other doorway" % f["from"]
	var walls := "the wall holds"
	if wall.has("bar"):
		walls = "the wall's spots seen from at most %d other doorway(s) hold" % int(wall["bar"])
	return ("[%s %d at %.0f px apart (the test's packing: %s), %s, %s]"
			% [
				walls,
				int(wall["count"]),
				Slots.STACK_SPACING,
				pts.call(wall["points"]),
				opens,
				tail,
			])


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
	var chain := _short_wall_chain(w, f, slots, count, capacity)
	var out := _wall_part_faults(chain)
	out.append_array(_overflow_part_faults(w, f, chain))
	out.append_array(_floor_part_faults(f, chain))
	out.append_array(_chain_number_faults(chain))
	return out


## What `short_wall_faults` judges a short wall's stack of `count` (`slots`, `capacity`) by: the
## slots by number (`ordered`) and by part (`walls` in the band, `on_floor` in the room off it,
## `tail` outside the room, `overflow` off the band), what the wall takes (`want_wall`), what the
## open floor holds (`opens`) and takes (`want_floor`), whether a tail may hold (`tail_ok`), how
## many slots in all (`want_total`), and the capacities for the messages (`caps`).
static func _short_wall_chain(
		w: Dictionary, f: Dictionary, slots: Array, count: int, capacity: Dictionary
) -> Dictionary:
	var opens := int((capacity.get("open", {}) as Dictionary).get("count", 0))
	var want_wall := mini(count, int(capacity["wall"]["count"]))
	var want_floor := mini(count - want_wall, opens)
	var tail_ok := String(f["from"]) != "" and not Slots.ways_into_stack_room(w, f).is_empty()
	var ordered := slots.duplicate()
	ordered.sort_custom(func(a, b): return int(a["n"]) < int(b["n"]))
	return {
		"count": count, "opens": opens, "want_wall": want_wall, "want_floor": want_floor,
		"tail_ok": tail_ok, "want_total": count if tail_ok else want_wall + want_floor,
		"caps": capacity_text(w, f, capacity), "ordered": ordered,
		"walls": ordered.filter(func(s): return SlotRules.in_wall_band(w, f, s["point"])),
		"on_floor": ordered.filter(func(s): return (
			not SlotRules.in_wall_band(w, f, s["point"])
				and SlotRules.in_stack_room(w, f, s["point"]) == ""
		)),
		"tail": ordered.filter(func(s): return SlotRules.in_stack_room(w, f, s["point"]) != ""),
		"overflow": ordered.filter(func(s): return not SlotRules.in_wall_band(w, f, s["point"])),
	}


## `short_wall_faults`' wall rules (`chain`, `_short_wall_chain`): the wall full before its
## overflow, and no more wall slots than the wall takes.
static func _wall_part_faults(chain: Dictionary) -> Array:
	var out: Array = []
	var walls: Array = chain["walls"]
	var overflow: Array = chain["overflow"]
	var want_wall: int = chain["want_wall"]
	if walls.size() < want_wall and not overflow.is_empty():
		out.append([
			int(overflow[0]["n"]),
			"E20 fallback: a short wall full before its overflow",
			"off the wall with %d wall slot(s) where the wall takes %d %s"
				% [walls.size(), want_wall, chain["caps"]],
		])
	for i in range(want_wall, walls.size()):
		out.append([
			int(walls[i]["n"]),
			"E20 fallback: no more wall slots than the wall holds",
			"wall slot %d of %d where the wall takes %d %s"
				% [i + 1, walls.size(), want_wall, chain["caps"]],
		])
	return out


## `short_wall_faults`' rule that the overflow (`chain`) is numbered after every wall slot.
static func _overflow_part_faults(w: Dictionary, f: Dictionary, chain: Dictionary) -> Array:
	var out: Array = []
	var walls: Array = chain["walls"]
	if walls.is_empty():
		return out
	var last_wall := int(walls[walls.size() - 1]["n"])
	for o in chain["overflow"]:
		if int(o["n"]) >= last_wall:
			continue
		var where := "on the open floor" if SlotRules.in_stack_room(
			w,
			f,
			o["point"],
		) == "" else "in the tail"
		out.append([
			int(o["n"]),
			"E20 fallback: the overflow numbered after every wall slot",
			"%s before wall slot %d %s" % [where, last_wall, chain["caps"]],
		])
	return out


## `short_wall_faults`' open-floor rules (`chain`): no more open-floor slots than it holds, the open
## floor full before the tail, and the tail last.
static func _floor_part_faults(f: Dictionary, chain: Dictionary) -> Array:
	var out: Array = []
	var on_floor: Array = chain["on_floor"]
	var tail: Array = chain["tail"]
	var opens: int = chain["opens"]
	for i in range(opens, on_floor.size()):
		out.append([
			int(on_floor[i]["n"]),
			"E20 fallback: no more open-floor slots than the open floor holds",
			"open-floor slot %d of %d where it holds %d %s"
				% [i + 1, on_floor.size(), opens, chain["caps"]],
		])
	if not tail.is_empty() and on_floor.size() < int(chain["want_floor"]):
		out.append([
			int(tail[0]["n"]),
			"E20 fallback: the open floor full before the tail",
			"a tail slot with %d open-floor slot(s) where it takes %d %s"
				% [on_floor.size(), chain["want_floor"], chain["caps"]],
		])
	for tail_slot in tail:
		out.append_array(_floor_after_tail(f, chain, tail_slot))
	return out


## The open-floor slots of `chain` numbered after its tail slot `tail_slot`, as
## `_floor_part_faults`' faults.
static func _floor_after_tail(f: Dictionary, chain: Dictionary, tail_slot: Dictionary) -> Array:
	var out: Array = []
	for s in chain["on_floor"]:
		if int(s["n"]) > int(tail_slot["n"]):
			out.append([
				int(s["n"]),
				"E20 fallback: the tail last",
				"in the %s, after slot %d of the tail %s"
					% [f["from"], int(tail_slot["n"]), chain["caps"]],
			])
	return out


## `short_wall_faults`' numbering (`chain`): slots 1..`want_total`, one per member where a tail may
## hold, else the dead-end cap of the wall and the open floor.
static func _chain_number_faults(chain: Dictionary) -> Array:
	var numbers: Array = (chain["ordered"] as Array).map(func(s): return int(s["n"]))
	var want_total: int = chain["want_total"]
	if numbers == range(1, want_total + 1):
		return []
	if chain["tail_ok"]:
		return [[
			0,
			"one slot per member",
			"slots %s for a stack of %d %s" % [str(numbers), chain["count"], chain["caps"]],
		]]
	return [[
		0,
		"E20 fallback: a short wall's dead end takes as many as its wall and open floor "
			+ "hold",
		"slots %s for a stack of %d, so slots %s %s"
			% [str(numbers), chain["count"], str(range(1, want_total + 1)), chain["caps"]],
	]]


## Which file `p` stands in by its distance from the wall plane: 1 against the wall, 2 a step out.
static func _row(f: Dictionary, p: Vector2) -> int:
	return 1 if Entry.outward(f, p) <= Slots.ROW1_MAX else 2
