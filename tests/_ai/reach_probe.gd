extends RefCounted
## Shared helpers for the tests of every member of an ordered stack reaching its slot
## (`tests/ai/entry/stack_reach_*`, `docs/leadership.md` D4 and D20; not a test itself):
## `const Reach := preload("res://tests/_ai/reach_probe.gd")`.
##
## A leader (a puppet standing in for the human, out of the way, its squad built and bound as a
## match's: the test declares `s.squads({ "human": <the leader> })`) orders a stack on one doorway
## through `Squad.issue`, on the first frame (before its members set off to follow it, LD19), held
## for its go (LD13) so the stack forms and holds in its slots instead of going in, and the rest of
## the AI is on; Von is down (scripted), so what each member does is
## the order's. Every member must, by its own measure:
## - end in the slot it claimed: its running entry is through the order's doorway, in the slot of
##   its latest `claim` on the radio, in its stack phase, within `SLOT_REACH` of that slot's point
##   (`debug_entry()["stack_point"]`);
## - never take the back of the stack (its claimed slot rising on the radio once it has settled) nor
##   give the claim up (`abort`). The stack moves up: a member in its slot steps into a lower slot
##   of its own file (its side of the door) whose holder is not there yet and takes that number, and
##   the latecomer takes the slot it freed, both radioed as claims. So a rise is allowed only as the
##   other half of a move-up (`move_ups`, read off the claims): a teammate claimed the member's old
##   number, on the same side, coming down from exactly the number the member rises to, within
##   `MOVE_UP_S`. Any other rise (the slot behind the last, `_to_back`) still fails; the check's
##   line lists each move-up allowed;
## - each move-up seen must be a real one (`_check_move_up`, a check of its own): the mover stood in
##   its own slot (`SLOT_REACH`) when it moved, its new slot is lower and on its own file, and it
##   ends in it (or in the slot of a later move-up of its own);
## - get there within its route's walking time (over its `movement.walk_speed()`) plus `SLACK_S`,
##   timed from where it stood when the order came; a member whose walk met the entry guard (D4: it
##   clears an uncleared room it passes before it claims a slot) is timed from the end of its last
##   such detour instead, from where it stood then. A detour is read off what the AI publishes: the
##   member's running entry (`debug_entry()`) is through another doorway or into another room than
##   the order's (its `opening` / `into`); while it lasts the member is not in the order's slot. The
##   route is the one that keeps out of both the room being entered (the order's `into`) and the
##   doorway's view, however long (an ordered member never walks through either, so no
##   `View.AVOID_RATIO` cap): `keep_out_route`, an avoid map carved with the test's own view polygon
##   and that room's rect, from where it is timed from, whenever that route reaches the slot (within
##   `ROUTE_REACH`); only when none does (it is timed from inside one of them, or the route ends
##   short) the plain route (`NavBuilder.route`). The check's line names the route used and its
##   length;
## - never walk the doorway's view nor cross the door's front close in (E1, E18) when a way round
##   exists: a route that keeps out of the view (the test's own copy, `door_view_probe.gd`, carved
##   into an avoid map, `NavBuilder.avoid_map`) no longer than `View.AVOID_RATIO` x the plain route
##   + `View.AVOID_SLACK`;
## - never bump a teammate (`bump_probe.gd`).
## The doorway is a frame of the test's own (`slots_probe.gd` `frame`), read from the house's rooms
## and openings.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")
const Bump := preload("res://tests/_ai/bump_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
## How close (px) a member stands to its claimed slot to be in it.
const SLOT_REACH := 6.0
## The slack (s) on a member's walking time to its slot.
const SLACK_S := 8.0
## How close (px) to the slot a route that keeps out of the room being entered and the doorway's
## view must end to reach it.
const ROUTE_REACH := 20.0
## A member's claimed slot may still settle (two claims on the same frame) this long (s) after its
## first claim.
const SETTLE_S := 1.0
## How far apart (s) on the radio the two claims of a move-up may be (the mover's lower number, the
## latecomer's rise to the one freed).
const MOVE_UP_S := 1.0
## How long (s) every member must have stood in its slot before the watch ends.
const HOLD_S := 2.0
## The longest the watch runs (s) after the order, whatever the routes say.
const WATCH_CAP := 120.0
## How long (s) a member may stand in the doorway's view all told (the agent cuts a corner by a few
## px).
const VIEW_SLACK_S := 0.25
## How far (px) out from the stack side's wall plane, and past the jamb along the wall, the leader's
## click lies on the side it orders (a click within the doorway's width of its centre names it,
## `Squad.resolve`).
const CLICK_OUT := 30.0
const CLICK_PAST := 15.0


## The test's own frame of going through the opening at `door_pos` into room `into`, read from the
## test world's house.
static func frame(t: TestContext, door_pos: Vector2, into: String) -> Dictionary:
	for o in t.world.openings:
		if (o["pos"] as Vector2).distance_to(door_pos) < 1.0:
			return Slots.frame(o, into, t.rooms)
	return {}


## Where the leader clicks to order a stack on side `side` (1 / -1 along the wall) of frame `f`: on
## the stack side, past the jamb.
static func click(f: Dictionary, side: int) -> Vector2:
	return ((f["pos"] as Vector2) + (f["out"] as Vector2) * CLICK_OUT
			+ (f["along"] as Vector2) * side * (float(f["width"]) * 0.5 + CLICK_PAST))


## Order the members (invader actors: the keys of `starts`, in order) to stack on frame `f`,
## starting on side `side`, held for the go, through the squad led by the puppet `lead` (the
## setup's `s.squads`); watch them form the stack; check each member as above (D4, D20). `starts`
## names each member's starting place for the messages (`{ id: "near along the wall" }`).
static func run(
	t: TestContext,
	f: Dictionary,
	lead: StringName,
	side: int,
	starts: Dictionary,
) -> void:
	var ids: Array = starts.keys()
	# The watch's record: where each member started, the order's time, the samples, and per member
	# the sim time it last came to stand in its claimed slot (INF while it is not in it), the first
	# such time (since its last detour ended), and its entry-guard detours
	# ([{ opening, into, start, end, from, paused }], `end` and `from` INF while one runs).
	var rec := {
		"starts": starts, "start": {}, "t0": 0.0, "samples": [], "arrived": {}, "ever": {},
		"detours": {},
	}
	if not _order_stack(t, f, lead, side, rec):
		return
	rec["t0"] = t.time
	var stop := func() -> bool: return _sample(t, f, ids, rec)
	var seen: Dictionary = await Bump.watch(t, ids, WATCH_CAP + 1.0, stop)
	rec["map"] = t.world.get_world_2d().navigation_map
	rec["moves"] = move_ups(t, ids, String(f["id"]))
	for id in ids:
		await _check_member(t, f, id, rec)
	for m: Dictionary in rec["moves"]:
		_check_move_up(t, f, m, rec["moves"], rec["samples"])
	var bumps: Array = seen["bumps"]
	t.check(
		bumps.is_empty(),
		"nobody bumps a teammate on the way to the stack (%d bump(s): %s)"
			% [bumps.size(), Bump.describe(bumps)],
	)


## `run`'s set-up and order: `require` the doorway, the squad led by `lead`, and the stack order its
## squad posts for the members (`rec.starts`' keys) on side `side` of frame `f`, noting where each
## stood then in `rec.start`; false when one failed.
static func _order_stack(
		t: TestContext, f: Dictionary, lead: StringName, side: int, rec: Dictionary
) -> bool:
	if not t.require(not f.is_empty(), "the doorway is in the house (test set-up)"):
		return false
	var squad := t.squad(&"invader")
	if not t.require(
			squad != null and squad.leader() == t.actor(lead),
			"set-up: the squad is declared (s.squads) and led by %s" % lead,
	):
		return false
	var ids: Array = rec["starts"].keys()
	var members: Array = ids.map(func(id): return t.actor(id))
	for id in ids:
		rec["start"][id] = t.actor(id).global_position
	var order := Order.stack_order(squad, members, click(f, side), "quiet", true)
	if not t.require(
			not order.is_empty(),
			"the squad posts the stack order on %s (issue)" % f["id"],
	):
		return false
	return t.require(
		String(order.get("opening", "")) == String(f["id"])
			and String(order.get("into", "")) == String(f["room_key"]),
		"set-up: the order names %s into the %s (it named %s into %s)"
			% [f["id"], f["room_key"], order.get("opening"), order.get("into")],
	)


## One frame of `run`'s watch of the members `ids` on frame `f`, recorded in `rec`; whether the
## watch is over (every member has stood in its slot `HOLD_S`, or `WATCH_CAP` is out).
static func _sample(t: TestContext, f: Dictionary, ids: Array, rec: Dictionary) -> bool:
	# slots: id -> { slot, spot, side } of its running entry at the order's doorway ({} in a detour
	# or with none)
	var sample := { "t": t.time, "pos": {}, "facing": {}, "slots": {} }
	var all_in := true
	var latest := -INF
	for id in ids:
		var arrived := _sample_member(t, f, id, rec, sample)
		if arrived == INF:
			all_in = false
		else:
			latest = maxf(latest, arrived)
	(rec["samples"] as Array).append(sample)
	return (all_in and t.time - latest >= HOLD_S) or t.time - float(rec["t0"]) >= WATCH_CAP


## Member `id`'s part of this frame's `sample` (and of `rec`): the sim time it came to stand in its
## claimed slot, or INF when it is not in it.
static func _sample_member(
		t: TestContext, f: Dictionary, id: StringName, rec: Dictionary, sample: Dictionary
) -> float:
	var a := t.actor(id)
	sample["pos"][id] = a.global_position
	sample["facing"][id] = a.facing
	var e := Entry.entry(Entry.brain(t, id))
	var spot = e.get("stack_point", Vector2.INF)
	sample["slots"][id] = ({}
			if e.is_empty() or _detour(f, e)
			else {
				"slot": int(e.get("slot", 0)), "side": int(e.get("side", 0)),
				"spot": spot if spot is Vector2 else Vector2.INF,
			})
	_track_detour(t, f, id, e, rec)
	var inside: bool = (not _detour(f, e)
			and String(e.get("phase", "")) == "stack"
			and spot is Vector2
			and spot != Vector2.INF
			and a.global_position.distance_to(spot) <= SLOT_REACH)
	var arrived: Dictionary = rec["arrived"]
	if not inside:
		arrived[id] = INF
		return INF
	if float(arrived.get(id, INF)) == INF:
		arrived[id] = t.time
	if not rec["ever"].has(id):
		rec["ever"][id] = t.time
	return float(arrived[id])


## Keeps member `id`'s entry-guard detours in `rec` up to date with its running entry `e`.
static func _track_detour(
		t: TestContext, f: Dictionary, id: StringName, e: Dictionary, rec: Dictionary
) -> void:
	var detour := _detour(f, e)
	var detours: Dictionary = rec["detours"]
	var runs: Array = detours.get(id, [])
	var running: bool = not runs.is_empty() and float(runs[runs.size() - 1]["end"]) == INF
	if detour and not running:
		runs.append({
			"opening": String(e.get("opening", "")), "into": String(e.get("into", "")),
			"start": t.time, "end": INF, "from": Vector2.INF,
			"paused": _order_paused(t, id),
		})
		detours[id] = runs
	elif detour:
		# One detour may run straight into the next: the latest.
		runs[runs.size() - 1]["opening"] = String(e.get("opening", ""))
		runs[runs.size() - 1]["into"] = String(e.get("into", ""))
	elif running:
		runs[runs.size() - 1]["end"] = t.time
		runs[runs.size() - 1]["from"] = t.actor(id).global_position
	if detour:
		rec["ever"].erase(id)   # Timed from the detour's end: an earlier arrival does not count.


## Whether `e` (a member's `debug_entry()`) is an entry-guard detour of the stack on frame `f`: an
## entry through another doorway or into another room than the order's.
static func _detour(f: Dictionary, e: Dictionary) -> bool:
	return (not e.is_empty()
			and (String(e.get("opening", "")) != String(f["id"])
					or String(e.get("into", "")) != String(f["room_key"])))


## Whether member `id`'s order leaf is paused behind a detour of the entry guard, as the AI says
## (`debug_state()["order"]["paused"]`).
static func _order_paused(t: TestContext, id: StringName) -> bool:
	var b := Entry.brain(t, id)
	return (b != null
			and b.has_method("debug_state")
			and bool((b.debug_state().get("order", {}) as Dictionary).get("paused", false)))


## Rule 9 for one member `id` of `run`'s record `rec`: it started at `rec.start[id]`
## (`rec.starts[id]`, in words) when the order came at `rec.t0` and first stood in its slot at
## `rec.ever[id]` (INF: never; since its last detour ended), its entry-guard detours
## `rec.detours[id]`, the stack's move-ups `rec.moves` (`move_ups`).
static func _check_member(t: TestContext, f: Dictionary, id: StringName, rec: Dictionary) -> void:
	var e := Entry.entry(Entry.brain(t, id))
	var spot = e.get("stack_point", Vector2.INF)
	var label := _label(rec, id)
	_check_in_claimed_slot(t, f, id, label, e)
	var claims := Entry.calls(t, "", id).filter(
		func(c): return String(c.get("opening", "")) == String(f["id"]),
	)
	var aborts := claims.filter(func(c): return String(c.get("entry_step", "")) == "abort")
	t.check(
		aborts.is_empty(),
		"%s never gives its claim up (abort radioed %d time(s))" % [label, aborts.size()],
	)
	_check_never_back(t, f, id, label, rec["moves"])
	if not (spot is Vector2 and spot != Vector2.INF):
		return
	var timing := _timed_from(t, f, id, rec)
	timing["to"] = spot
	await _check_walk_time(t, f, id, rec, timing)
	await _check_view(t, f, id, rec, spot)


## Member `id` and its starting place in words (`rec.starts`), for a message.
static func _label(rec: Dictionary, id: StringName) -> String:
	return "%s (%s)" % [id, String(rec["starts"].get(id, ""))]


## `_check_member`'s check that member `id` (`label`, its running entry `e`) ends in the slot it
## claimed.
static func _check_in_claimed_slot(
		t: TestContext, f: Dictionary, id: StringName, label: String, e: Dictionary
) -> void:
	var a := t.actor(id)
	var spot = e.get("stack_point", Vector2.INF)
	var phase := String(e.get("phase", ""))
	var in_slot: bool = (spot is Vector2
			and spot != Vector2.INF
			and a.global_position.distance_to(spot) <= SLOT_REACH
			and phase == "stack")
	var said := _latest_claim(t, id, String(f["id"]))
	var claimed: bool = (not said.is_empty()
			and String(e.get("opening", "")) == String(f["id"])
			and int(e.get("slot", 0)) == int(said["slot"]))
	var latest := (
		"slot %d at %.1f s" % [said["slot"], said["at"]]
			if not said.is_empty()
			else "none radioed at %s" % f["id"]
	)
	var off: float = (a.global_position.distance_to(spot)
			if spot is Vector2 and spot != Vector2.INF
			else INF)
	t.check(
		in_slot and claimed,
		("%s ends in the slot it claimed (its latest claim: %s; at %s, its entry through %s, slot "
				+ "%s at %s, phase %s, %.0f px off)")
			% [
				label, latest, str(a.global_position.round()), e.get("opening", "-"),
				str(e.get("slot")),
				str(spot.round()) if spot is Vector2 and spot != Vector2.INF else "-", phase, off,
			],
	)


## `_check_member`'s check that member `id` (`label`) never takes the back of the stack: each rise
## of its slot is the other half of one of the stack's move-ups `moves`.
static func _check_never_back(
		t: TestContext, f: Dictionary, id: StringName, label: String, moves: Array
) -> void:
	var backs: Array = []     # its rises that are no move-up's other half
	var halves: Array = []    # its rises that are, as the move-up's words
	for r: Dictionary in _slot_changes(t, id, String(f["id"])):
		if int(r["to"]) <= int(r["from"]):
			continue
		var m := _move_up_of(moves, id, r)
		if m.is_empty():
			backs.append("%d -> %d at %.1f s" % [r["from"], r["to"], r["at"]])
			continue
		halves.append("%s moved up %d -> %d at %.1f s, it took %d at %.1f s"
				% [m["mover"], m["from"], m["to"], m["at"], m["from"], m["late_at"]])
	var own: Array = moves.filter(func(m): return m["mover"] == id).map(func(m): return (
		"%d -> %d at %.1f s (%s took %d)" % [m["from"], m["to"], m["at"], m["late"], m["from"]]
	))
	t.check(
		backs.is_empty(),
		("%s never takes the back of the stack (its slot rose: %s; rose as the other half of a "
				+ "move-up: %s; moved up itself: %s)")
			% [
				label, ", ".join(backs) if not backs.is_empty() else "never",
				", ".join(halves) if not halves.is_empty() else "never",
				", ".join(own) if not own.is_empty() else "never",
			],
	)


## Where and when member `id`'s walk to its slot is timed from: `{ from, at, since }`, where it
## stood when the order came, or the end of its last entry-guard detour (`at` INF while that still
## runs); `since` says which for the message ("" for the order).
static func _timed_from(
	t: TestContext,
	f: Dictionary,
	id: StringName,
	rec: Dictionary,
) -> Dictionary:
	var detours: Array = rec["detours"].get(id, [])
	if detours.is_empty():
		return { "from": rec["start"][id], "at": float(rec["t0"]), "since": "" }
	var last: Dictionary = detours[detours.size() - 1]
	var other_claims := Entry.calls(t, "claim", id).filter(func(c): return (
		String(c.get("opening", "")) != String(f["id"])
			or String(c.get("into", "")) != String(f["room_key"])
	))
	var since := ((" from the end of its last entry-guard detour (%d detour(s), %d claim(s) "
				+ "radioed elsewhere; the last through %s into the %s, from %.1f s; the "
				+ "order paused behind it: %s at its start, %s now)")
			% [
				detours.size(),
				other_claims.size(),
				last["opening"],
				last["into"],
				last["start"],
				last["paused"],
				_order_paused(t, id),
			])
	var timed_from: Vector2 = last["from"]
	var timed_at := float(last["end"])
	if timed_at != INF:
		since = (since.trim_suffix(")")
				+ "; it ended at %.1f s at %s)" % [timed_at, str(timed_from.round())])
	return { "from": timed_from, "at": timed_at, "since": since }


## `_check_member`'s check that member `id` is in its slot (`timing.to`) within its route's walking
## time + `SLACK_S`, timed as `timing` (`_timed_from`) says: the route that keeps out of the room
## being entered and the doorway's view when one reaches the slot, else the plain route.
static func _check_walk_time(
		t: TestContext, f: Dictionary, id: StringName, rec: Dictionary, timing: Dictionary
) -> void:
	var label := _label(rec, id)
	var timed_at: float = timing["at"]
	if not _detour_ended(t, label, timing):
		return
	var a := t.actor(id)
	var map: RID = rec["map"]
	var kept := await keep_out_route(t, f, timing["from"], timing["to"], map)
	var route_len: float
	var route_kind: String
	if kept.has("path"):
		route_len = NavBuilder.path_length(kept["path"])
		route_kind = "the way round the %s and the doorway's view" % f["room_key"]
	else:
		route_len = NavBuilder.path_length(NavBuilder.route(map, timing["from"], timing["to"]))
		route_kind = "the plain route: %s" % kept["why"]
	var budget := route_len / maxf(float(a.movement.walk_speed()), 1.0) + SLACK_S
	var took := float(rec["ever"].get(id, INF)) - timed_at
	t.check(
		took <= budget,
		("%s is in its slot within its route's walking time + %.0f s%s (%.1f s; route %.0f "
				+ "px, %s, at %.0f px/s: %.1f s allowed)")
			% [
				label,
				SLACK_S,
				timing["since"],
				took,
				route_len,
				route_kind,
				a.movement.walk_speed(),
				budget,
			],
	)


## `_check_walk_time`'s failed check when the detour its walk is timed from (`timing`) never ended;
## true when it did.
static func _detour_ended(t: TestContext, label: String, timing: Dictionary) -> bool:
	if float(timing["at"]) != INF:
		return true
	t.check(
		false,
		("%s is in its slot within its route's walking time + %.0f s%s: the detour never "
				+ "ended (still running when the watch ended at %.1f s)")
			% [label, SLACK_S, timing["since"], t.time],
	)
	return false


## `_check_member`'s checks that member `id` never walks the doorway's view nor crosses the door's
## front close in on its way to `spot`, when a way round exists from where it started.
static func _check_view(
		t: TestContext, f: Dictionary, id: StringName, rec: Dictionary, spot: Vector2
) -> void:
	var label := _label(rec, id)
	var round_way := await way_round(t, f, rec["start"][id], spot, rec["map"])
	if round_way != "":
		t.check(true, "%s: %s" % [label, round_way])
		return
	var in_view := View.time_in_view(t, rec["samples"], id, f)
	t.check(
		in_view <= VIEW_SLACK_S,
		"%s never walks the doorway's view (%.2f s in it; a way round exists)" % [label, in_view],
	)
	var cross := front_crossings(t, f, rec["samples"], id)
	t.check(
		cross.is_empty(),
		"%s never crosses the door's front close in (a way round exists): %s"
			% [label, ", ".join(cross)],
	)


## Every change of `id`'s claimed slot at doorway `opening` on the radio after it settled
## (`SETTLE_S` after its first claim), as `{ from, to, at, step, side, side_before }`: the entry
## step that first carried the new number (a claim, or another step), the side of the door that call
## names and the side of the call before it.
static func _slot_changes(t: TestContext, id: StringName, opening: String) -> Array:
	var who := t.actor(id)
	var out: Array = []
	var first := INF
	var base := 0
	var base_side := 0
	for ev: Dictionary in t.events:
		var d: Dictionary = ev["data"]
		if (ev["topic"] != &"callout"
				or d.get("speaker") != who
				or String(d.get("opening", "")) != opening
				or String(d.get("entry_step", "")) == ""):
			continue
		var slot := int(d.get("slot", 0))
		var side := int(d.get("side", 0))
		if first == INF:
			first = float(ev["time"])
		if float(ev["time"]) - first > SETTLE_S and slot != base:
			out.append({
				"from": base,
				"to": slot,
				"at": float(ev["time"]),
				"step": String(d.get("entry_step", "")),
				"side": side,
				"side_before": base_side,
			})
		base = slot
		base_side = side
	return out


## `id`'s latest claim at doorway `opening` on the radio (its latest `claim` step), as
## `{ slot, at }`, or {} when it radioed none.
static func _latest_claim(t: TestContext, id: StringName, opening: String) -> Dictionary:
	var who := t.actor(id)
	var out := {}
	for ev: Dictionary in t.events:
		var d: Dictionary = ev["data"]
		if (ev["topic"] == &"callout"
				and d.get("speaker") == who
				and String(d.get("opening", "")) == opening
				and String(d.get("entry_step", "")) == "claim"):
			out = { "slot": int(d.get("slot", 0)), "at": float(ev["time"]) }
	return out


## The stack's move-ups at doorway `opening` among the members `ids`, read off their claims on the
## radio (E2: a member in its slot steps into a lower slot of its own file whose holder is not there
## yet, and the latecomer takes the slot it freed): a mover's claim of a lower number on the same
## side of the door (`from` -> `to`), paired with a teammate's claim, within `MOVE_UP_S` of it, that
## rises from exactly `to` to exactly `from` on that side. Each
## `{ mover, late, from, to, at, late_at, side }`; a rise pairs with one claim.
static func move_ups(t: TestContext, ids: Array, opening: String) -> Array:
	var changes := {}
	for id in ids:
		changes[id] = _slot_changes(t, id, opening)
	var out: Array = []
	for late in ids:
		for r: Dictionary in changes[late]:
			if r["step"] != "claim" or int(r["to"]) <= int(r["from"]):
				continue
			var m := _pair_rise(changes, ids, late, r)
			if not m.is_empty():
				out.append(m)
	return out


## The move-up whose other half is `late`'s rise `r` (`_slot_changes`), read off the members' slot
## changes `changes` (id -> `_slot_changes`; the members `ids` tried in turn): the first mover's
## claim of exactly the number `r` rose from, coming down from exactly the number it rose to, on
## the same side and within `MOVE_UP_S` of it; {} when none is.
static func _pair_rise(changes: Dictionary, ids: Array, late: Variant, r: Dictionary) -> Dictionary:
	for mover in ids:
		if mover == late:
			continue
		for d: Dictionary in changes[mover]:
			if not _halves_of_move_up(d, r):
				continue
			return {
				"mover": mover, "late": late, "from": int(d["from"]), "to": int(d["to"]),
				"at": float(d["at"]), "late_at": float(r["at"]), "side": int(d["side"]),
				"side_before": int(d["side_before"]),
			}
	return {}


## Whether the slot changes `d` (a mover's claim) and `r` (a latecomer's rise) are the two halves of
## one move-up.
static func _halves_of_move_up(d: Dictionary, r: Dictionary) -> bool:
	return (d["step"] == "claim"
			and int(d["to"]) == int(r["from"])
			and int(d["from"]) == int(r["to"])
			and int(d["side"]) == int(r["side"])
			and absf(float(d["at"]) - float(r["at"])) <= MOVE_UP_S)


## The move-up among `moves` whose other half is `late`'s slot change `r` (`_slot_changes`), or {}.
static func _move_up_of(moves: Array, late: StringName, r: Dictionary) -> Dictionary:
	for m: Dictionary in moves:
		if (m["late"] == late
				and int(m["from"]) == int(r["to"])
				and int(m["to"]) == int(r["from"])
				and float(m["late_at"]) == float(r["at"])):
			return m
	return {}


## Whether move-up `m` (`move_ups`) is a real one: its mover stood in its own slot (within
## `SLOT_REACH` of the point its entry gave that slot, in the last sample before the claim), its new
## slot is lower and on its own file (the same side of the door as the slot it left), and it ends in
## it (its running entry at the order's doorway in that slot, in its stack phase, within
## `SLOT_REACH`), or in the slot of a later move-up of its own, each checked on its own.
static func _check_move_up(
	t: TestContext,
	f: Dictionary,
	m: Dictionary,
	moves: Array,
	samples: Array,
) -> void:
	var mover: StringName = m["mover"]
	var stand := _stood(f, m, samples)
	var lower: bool = int(m["to"]) < int(m["from"]) and int(m["side"]) == int(m["side_before"])
	var last := _last_slot(m, moves)
	var a := t.actor(mover)
	var e := Entry.entry(Entry.brain(t, mover))
	var spot = e.get("stack_point", Vector2.INF)
	var off_end: float = (a.global_position.distance_to(spot)
			if spot is Vector2 and spot != Vector2.INF
			else INF)
	var ends: bool = (String(e.get("opening", "")) == String(f["id"])
			and int(e.get("slot", 0)) == last
			and String(e.get("phase", "")) == "stack"
			and off_end <= SLOT_REACH)
	t.check(
		stand["standing"] and lower and ends,
		("%s's move-up %d -> %d at %.1f s (%s took %d) is a real one: it stood in its slot (%s), "
				+ "the new slot is lower on its own file (side %d, from side %d), and it ends in "
				+ "%s (slot %s through %s, phase %s, %.0f px off)")
			% [
				mover, m["from"], m["to"], m["at"], m["late"], m["from"], stand["stood"], m["side"],
				m["side_before"],
				"slot %d" % last if last == int(m["to"]) else "slot %d, its later move-up's" % last,
				str(e.get("slot")), e.get("opening", "-"), e.get("phase", "-"), off_end,
			],
	)


## Whether the mover of move-up `m` stood in its own slot when it moved, by the last of `samples`
## before the claim: `{ standing, stood }` (`stood`: what it was doing, in words).
static func _stood(f: Dictionary, m: Dictionary, samples: Array) -> Dictionary:
	var mover: StringName = m["mover"]
	var before := {}
	for s: Dictionary in samples:
		if float(s["t"]) >= float(m["at"]):
			break
		before = s
	if before.is_empty():
		return { "standing": false, "stood": "no sample before it" }
	var held: Dictionary = (before["slots"] as Dictionary).get(mover, {})
	var at: Vector2 = before["pos"][mover]
	if held.is_empty():
		return {
			"standing": false,
			"stood": "its entry was not at %s at %.1f s" % [f["id"], before["t"]],
		}
	var off := at.distance_to(held["spot"]) if held["spot"] != Vector2.INF else INF
	return {
		"standing": int(held["slot"]) == int(m["from"]) and off <= SLOT_REACH,
		"stood": "at %.1f s it held slot %d, %.0f px off its point" % [
			before["t"],
			held["slot"],
			off,
		],
	}


## The slot the mover of move-up `m` ends the stack's move-ups `moves` in: `m`'s new slot, or that
## of its later move-ups from it in turn.
static func _last_slot(m: Dictionary, moves: Array) -> int:
	var last := int(m["to"])
	var later := true
	while later:
		later = false
		for n: Dictionary in moves:
			if (n["mover"] == m["mover"]
					and int(n["from"]) == last
					and float(n["at"]) > float(m["at"])):
				last = int(n["to"])
				later = true
				break
	return last


## The times member `id` crossed the door's axis close in: on its outer side, at a point inside the
## doorway's view (`View.in_view`, walls respected, no edge margin: the crossing itself, however
## fast), as "at t s, n px out".
static func front_crossings(t: TestContext, f: Dictionary, samples: Array, id: StringName) -> Array:
	var out: Array = []
	for i in range(1, samples.size()):
		var a: Vector2 = samples[i - 1]["pos"][id]
		var b: Vector2 = samples[i]["pos"][id]
		var la := Entry.lateral(f, a)
		var lb := Entry.lateral(f, b)
		if la == 0.0 or signf(la) == signf(lb):
			continue
		var at := a.lerp(b, la / (la - lb))
		if Entry.outward(f, at) > 0.0 and View.in_view(t, f, at, 0.0):
			out.append("at %.1f s, %.0f px out" % [samples[i]["t"], Entry.outward(f, at)])
	return out


## "" when a way round the doorway's view exists from `from` to `to` (the plain route keeps out of
## it, or a route that keeps out of it is no longer than `View.AVOID_RATIO` x the plain one +
## `View.AVOID_SLACK`), else why none (the checks on the view are then left out).
static func way_round(
	t: TestContext,
	f: Dictionary,
	from: Vector2,
	to: Vector2,
	map: RID,
) -> String:
	var plain := NavBuilder.route(map, from, to)
	var plain_len := NavBuilder.path_length(plain)
	var poly := View.polygon(f)
	if Geometry2D.is_point_in_polygon(from, poly) and Entry.outward(f, from) > 0.0:
		return "starts in the doorway's view: no way round asked of it"
	if not _route_in_view(t, f, [from] + Array(plain)):
		return ""
	var region := NavBuilder.planning_region(map)
	if region == null:
		return "no planning region to measure a way round on"
	var avoid := NavBuilder.avoid_map(region, "reach_test_%s>%s" % [f["id"], f["room_key"]], [poly])
	var waited := 0
	while not NavBuilder.ready(avoid) and waited < 240:
		await t.frames(1)
		waited += 1
	if not NavBuilder.ready(avoid):
		return "the avoid map never came up: no way round measured"
	var detour := NavBuilder.route(avoid, from, to)
	var round_len := NavBuilder.path_length(detour)
	if detour.is_empty() or detour[detour.size() - 1].distance_to(to) > 20.0:
		return "no route round the doorway's view reaches the slot"
	if round_len > View.AVOID_RATIO * plain_len + View.AVOID_SLACK:
		return (("the way round the doorway's view (%.0f px) is longer than %.1f x the plain route "
					+ "(%.0f px) + %.0f px")
				% [round_len, View.AVOID_RATIO, plain_len, View.AVOID_SLACK])
	return ""


## The route from `from` to `to` that keeps out of both the room being entered (frame `f`'s `room`)
## and the doorway's view (the test's own polygon), however long: measured on an avoid map carved
## with the two (`NavBuilder.avoid_map`), as `way_round` carves the view. `{ path }` when one
## reaches `to` (within `ROUTE_REACH`) and keeps out of both, else `{ why }` (why none, in words):
## it starts in one of them, or the map never came up, or its route ends short of `to` or still runs
## through them.
static func keep_out_route(
	t: TestContext,
	f: Dictionary,
	from: Vector2,
	to: Vector2,
	map: RID,
) -> Dictionary:
	var room: Rect2 = f["room"]
	var view := View.polygon(f)
	if room.has_point(from):
		return {
			"why": "it is timed from inside the %s, so no route keeps out of it" % f["room_key"],
		}
	if Geometry2D.is_point_in_polygon(from, view) and Entry.outward(f, from) > 0.0:
		return { "why": "it is timed from inside the doorway's view, so no route keeps out of it" }
	var region := NavBuilder.planning_region(map)
	if region == null:
		return { "why": "no planning region to measure a way round on" }
	var room_poly := PackedVector2Array([
		room.position,
		Vector2(room.end.x, room.position.y),
		room.end,
		Vector2(room.position.x, room.end.y),
	])
	var avoid := NavBuilder.avoid_map(
		region,
		"reach_budget_%s>%s" % [f["id"], f["room_key"]],
		[view, room_poly],
	)
	var waited := 0
	while not NavBuilder.ready(avoid) and waited < 240:
		await t.frames(1)
		waited += 1
	if not NavBuilder.ready(avoid):
		return { "why": "the avoid map never came up" }
	var path := NavBuilder.route(avoid, from, to)
	if path.is_empty() or path[path.size() - 1].distance_to(to) > ROUTE_REACH:
		var off := path[path.size() - 1].distance_to(to) if not path.is_empty() else INF
		var why := (("no route round the %s and the doorway's view reaches the slot (it ends %.0f "
				+ "px off)") % [f["room_key"], off])
		return { "why": why }
	if _route_through(f, view, Array(path)):
		return {
			"why": "the avoid map's route still runs through the %s or the doorway's view"
				% f["room_key"],
		}
	return { "path": path }


## Whether the polyline `pts` passes into room rect `f["room"]` or into the polygon `view` on the
## door's outer side (sampled every 8 px; 2 px in, so a point on an edge does not count).
static func _route_through(f: Dictionary, view: PackedVector2Array, pts: Array) -> bool:
	var room: Rect2 = (f["room"] as Rect2).grow(-2.0)
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var steps := maxi(int(a.distance_to(b) / 8.0), 1)
		for k in steps + 1:
			var p := a.lerp(b, float(k) / float(steps))
			if (room.has_point(p)
					or (Geometry2D.is_point_in_polygon(p, view) and Entry.outward(f, p) > 2.0)):
				return true
	return false


## Whether the polyline `pts` passes through the doorway's view (sampled every 8 px).
static func _route_in_view(t: TestContext, f: Dictionary, pts: Array) -> bool:
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var steps := maxi(int(a.distance_to(b) / 8.0), 1)
		for k in steps + 1:
			if View.in_view(t, f, a.lerp(b, float(k) / float(steps))):
				return true
	return false
