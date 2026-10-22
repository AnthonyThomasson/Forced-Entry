extends GameTest
## E20 to E22 (`docs/tactical-entry.md`, ticket #65 round 2): where a stack's slots lie, swept over
## every doorway of every floorplan. Geometry only, no simulation: the house is built and baked,
## then each way into each room (both sides of every doorway's wall, an exterior door from outside)
## is read for stacks of 1 to 6 starting on either side of the door (1 / -1 along its wall), through
## the published rule for where a stack of N stands (`DoorStack.stack_slots(g, count, side)`, read
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
## ticket's rule 6 instead, judged the same way (`Slots.way_kind`): when every spot beside the door
## against its wall is in some other doorway's view, the slots take the spots seen from the fewest
## other doorways (counted with the test's own view check), never in a funnel, in the same room;
## when there is no spot against the wall at all, they stand on the stack-side room's open floor
## (inside its rect, off the door's axis by a body, out of its funnel), and the members it cannot
## hold are the stack's tail, numbered last, holding in the room they came by at its doorway into
## the small room, off that doorway's axis and out of its funnel; and when that small room is a dead
## end (its only doorway the one entered: no room for a tail), the stack takes only as many slots as
## its open floor holds at the normal spacing, never squeezed, never a tail slot: exactly min(N,
## what the room holds) slots, the room's capacity counted by the test's own geometry
## (`Slots.dead_end_capacity`: the most points of a 4 px grid, 44 px apart, that keep the open-floor
## rules, searched exhaustively), and the members past it get no slot. A way in against a wall whose
## wall band (both sides and the second file, judged as above) holds fewer than the stack takes the
## chain the user decided in round 2 (`Slots.short_wall_faults`): the wall takes exactly min(N, what
## it holds) slots, numbered first, its capacity the test's own exhaustive packing of the band's
## valid points at the slot spacing (`Slots.wall_capacity`); the members past it stand on the same
## room's open floor (in the room, off the door's axis by a body, out of its funnel and every other
## doorway's view and funnel, on the navmesh, reached, off furniture, spacing kept), numbered after
## every wall slot, as many as it then holds (`Slots.open_floor_capacity`, the same packing); then
## the tail at the room's other doorway (the tail rule above), or, from a room with no other
## doorway, no more slots. Only on a dead end and that last link may a stack have fewer slots than
## members. The same chain holds where every wall spot is in another doorway's view and the wall's
## fewest-seen spots hold fewer than the stack (`Slots.views_capacity`): the band takes exactly
## min(N, what they hold) slots by the `views` rule above (never in a funnel, seen from no more
## other doorways than the test's own bar), its capacity the same exhaustive packing of the band's
## points that keep that rule; then the same room's open floor (out of every other doorway's view
## and funnel), numbered after them; then the tail, or the dead-end cap. On failure every offending
## house, doorway, side and slot is listed by rule: the sweep is the evidence of the bug.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
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
	var offences: Array = []
	var kinds := {}   # way_kind -> the ways in of that kind ("<house> <door>>room")
	var swept := 0
	var terrace := t.world.get_world_2d()
	swept += _sweep(
		t,
		"terrace",
		t.world.house,
		t.rooms,
		t.world.openings,
		terrace.navigation_map,
		terrace.direct_space_state,
		offences,
		kinds,
	)
	for plan in HouseDefinitions.get_all():
		for house_seed in SEEDS:
			var built: Dictionary = await _build_house(t, String(plan), int(house_seed))
			if not t.require(
					not built.is_empty(),
					"the %s house (seed %d) is built and its navigation map comes up"
						% [plan, house_seed],
			):
				return
			var w2d: World2D = built["viewport"].world_2d
			swept += _sweep(
				t, "%s#%d" % [plan, house_seed], built["house"], built["rooms"], built["openings"],
				w2d.navigation_map, w2d.direct_space_state, offences, kinds,
			)
			built["viewport"].queue_free()
			await t.frames(1)
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
	_report(t, offences)


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


