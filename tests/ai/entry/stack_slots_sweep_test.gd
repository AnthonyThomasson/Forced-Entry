extends GameTest
## E20 to E22 (`docs/tactical-entry.md`, ticket #65 round 2): where a stack's slots lie, swept over
## every doorway of every floorplan. Geometry only, no simulation: the house is built and baked,
## then each way into each room (both sides of every doorway's wall, an exterior door from outside)
## is read for stacks of 1 to 6 starting on either side of the door (1 / -1 along its wall), through
## the published rule for where a stack of N stands (`StackLayout.slots(g, count, side)`, read
## through `tests/_ai/slots_probe.gd`).
##
## The houses: the 11 generated floorplans (`HouseDefinitions.get_all()`), each with 3 fixed seeds
## and furnished as a match furnishes them (`WorldGen.generate`, its front door at the origin as a
## test house's), each in a world of its own (a `SubViewport` with its own `World2D`: its own
## physics space and navigation map); and the Terrace house (`flank_maps.gd`), furnished, as the
## test's own world.
##
## Every slot must (E20) lie in the room (or the outdoor area) on the stack side of the doorway's
## wall, judged from the rooms' rects and the wall plane; be on the navmesh; be reached from the
## stack side by a route that does not go through the doorway; be out of every other doorway's view
## and funnel; (E22) be off solid furniture (`NavBuilder.furniture_holes`); and (E2) stand beside
## the door, against the wall or (E21) a step out from it. Each stack keeps its spacing and its
## files nearest the door first; its point stands on the asked side when that side has room; a
## second file only once neither side has room (E21). A way in with no such spot answers to the
## ticket's rule 6 instead, judged the same way (`SlotCapacity.way_kind`): when every spot beside
## the door against its wall is in some other doorway's view, the slots take the spots seen from the
## fewest other doorways (counted with the test's own view check), never in a funnel, in the same
## room; when there is no spot against the wall at all, they stand on the stack-side room's open
## floor (inside its rect, off the door's axis by a body, out of its funnel), and the members it
## cannot hold are the stack's tail, numbered last, holding in the room they came by at its doorway
## into the small room, off that doorway's axis and out of its funnel; and when that small room is a
## dead end (its only doorway the one entered: no room for a tail), the stack takes only as many
## slots as its open floor holds at the normal spacing, never squeezed, never a tail slot: exactly
## min(N, what the room holds) slots, the room's capacity counted by the test's own geometry
## (`SlotCapacity.dead_end_capacity`: the most points of a 4 px grid, 44 px apart, that keep the
## open-floor rules, searched exhaustively), and the members past it get no slot. A way in against a
## wall whose wall band (both sides and the second file, judged as above) holds fewer than the stack
## takes the chain the user decided in round 2 (`SlotFaults.short_wall_faults`): the wall takes
## exactly min(N, what it holds) slots, numbered first, its capacity the test's own exhaustive
## packing of the band's valid points at the slot spacing (`SlotCapacity.wall_capacity`); the
## members past it stand on the same room's open floor (in the room, off the door's axis by a body,
## out of its funnel and every other doorway's view and funnel, on the navmesh, reached, off
## furniture, spacing kept), numbered after every wall slot, as many as it then holds
## (`SlotCapacity.open_floor_capacity`, the same packing); then the tail at the room's other doorway
## (the tail rule above), or, from a room with no other doorway, no more slots. Only on a dead end
## and that last link may a stack have fewer slots than members. The same chain holds where every
## wall spot is in another doorway's view and the wall's fewest-seen spots hold fewer than the stack
## (`SlotCapacity.views_capacity`): the band takes exactly min(N, what they hold) slots by the
## `views` rule above (never in a funnel, seen from no more other doorways than the test's own bar),
## its capacity the same exhaustive packing of the band's points that keep that rule; then the same
## room's open floor (out of every other doorway's view and funnel), numbered after them; then the
## tail, or the dead-end cap. On failure every offending house, doorway, side and slot is listed by
## rule: the sweep is the evidence of the bug.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
const SlotCapacity := preload("res://tests/_ai/slot_capacity_probe.gd")
const SlotFaults := preload("res://tests/_ai/slot_faults_probe.gd")
const SlotRules := preload("res://tests/_ai/slot_rules_probe.gd")
## The fixed seeds each generated floorplan is built with (furniture and the plan's mirroring follow
## the seed).
const SEEDS := [1, 2, 3]
## How long (physics frames) a house's navigation map is given to come up after its bake.
const NAV_WAIT_FRAMES := 240


