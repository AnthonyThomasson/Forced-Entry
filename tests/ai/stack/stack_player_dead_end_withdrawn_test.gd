extends GameTest
## E20 for the human (`docs/tactical-entry.md` E16, E20): a slot the human is reserved in a stack
## forming in a dead end is withdrawn, its claim radioed `abort`, once the stack pushes it past what
## the dead end holds; it is never moved to a slot the room does not have.
##
## The world is the dead-end closet of `ai/entry/stack_dead_end_refused` (a 100 x 100 room whose
## only doorway is the one being entered, no wall beside it): the stack forms in the closet, going
## into the office, and holds only as many as the closet's open floor does (the test's own packing,
## `Slots.dead_end_capacity`). The human (a puppet with the human's stack radio, as Main gives it)
## stands in the closet beside the doorway.
##
## Premise: the teammates are puppets radioing their claims on the bus (`Stack.radio`), not AI
## invaders. The human's slot is pushed up only when a teammate's claim sits on that very slot and
## keeps it (the lower instance id), and an AI that has heard the human's claim never claims its
## slot: with AI teammates that takes a claim made before the human's reached it, and the human's
## made before that one reached the human, a race on the radio's heartbeat. The human's stack reads
## only the bus, so a puppet's claim is exactly what it hears from an AI. Each puppet is declared
## before the human (a lower instance id, checked), so its claim keeps the slot.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Reach := preload("res://tests/_ai/reach_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const OFFICE := Rect2(0, 0, 500, 300)
const CLOSET := Rect2(500, 100, 100, 100)
const DOOR := Vector2(500, 150)
## The puppet teammates, in the order they claim: `p1` the point, then one per slot the human is
## pushed from.
const MATES := [&"p1", &"p2", &"p3", &"p4", &"p5", &"p6"]
## How often (s) the puppets repeat their claims (the NPCs' heartbeat is 2 s; a claim lapses after
## 6 s).
const REPEAT := 1.0


func describe() -> Dictionary:
	return {
		"name": "The human's slot in a dead-end stack is withdrawn once pushed past what it holds",
		"description": "The human is reserved a slot in a stack forming in a dead-end closet; "
			+ "teammates (puppets on the radio) take its slot in turn until it is pushed past the "
			+ "last slot the closet holds: it radios abort and its reservation is gone, never a "
			+ "slot the closet lacks.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "office", "type": "bedroom", "rect": OFFICE, "floor": "oak_planks" },
		{ "key": "closet", "type": "hallway", "rect": CLOSET, "floor": "oak_planks" },
	], [
		{ "pos": DOOR, "width": 80.0 },
	])
	s.switch(&"ai.hostile_on_trespass", false)
	for i in MATES.size():
		Stack.human(s, MATES[i], Vector2(60, 40 + 40 * i))
	# In the closet, beside the doorway, out of its funnel: near the stack, not in the doorway.
	Stack.human(s, &"me", Vector2(570, 120))


func run(t: TestContext) -> void:
	var f := Reach.frame(t, DOOR, "office")
	if not t.require(not f.is_empty(), "the doorway is in the layout (test set-up)"):
		return
	var w2d := t.world.get_world_2d()
	var w := Slots.world_of(
		t.rooms, t.world.openings, w2d.navigation_map, w2d.direct_space_state, t.world.house,
	)
	if not t.require(
			Slots.way_kind(w, f) == "dead_end",
			"set-up: the closet is a dead end (the test's own way kind: %s)" % Slots.way_kind(w, f),
	):
		return
	var holds := int(Slots.dead_end_capacity(w, f, {})["count"])
	if not t.require(
			holds >= 2 and holds < MATES.size(),
			"set-up: the closet holds 2 to %d (the test's own packing: %d)" % [
				MATES.size() - 1,
				holds,
			],
	):
		return
	var me := t.actor(&"me")
	for id in MATES:
		if not t.require(
				t.actor(id).get_instance_id() < me.get_instance_id(),
				"set-up: %s has a lower instance id than the human (its claim keeps a slot)" % id,
		):
			return
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	var opening := String(f["id"])
	# The puppets claiming so far: id -> slot.
	var claiming := { MATES[0]: 1 }
	if not t.require(
			await _radioing(t, claiming, opening, func(): return Stack.mine(stack) > 0),
			"the human is reserved a slot in the closet's stack",
	):
		return
	t.expect_eq(Stack.mine(stack), 2, "behind the point: slot 2")
	var aborted := func(): return not Entry.calls(t, "abort", &"me").is_empty()
	for i in range(1, MATES.size()):
		if aborted.call():
			break
		var held := Stack.mine(stack)
		# The next teammate claims the human's slot and keeps it (its lower instance id).
		claiming[MATES[i]] = held
		await _radioing(
			t, claiming, opening, func(): return aborted.call() or Stack.mine(stack) != held,
		)
	if not t.require(aborted.call(), "the human's claim is withdrawn: it radios abort"):
		return
	var claims := Stack.calls_at(t, &"me", opening).filter(
		func(d): return String(d["entry_step"]) != "abort",
	)
	var slots: Array = claims.map(func(d): return int(d.get("slot", 0)))
	t.check(
		slots.all(func(n): return n >= 1 and n <= holds),
		"every slot the human claimed is one the closet holds (1 to %d): %s" % [holds, str(slots)],
	)
	t.expect_eq(
		int(slots[-1]) if not slots.is_empty() else 0,
		holds,
		"it held the closet's last slot when it was pushed past it",
	)
	t.check(Stack.view(stack).is_empty(), "the human has no reservation left")


## Keep the puppets in `claiming` (id -> slot) radioing their claims on `opening` every `REPEAT` s
## until `done` holds or 5 s have passed; whether it held.
func _radioing(t: TestContext, claiming: Dictionary, opening: String, done: Callable) -> bool:
	var start := t.time
	var said := -INF
	while not done.call():
		if t.time - start > 5.0:
			return false
		if t.time - said >= REPEAT:
			said = t.time
			for id in claiming:
				Stack.radio(t, id, opening, "office", claiming[id], 1)
		await t.frames(1)
	return true