## Sweep every way into every room of one house (`label`), adding what breaks the rules to
## `offences`. Returns how many ways in it read.
func _sweep(t: TestContext, label: String, house: Node2D, rooms: Array, openings: Array, map: RID,
		space: PhysicsDirectSpaceState2D, offences: Array, kinds: Dictionary) -> int:
	var entry := Slots.entry_geometry(openings, rooms)
	if not t.require(entry != null, "the entry geometry script exists (%s)" % Slots.ENTRY_SCRIPT):
		return 0
	var w := Slots.world_of(rooms, openings, map, space, house)
	var cache := {}
	# "<door> <side> <n> <rule>" -> true: one line per slot and rule, at the smallest stack that
	# shows it.
	var seen := {}
	var read := 0
	for f: Dictionary in w["frames"]:
		var door := "%s>%s" % [f["id"], f["room_key"]]
		var g: Dictionary = entry.geometry(f["id"], f["room_key"], map, space)
		if g.is_empty():
			offences.append({
				"house": label, "door": door, "side": 0, "n": 0, "count": 0, "point": Vector2.INF,
				"rule": "geometry", "why": "the AI has no entry geometry for it",
			})
			continue
		read += 1
		var kind := Slots.way_kind(w, f)
		var capacity: Dictionary = (Slots.dead_end_capacity(w, f, cache)
				if kind == "dead_end"
				else {})
		kinds[kind] = kinds.get(kind, []) + [
			"%s %s%s" % [
				label,
				door,
				(" (holds %d)" % int(capacity["count"])) if kind == "dead_end" else "",
			],
		]
		if kind == "views":
			door += " (every wall spot in another doorway's view)"
		elif kind == "open_floor":
			door += " (no wall spot)"
		elif kind == "dead_end":
			door += " (no wall spot, a dead end holding %d)" % int(capacity["count"])
		var spots: Array = Slots.wall_spots(w, f) if kind == "views" else []
		var lays := {}   # "<side> <count>" -> layout
		for side in [1, -1]:
			for count in range(1, Slots.MAX_STACK + 1):
				lays["%d %d" % [side, count]] = Slots.layout(g, count, side)
		if kind == "wall":
			var wall := _wall_capacity(w, f, cache, lays)
			if int(wall["count"]) < Slots.MAX_STACK:
				capacity = { "wall": wall }
				door += " (a short wall holding %d)" % int(wall["count"])
				kinds["short_wall"] = kinds.get("short_wall", []) + [
					"%s %s>%s (holds %d)" % [label, f["id"], f["room_key"], int(wall["count"])],
				]
		elif kind == "views":
			var extra: Array = []
			for key in lays:
				extra.append_array((lays[key]["slots"] as Array).map(func(s): return s["point"]))
			var views := Slots.views_capacity(w, f, cache, spots, extra)
			if not views.is_empty() and int(views["count"]) < Slots.MAX_STACK:
				capacity = { "wall": views }
				door = (door.trim_suffix(")")
						+ ", its fewest-seen spots holding %d)" % int(views["count"]))
				kinds["short_views"] = kinds.get("short_views", []) + [
					"%s %s>%s (holds %d, seen from at most %d)"
						% [label, f["id"], f["room_key"], int(views["count"]), int(views["bar"])],
				]
		for side in [1, -1]:
			for count in range(1, Slots.MAX_STACK + 1):
				var bar := Slots.fewest_views_bar(spots, count) if kind == "views" else 0
				var lay: Dictionary = lays["%d %d" % [side, count]]
				var slots: Array = lay["slots"]
				var judged := capacity
				var caps := ""
				var short := Slots.is_short_wall(kind, capacity, count)
				if short:
					var need := count - int(capacity["wall"]["count"])
					var in_band := func(s): return Slots.in_wall_band(w, f, s["point"])
					var taken: Array = slots.filter(in_band).map(func(s): return s["point"])
					var open := Slots.open_floor_capacity(w, f, cache, taken, need)
					open["need"] = need
					judged = { "wall": capacity["wall"], "open": open }
					caps = Slots.capacity_text(w, f, judged)
				for s in slots:
					var slot_kind := kind
					if short and not Slots.in_wall_band(w, f, s["point"]):
						slot_kind = "overflow"
					for fault in Slots.point_faults(w, f, s["point"], cache, slot_kind, bar):
						_add(
							offences,
							seen,
							label,
							door,
							side,
							int(s["n"]),
							count,
							s["point"],
							fault[0],
							_with_caps(fault[1], caps),
						)
				for fault in Slots.stack_faults(w, f, slots, count, side, kind, judged):
					var at: Vector2 = Vector2.INF
					for s in slots:
						if int(s["n"]) == int(fault[0]):
							at = s["point"]
					_add(
						offences,
						seen,
						label,
						door,
						side,
						int(fault[0]),
						count,
						at,
						fault[1],
						_with_caps(fault[2], caps),
					)
	return read


## What frame `f`'s wall band holds (`Slots.wall_capacity`), `{ count, points }`: when a stack of
## six of the way in's own layouts (`lays`) stands in the band on valid points at the slot spacing,
## that stack is the packing (the wall holds six); else the test's own exhaustive packing of the
## band's grid and the layouts' valid band points.
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
		if (points.size() < Slots.MAX_STACK
					or not points.all(func(p): return (
						Slots.in_wall_band(w, f, p)
							and Slots.point_faults(w, f, p, cache, "wall").is_empty()
					))):
			continue
		var spaced := true
		for i in points.size():
			for j in range(i + 1, points.size()):
				spaced = (spaced
						and (points[i] as Vector2).distance_to(points[j]) >= Slots.STACK_SPACING)
		if spaced:
			return { "count": points.size(), "points": points }
	return Slots.wall_capacity(w, f, cache, extra)


## `why` with a short wall's capacities (`caps`) added, unless it names them already.
static func _with_caps(why: String, caps: String) -> String:
	return why if caps == "" or why.contains(caps) else "%s %s" % [why, caps]


func _add(
	offences: Array,
	seen: Dictionary,
	house: String,
	door: String,
	side: int,
	n: int,
	count: int,
	point: Vector2,
	rule: String,
	why: String,
) -> void:
	var key := "%s %s %d %d %s" % [house, door, side, n, rule]
	if seen.has(key):
		return
	seen[key] = true
	offences.append({
		"house": house, "door": door, "side": side, "n": n, "count": count, "point": point,
		"rule": rule, "why": why,
	})


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