func describe() -> Dictionary:
	return {
		"name": "Every stack slot of every doorway lies in the stack's room",
		"description": "Every doorway of the 11 generated floorplans (3 seeds, furnished) and the "
			+ "Terrace house, both sides of its wall, stacks of 1 to 6 on either side of the "
			+ "door: each slot in the stack-side room, on the navmesh, reachable without crossing "
			+ "the doorway, out of every other doorway's view and funnel, off furniture, spacing "
			+ "kept, the other side then a second file when a wall runs out (E20 to E22); a "
			+ "dead-end small room takes only as many slots as its open floor holds, and a wall "
			+ "that holds fewer than the stack takes as many as it holds, then the room's open "
			+ "floor, then the tail or the dead-end cap, and the same where every wall spot is in "
			+ "another doorway's view and its fewest-seen spots hold fewer (rule 6).",
		"tags": ["ai", "entry", "stack", "geometry", "sweep"],
		"timeout": 600.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, true)
	s.switch(&"lighting.enabled", false)


func run(t: TestContext) -> void:
	# offences: what breaks the rules; kinds: way_kind -> the ways in of that kind
	# ("<house> <door>>room")
	var found := { "offences": [], "kinds": {} }
	var terrace := t.world.get_world_2d()
	var swept := _sweep(
		t,
		{
			"label": "terrace", "house": t.world.house, "rooms": t.rooms,
			"openings": t.world.openings, "map": terrace.navigation_map,
			"space": terrace.direct_space_state,
		},
		found,
	)
	for plan in HouseDefinitions.get_all():
		for house_seed in SEEDS:
			var read: int = await _sweep_plan(t, String(plan), int(house_seed), found)
			if read < 0:
				return
			swept += read
	_check_swept(t, swept, found["kinds"])
	_report(t, found["offences"])


## Build generated house `plan` from `house_seed` (`_build_house`) and sweep it into `found`
## (`_sweep`): how many ways in it read, or -1 when it was not built.
func _sweep_plan(t: TestContext, plan: String, house_seed: int, found: Dictionary) -> int:
	var built: Dictionary = await _build_house(t, plan, house_seed)
	if not t.require(
			not built.is_empty(),
			"the %s house (seed %d) is built and its navigation map comes up" % [plan, house_seed],
	):
		return -1
	var w2d: World2D = built["viewport"].world_2d
	var read := _sweep(
		t,
		{
			"label": "%s#%d" % [plan, house_seed], "house": built["house"],
			"rooms": built["rooms"], "openings": built["openings"], "map": w2d.navigation_map,
			"space": w2d.direct_space_state,
		},
		found,
	)
	built["viewport"].queue_free()
	await t.frames(1)
	return read


## The checks that the sweep read the ways in of every kind: `swept` ways in all told, `kinds`
## (way_kind -> its ways in) by kind.
func _check_swept(t: TestContext, swept: int, kinds: Dictionary) -> void:
	t.check(
		swept > 0,
		("the sweep read some stacks (%d ways in: %d against a wall, %d where every wall spot is "
				+ "in another doorway's view, %d with no wall spot and a room for a tail, %d with "
				+ "no wall spot from a dead-end small room: %s)")
			% [
				swept, kinds.get("wall", []).size(), kinds.get("views", []).size(),
				kinds.get("open_floor", []).size(), kinds.get("dead_end", []).size(),
				"; ".join(kinds.get("dead_end", [])),
			],
	)
	t.check(
		swept > 0,
		("the sweep read the short walls (%d of the %d ways in against a wall hold fewer than %d: "
				+ "%s)")
			% [
				kinds.get("short_wall", []).size(),
				kinds.get("wall", []).size(),
				Slots.MAX_STACK,
				"; ".join(kinds.get("short_wall", [])),
			],
	)
	t.check(
		swept > 0,
		("the sweep read the short views walls (%d of the %d ways in where every wall spot is in "
				+ "another doorway's view hold fewer than %d by their fewest-seen spots: %s)")
			% [
				kinds.get("short_views", []).size(),
				kinds.get("views", []).size(),
				Slots.MAX_STACK,
				"; ".join(kinds.get("short_views", [])),
			],
	)


