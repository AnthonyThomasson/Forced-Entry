extends GameTest

## Rule 6's dead end (ticket #65 round 2, `docs/tactical-entry.md` E20, `docs/leadership.md` LD7): a stack forming in a dead-end small room
## (its only doorway the one being entered, no wall beside the door, so nowhere for a tail to hold) takes only as many slots as its open
## floor holds at the normal spacing (44 px), never squeezed; the members past that get no slot, hold where they are, and their order shows
## `refused` (no room) in `Squad.view()`.
##
## A hand-laid layout, because no generated plan has a dead end that holds fewer than six: the slot sweep (`ai/entry/stack_slots_sweep`, 11
## plans x 3 seeds) finds twelve dead-end ways in (micro_flat kitchenette > studio on all three seeds, office_loft home_office > great_room
## #1 and #2, bungalow laundry_room > kitchen #2 and #3 and bathroom > bedroom #3, starter_home bathroom > bedroom #1 and #2,
## open_plan_home bathroom > bedroom #1 and #2), and its own packing finds each holds six (rooms 200 to 380 px across, where furniture only
## blocks every spot against the wall), while a stack is at most six. So: an office (500 x 300) and, east of it, a closet (100 x 100) whose
## only doorway is an 80 px opening in the middle of their shared wall: ten px of wall either side of it, so no spot against the wall. The
## test's own packing (`Slots.dead_end_capacity`: the most points of a 4 px grid, 44 px apart, that keep the open-floor rules) counts what
## the closet holds; the set-up requires it to be fewer than the four ordered.
##
## The four members start in the office, just outside the closet's doorway, off its axis: inside the closet's floor (about 60 x 60 px past
## its walls) four bodies fit only touching, and the ones walking to the slots would shove the ones that must stay where they are. They have
## to cross the doorway to reach the stack side, which is the same case (the stack still forms in the closet, and the extras hold where they
## stood). The test does not ask which members get the slots (the stack's choice), only how many.
##
## The four are ordered (quiet, held for the leader's go, so the stack forms and holds) to stack on the doorway from the closet's side into
## the office through `Squad.issue`, by a puppet leader at the office's far end; Von is down (scripted), the rest of the AI on. Exactly
## min(4, what the closet holds) members claim a slot, each a slot in the closet that it reaches (6 px) and stands in; each of the others
## never claims a slot, stays within `STAY_PX` of where it started, and its order in `Squad.view()` is still held with the step `refused`.

