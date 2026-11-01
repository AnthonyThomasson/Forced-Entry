extends GameTest
## Desired (E3, E14, the interim rule until #159): a hostile standing in the gap of an ajar door is
## fought from outside, not walked into. The stack's slot stands off the doorway's view, so the
## invader sees the hostile only when it sets off to cross; from then on nobody crosses while it
## stands in view (E14): the point does not slice the pie at a door that shuts the view, does not
## step into the doorway or the room, and fires at the hostile from outside the wall. A teammate
## that never comes holds the stack's wait (`ready_timeout`, 8 s) until the hostile is in the gap.
## The door is ajar at 45 degrees, hinged on the south jamb so its gap is on the north side, where
## the stack stands; a defender that cannot be killed walks to the gap once the invader is in its
## slot.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const DoorPie := preload("res://tests/_ai/entry_door_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const AJAR := 45.0
## The defender's start, hidden from the stack, and the spot in the gap it walks to.
const HIDDEN := Vector2(760, 120)
const IN_THE_GAP := Vector2(835, 180)
## Test seconds the invader is watched: past its stack's wait, which would have it cross.
const WATCH := 16.0


func describe() -> Dictionary:
	return {
		"name": "Entry fights a hostile in an ajar door's gap from its stack",
		"description": "An invader waiting in its stack at an ajar door sees a defender step into "
			+ "the gap: it fires on it from outside and neither slices the pie nor crosses.",
		"tags": ["ai", "entry", "scripted", "door", "combat"],
		"timeout": 50.0,
	}


func configure(s: TestSetup) -> void:
	DoorPie.configure(s, { "hinge": DoorPie.HINGE_SOUTH, "angle": AJAR })
	Entry.npc(s, &"inv", Vector2(960, 60), { "tuning:entry:ready_timeout": 8.0 })
	s.actor(&"mate", &"puppet", Vector2(1010, 140), { "faction": &"invader" })
	Entry.target(s, &"defender", HIDDEN, Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	var door: Node = t.object(&"back_door")
	var inv := t.actor(&"inv")
	var seen := { "sliced": false, "funnel": false, "stack_at": INF, "ajar": false }
	var frame := Engine.get_physics_frames()
	var end := t.time + WATCH
	while t.time < end:
		# The teammate's claim, radioed again every moment so it stays live: it holds the wait.
		Entry.radio_claim(t.actor(&"mate"), DoorPie.DOOR["id"], "kitchen", Vector2i(2, 1), frame)
		if seen["stack_at"] == INF and Entry.entry(Entry.brain(t, &"inv")).get("phase") == "stack":
			seen["stack_at"] = t.time
			seen["ajar"] = door.angle() < 60.0
			t.puppet(&"defender").walk_to(IN_THE_GAP)
		# The defender's walk may nudge the leaf; the pie is judged while the door shuts the view.
		var shut_view: bool = door.angle() < 60.0
		seen["sliced"] = seen["sliced"] or (shut_view and DoorPie.slicing(t, [&"inv"]))
		seen["funnel"] = seen["funnel"] or Entry.in_funnel(DoorPie.DOOR, inv.global_position)
		await t.seconds(0.25)
	var shot_by_inv := func(d): return d.get("attacker") == inv
	if not t.require(seen["stack_at"] < INF, "premise: the invader reached its stack"):
		return
	if not t.require(seen["ajar"], "premise: the door is ajar when the defender steps in"):
		return
	if not t.require(
			t.happened(&"shot", shot_by_inv),
			"premise: it saw the defender in the gap and fired (act %s)"
				% Entry.brain(t, &"inv").current_act(),
	):
		return
	t.check(not seen["sliced"], "the invader did not slice the pie")
	t.check(not seen["funnel"], "it never stepped into the doorway")
	t.check(
		not Entry.in_room(DoorPie.DOOR, inv.global_position),
		"and is still outside the kitchen (%s)" % inv.global_position.round(),
	)
	var from_outside := t.events_of(&"shot", shot_by_inv).all(
		func(d): return Entry.outward(DoorPie.DOOR, d.get("position", Vector2.ZERO)) > 0.0,
	)
	t.check(from_outside, "every shot left from outside the wall")