## Build generated house `plan` from `house_seed` in a world of its own, baked, and wait for its
## navigation map: `{ viewport, house, rooms, openings }`, or {} when the map never comes up.
func _build_house(t: TestContext, plan: String, house_seed: int) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "Sweep_%s_%d" % [plan, house_seed]
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	t.world.add_child(viewport)
	var root := Node2D.new()
	root.name = "World"
	viewport.add_child(root)
	var house := WorldGen.generate(house_seed, plan, Vector2.ZERO, root)
	var rooms := WorldGen.get_rooms(house)
	NavBuilder.build(house, rooms, root)
	var map: RID = viewport.world_2d.navigation_map
	await t.frames(2)   # The walls and the furniture join the physics space at the next steps.
	var waited := 0
	while not NavBuilder.ready(map) and waited < NAV_WAIT_FRAMES:
		await t.frames(1)
		waited += 1
	if not NavBuilder.ready(map):
		viewport.queue_free()
		return {}
	return {
		"viewport": viewport,
		"house": house,
		"rooms": rooms,
		"openings": WorldGen.get_openings(house),
	}


## Sweep every way into every room of one house (`where`: `{ label, house, rooms, openings, map,
## space }`), adding what breaks the rules to `found.offences` and each way in to `found.kinds`.
## Returns how many ways in it read.
func _sweep(t: TestContext, where: Dictionary, found: Dictionary) -> int:
	var entry := Slots.entry_geometry(where["openings"], where["rooms"])
	if not t.require(entry != null, "the entry geometry script exists (%s)" % Slots.ENTRY_SCRIPT):
		return 0
	var w := Slots.world_of(
		where["rooms"], where["openings"], where["map"], where["space"], where["house"],
	)
	# The sweep of this house: its world, `point_faults`' cache, and `seen`
	# ("<door> <side> <n> <rule>" -> true: one line per slot and rule, at the smallest stack that
	# shows it).
	var sweep := {
		"label": where["label"], "w": w, "cache": {}, "seen": {}, "offences": found["offences"],
		"kinds": found["kinds"],
	}
	var read := 0
	for f: Dictionary in w["frames"]:
		var g: Dictionary = entry.geometry(f["id"], f["room_key"], where["map"], where["space"])
		if g.is_empty():
			(found["offences"] as Array).append({
				"house": where["label"], "door": "%s>%s" % [f["id"], f["room_key"]], "side": 0,
				"n": 0, "count": 0, "point": Vector2.INF, "rule": "geometry",
				"why": "the AI has no entry geometry for it",
			})
			continue
		read += 1
		var way := _way(sweep, f, g)
		for side in [1, -1]:
			for count in range(1, Slots.MAX_STACK + 1):
				_judge_stack(sweep, way, side, count)
	return read


## The way in by frame `f` (the AI's geometry `g`) as the sweep judges it: `{ f, kind, door,
## capacity, spots, lays }` (its `way_kind`; its words for the messages; what it holds, on a dead
## end or a short wall; its wall spots on a `views` way in; `lays`: "<side> <count>" -> layout),
## noted in `sweep.kinds`.
func _way(sweep: Dictionary, f: Dictionary, g: Dictionary) -> Dictionary:
	var w: Dictionary = sweep["w"]
	var door := "%s>%s" % [f["id"], f["room_key"]]
	var kind := SlotCapacity.way_kind(w, f)
	var capacity: Dictionary = (SlotCapacity.dead_end_capacity(w, f, sweep["cache"])
			if kind == "dead_end"
			else {})
	_note(sweep, kind, "%s %s%s" % [
		sweep["label"],
		door,
		(" (holds %d)" % int(capacity["count"])) if kind == "dead_end" else "",
	])
	if kind == "views":
		door += " (every wall spot in another doorway's view)"
	elif kind == "open_floor":
		door += " (no wall spot)"
	elif kind == "dead_end":
		door += " (no wall spot, a dead end holding %d)" % int(capacity["count"])
	var way := {
		"f": f, "kind": kind, "door": door, "capacity": capacity,
		"spots": SlotCapacity.wall_spots(w, f) if kind == "views" else [], "lays": {},
	}
	for side in [1, -1]:
		for count in range(1, Slots.MAX_STACK + 1):
			way["lays"]["%d %d" % [side, count]] = Slots.layout(g, count, side)
	if kind == "wall":
		_short_wall(sweep, way)
	elif kind == "views":
		_short_views(sweep, way)
	return way


## Add the way in `entry` (in words) to the ways in of kind `kind` in `sweep.kinds`.
func _note(sweep: Dictionary, kind: String, entry: String) -> void:
	var kinds: Dictionary = sweep["kinds"]
	kinds[kind] = kinds.get(kind, []) + [entry]