const Order := preload("res://tests/_ai/order_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Reach := preload("res://tests/_ai/reach_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")

const OFFICE := Rect2(0, 0, 500, 300)
const CLOSET := Rect2(500, 100, 100, 100)
const DOOR := Vector2(500, 150)
## The leader's click: in the closet, past the doorway's south jamb (outside its half-width along the wall, so not a split stack).
const CLICK := Vector2(540, 194)

const IDS := [&"a", &"b", &"c", &"d"]
## How far (px) a member with no slot may drift from where it started.
const STAY_PX := 6.0
## How long (s) the claimants stand in their slots, and the others hold refused, before the watch ends.
const HOLD_S := 2.0
## The longest the watch runs (s) after the order.
const WATCH_CAP := 45.0


func describe() -> Dictionary:
	return {
		"name": "A stack ordered into a dead-end closet too small for it: the extras get no slot and are refused",
		"description": "4 invaders ordered to stack (held) from a 100 x 100 dead-end closet whose open floor holds fewer: exactly as many as it holds claim a slot in it and reach it; each of the others never claims one, stays where it was and shows its order refused in the squad's view (rule 6).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "office", "type": "bedroom", "rect": OFFICE, "floor": "oak_planks" },
		{ "key": "closet", "type": "hallway", "rect": CLOSET, "floor": "oak_planks" },
	], [
		{ "pos": DOOR, "width": 80.0 },
	])
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(440, 60), { "max_health": 1000000.0 })
	s.actor(&"b", &"invader", Vector2(440, 240), { "max_health": 1000000.0 })
	s.actor(&"c", &"invader", Vector2(380, 100), { "max_health": 1000000.0 })
	s.actor(&"d", &"invader", Vector2(380, 200), { "max_health": 1000000.0 })
	s.actor(&"lead", &"puppet", Vector2(40, 150), { "faction": &"invader", "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	var f := Reach.frame(t, DOOR, "office")
	if not t.require(not f.is_empty(), "the doorway is in the layout (test set-up)"):
		return
	var w2d := t.world.get_world_2d()
	var w := Slots.world_of(t.rooms, t.world.openings, w2d.navigation_map, w2d.direct_space_state, t.world.house)
	var kind := Slots.way_kind(w, f)
	if not t.require(kind == "dead_end", "set-up: the closet is a dead end with no spot against the wall (the test's own way kind: %s)" % kind):
		return
	var capacity := Slots.dead_end_capacity(w, f, {})
	var holds := int(capacity["count"])
	var points: Array = (capacity["points"] as Array).map(func(p): return str((p as Vector2).round()))
	if not t.require(holds < IDS.size(), "set-up: the closet holds fewer than the %d ordered (the test's own packing: %d, at %s)" % [IDS.size(), holds, ", ".join(points)]):
		return
	var expect := mini(IDS.size(), holds)
	var squad := Order.raid(t, IDS, &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.3)
	var members: Array = IDS.map(func(id): return t.actor(id))
	var start := {}
	for id in IDS:
		start[id] = t.actor(id).global_position
	var order := Order.stack_order(squad, members, CLICK, "quiet", true)
	if not t.require(not order.is_empty(), "the squad posts the stack order on %s (issue)" % f["id"]):
		return
	if not t.require(String(order.get("opening", "")) == String(f["id"]) and String(order.get("into", "")) == "office",
			"set-up: the order names %s into the office (it named %s into %s)" % [f["id"], order.get("opening"), order.get("into")]):
		return
	var t0 := t.time
	var claimed := {}   # id -> true once it has held a slot at this doorway (its entry or its radio)
	var drift := {}     # id -> the farthest (px) it has been from where it started
	var settled := INF  # when the claimants were last all in their slots and the others refused
	while t.time - t0 < WATCH_CAP:
		await t.frames(1)
		for id in IDS:
			drift[id] = maxf(float(drift.get(id, 0.0)), t.actor(id).global_position.distance_to(start[id]))
			if _claim_of(t, id, String(f["id"])) > 0:
				claimed[id] = true
		var done := claimed.size() == expect
		for id in IDS:
			done = done and (_in_slot(t, id) if claimed.has(id) else _step(squad, t.actor(id)) == "refused")
		if not done:
			settled = INF
		elif settled == INF:
			settled = t.time
		if t.time - settled >= HOLD_S:
			break
	var claimants: Array = IDS.filter(func(id): return claimed.has(id))
	t.check(claimants.size() == expect, "exactly %d of the %d claim a slot, as many as the closet holds (%s claimed: %s; the test's own packing: %s)"
			% [expect, IDS.size(), claimants.size(), str(claimants.map(func(id): return "%s slot %d" % [id, _claim_of(t, id, String(f["id"]))])), ", ".join(points)])
	for id in claimants:
		var spot := Order.stack_point(t, id)
		var a := t.actor(id)
		t.check(spot != Vector2.INF and Slots.in_stack_room(w, f, spot) == "", "%s's slot is in the closet (at %s: %s)"
				% [id, str(spot.round()) if spot != Vector2.INF else "-", Slots.in_stack_room(w, f, spot) if spot != Vector2.INF else "no slot"])
		t.check(_in_slot(t, id), "%s ends in the slot it claimed (at %s, slot at %s, phase %s, %.0f px off)" % [id, str(a.global_position.round()),
				str(spot.round()) if spot != Vector2.INF else "-", String(Entry.entry(Entry.brain(t, id)).get("phase", "")),
				a.global_position.distance_to(spot) if spot != Vector2.INF else INF])
	var extras: Array = IDS.filter(func(id): return not claimed.has(id))
	t.check(extras.size() == IDS.size() - expect, "%d member(s) past the closet's capacity get no slot (%d did not claim one: %s)"
			% [IDS.size() - expect, extras.size(), str(extras)])
	for id in extras:
		var mv := Order.member_view(squad, t.actor(id))
		var held: Dictionary = mv.get("order", {}) if mv.get("order", {}) is Dictionary else {}
		t.check(float(drift.get(id, 0.0)) <= STAY_PX, "%s, with no slot, holds where it was (it moved up to %.0f px from %s)" % [id, float(drift.get(id, 0.0)), str((start[id] as Vector2).round())])
		t.check(String(mv.get("step", "")) == "refused", "%s's order shows refused in the squad's view (step %s)" % [id, str(mv.get("step", ""))])
		t.check(str(held.get("id", "")) == str(order["id"]), "%s still holds the refused order in the squad's view (order %s)" % [id, str(held.get("id", ""))])


## The slot actor `id` holds in the ordered stack (doorway `opening` into the office) now or last radioed there (0: none ever). A claim into
## the closet is not one: before the order, each member's own SEARCH takes the one unsearched room and stacks on the same doorway from the
## office side, which is not the stack under test.
func _claim_of(t: TestContext, id: StringName, opening: String) -> int:
	var e := Entry.entry(Entry.brain(t, id))
	if String(e.get("opening", "")) == opening and String(e.get("into", "")) == "office" and int(e.get("slot", 0)) > 0:
		return int(e["slot"])
	var ordered := func(c): return String(c.get("opening", "")) == opening and String(c.get("into", "")) == "office" and int(c.get("slot", 0)) > 0
	var claims := Entry.calls(t, "", id).filter(ordered)
	return int(claims.back()["slot"]) if not claims.is_empty() else 0


## Whether actor `id` stands in the slot its entry has it claim, in its stack phase (within `Reach.SLOT_REACH`).
func _in_slot(t: TestContext, id: StringName) -> bool:
	var e := Entry.entry(Entry.brain(t, id))
	var spot = e.get("stack_point", Vector2.INF)
	return String(e.get("phase", "")) == "stack" and spot is Vector2 and spot != Vector2.INF \
			and t.actor(id).global_position.distance_to(spot) <= Reach.SLOT_REACH


## The latest order step the squad's view shows for `member` ("" when none).
func _step(squad: Node, member: Node) -> String:
	return String(Order.member_view(squad, member).get("step", ""))