## On a `wall` way in, what its wall band holds (`_wall_capacity`): a short wall's capacity and
## words, noted in `sweep.kinds`, when it holds fewer than `MAX_STACK`.
func _short_wall(sweep: Dictionary, way: Dictionary) -> void:
	var f: Dictionary = way["f"]
	var wall := _wall_capacity(sweep["w"], f, sweep["cache"], way["lays"])
	if int(wall["count"]) >= Slots.MAX_STACK:
		return
	way["capacity"] = { "wall": wall }
	way["door"] += " (a short wall holding %d)" % int(wall["count"])
	_note(
		sweep,
		"short_wall",
		"%s %s>%s (holds %d)" % [sweep["label"], f["id"], f["room_key"], int(wall["count"])],
	)


## On a `views` way in, what its band's fewest-seen spots hold (`SlotCapacity.views_capacity`, with
## the way in's own slots): a short wall's capacity and words, noted in `sweep.kinds`, when they
## hold fewer than `MAX_STACK`.
func _short_views(sweep: Dictionary, way: Dictionary) -> void:
	var f: Dictionary = way["f"]
	var extra: Array = []
	for key in way["lays"]:
		extra.append_array((way["lays"][key]["slots"] as Array).map(func(s): return s["point"]))
	var views := SlotCapacity.views_capacity(sweep["w"], f, sweep["cache"], way["spots"], extra)
	if views.is_empty() or int(views["count"]) >= Slots.MAX_STACK:
		return
	way["capacity"] = { "wall": views }
	way["door"] = (String(way["door"]).trim_suffix(")")
			+ ", its fewest-seen spots holding %d)" % int(views["count"]))
	_note(
		sweep,
		"short_views",
		"%s %s>%s (holds %d, seen from at most %d)"
			% [sweep["label"], f["id"], f["room_key"], int(views["count"]), int(views["bar"])],
	)


## Judge the stack of `count` on side `side` of the way in `way`: each slot's rules
## (`SlotFaults.point_faults`), then the stack's (`SlotFaults.stack_faults`), adding what breaks to
## `sweep`.
func _judge_stack(sweep: Dictionary, way: Dictionary, side: int, count: int) -> void:
	var kind: String = way["kind"]
	var stack := {
		"side": side, "count": count,
		"slots": way["lays"]["%d %d" % [side, count]]["slots"],
		"bar": SlotCapacity.fewest_views_bar(way["spots"], count) if kind == "views" else 0,
		"short": SlotFaults.is_short_wall(kind, way["capacity"], count), "judged": way["capacity"],
		"caps": "",
	}
	if stack["short"]:
		stack["judged"] = _judged_short(sweep, way, stack)
		stack["caps"] = SlotFaults.capacity_text(sweep["w"], way["f"], stack["judged"])
	for s in stack["slots"]:
		_judge_slot(sweep, way, stack, s)
	var w: Dictionary = sweep["w"]
	var f: Dictionary = way["f"]
	var faults := SlotFaults.stack_faults(
		w, f, { "slots": stack["slots"], "count": count, "side": side }, kind, stack["judged"],
	)
	for fault in faults:
		var at: Vector2 = Vector2.INF
		for s in stack["slots"]:
			if int(s["n"]) == int(fault[0]):
				at = s["point"]
		_add(sweep, {
			"house": sweep["label"], "door": way["door"], "side": side, "n": int(fault[0]),
			"count": count, "point": at, "rule": fault[1],
			"why": _with_caps(fault[2], stack["caps"]),
		})


## A short wall's capacities for `stack` (`{ wall, open }`): the wall's, and what the open floor
## then holds beside the stack's own wall slots, up to the members past the wall.
func _judged_short(sweep: Dictionary, way: Dictionary, stack: Dictionary) -> Dictionary:
	var w: Dictionary = sweep["w"]
	var f: Dictionary = way["f"]
	var capacity: Dictionary = way["capacity"]
	var need := int(stack["count"]) - int(capacity["wall"]["count"])
	var in_band := func(s): return SlotRules.in_wall_band(w, f, s["point"])
	var taken: Array = (stack["slots"] as Array).filter(in_band).map(func(s): return s["point"])
	var open := SlotCapacity.open_floor_capacity(w, f, sweep["cache"], taken, need)
	open["need"] = need
	return { "wall": capacity["wall"], "open": open }


## Judge slot `s` of `stack` by its own rules (`SlotFaults.point_faults`: the way in's kind, or
## `overflow` for a short wall's slot off its band), adding what breaks to `sweep`.
func _judge_slot(sweep: Dictionary, way: Dictionary, stack: Dictionary, s: Dictionary) -> void:
	var w: Dictionary = sweep["w"]
	var f: Dictionary = way["f"]
	var slot_kind: String = way["kind"]
	if stack["short"] and not SlotRules.in_wall_band(w, f, s["point"]):
		slot_kind = "overflow"
	var rules := { "kind": slot_kind, "bar": stack["bar"] }
	for fault in SlotFaults.point_faults(w, f, s["point"], sweep["cache"], rules):
		_add(sweep, {
			"house": sweep["label"], "door": way["door"], "side": stack["side"],
			"n": int(s["n"]), "count": stack["count"], "point": s["point"], "rule": fault[0],
			"why": _with_caps(fault[1], stack["caps"]),
		})


## What frame `f`'s wall band holds (`SlotCapacity.wall_capacity`), `{ count, points }`: when a
## stack of six of the way in's own layouts (`lays`) stands in the band on valid points at the slot
## spacing, that stack is the packing (the wall holds six); else the test's own exhaustive packing
## of the band's grid and the layouts' valid band points.
func _wall_capacity(
	w: Dictionary,
	f: Dictionary,
	cache: Dictionary,
	lays: Dictionary,
) -> Dictionary:
	var extra: Array = []
	for key in lays:
		var points: Array = (lays[key]["slots"] as Array).map(func(s): return s["point"])
		extra.append_array(points)
		if _packs_six(w, f, cache, points):
			return { "count": points.size(), "points": points }
	return SlotCapacity.wall_capacity(w, f, cache, extra)


## Whether `points` (a layout's) are `MAX_STACK` valid wall-band points of frame `f`, pairwise at
## least the slot spacing apart.
func _packs_six(w: Dictionary, f: Dictionary, cache: Dictionary, points: Array) -> bool:
	var valid := func(p): return (
		SlotRules.in_wall_band(w, f, p)
			and SlotFaults.point_faults(w, f, p, cache, { "kind": "wall" }).is_empty()
	)
	if points.size() < Slots.MAX_STACK or not points.all(valid):
		return false
	for i in points.size():
		for j in range(i + 1, points.size()):
			if (points[i] as Vector2).distance_to(points[j]) < Slots.STACK_SPACING:
				return false
	return true


## `why` with a short wall's capacities (`caps`) added, unless it names them already.
static func _with_caps(why: String, caps: String) -> String:
	return why if caps == "" or why.contains(caps) else "%s %s" % [why, caps]


## Note `offence` (`{ house, door, side, n, count, point, rule, why }`) in `sweep.offences`, once
## per house, door, side, slot and rule (at the smallest stack that shows it, `sweep.seen`).
func _add(sweep: Dictionary, offence: Dictionary) -> void:
	var key := "%s %s %d %d %s" % [
		offence["house"], offence["door"], offence["side"], offence["n"], offence["rule"],
	]
	if sweep["seen"].has(key):
		return
	sweep["seen"][key] = true
	(sweep["offences"] as Array).append(offence)


## One check per house and rule, listing every offending doorway, side and slot; then a summary line
## per rule by floorplan.
func _report(t: TestContext, offences: Array) -> void:
	var by := {}   # "<house>|<rule>" -> lines
	var summary := {}   # rule -> plan -> count
	for o: Dictionary in offences:
		var line := "%s side %+d slot %d (of a stack of %d) at %s: %s" % [
			o["door"], o["side"], o["n"], o["count"],
			str((o["point"] as Vector2).round()) if o["point"] != Vector2.INF else "-", o["why"],
		]
		var key := "%s|%s" % [o["house"], o["rule"]]
		by[key] = by.get(key, []) + [line]
		var plan := String(o["house"]).get_slice("#", 0)
		var per: Dictionary = summary.get(o["rule"], {})
		per[plan] = int(per.get(plan, 0)) + 1
		summary[o["rule"]] = per
	var keys := by.keys()
	keys.sort()
	for key in keys:
		var house := String(key).get_slice("|", 0)
		var rule := String(key).get_slice("|", 1)
		t.check(
			false,
			"%s: %s broken at %d slot(s): %s" % [house, rule, by[key].size(), "; ".join(by[key])],
		)
	for rule in summary:
		t.check(false, "summary, %s: offending slots by floorplan %s" % [rule, str(summary[rule])])
	t.check(
		offences.is_empty(),
		"every slot of every stack keeps E20 to E22 (%d offending slot(s))" % offences.size(),
	)
