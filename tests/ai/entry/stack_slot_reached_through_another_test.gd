extends GameTest
## Rule 9 (`docs/tactical-entry.md` E2, E21): every member of an ordered stack reaches the slot it
## claimed, also when the slot lies in a pocket of furniture whose only way in runs through the
## spot of the slot before it. A gap: the stack lays slot 4 where only the slot-3 holder's spot
## leads, so the member sent to slot 4 is stopped by the teammate standing in slot 3 and never
## arrives (the slot oracles, `ai/entry/stack_slots_sweep`, judge each slot alone and do not see
## it). A known defect, issue #170. When it is fixed, drop the `gap` tag.
##
## The world is `ai/entry/stack_reach_bungalow_kitchen_door`'s, on the seed that test left (it
## now runs on seed 8, where the scenario it names still arises and every member arrives): the
## bungalow (seed 1, furnished, doors off) doorway from the living room into the kitchen, the
## stack in the living room ordered on its north side, 4 invaders from the same four starts.
## On this seed the 60 px doorways leave the furniture so that slot 4 (-208, -22) lies in a
## pocket under a piece (-221..-189, -100..-70), with pieces beside it, whose only gap leads past
## slot 3 (-179, -58).
##
## Premise (a set-up check of its own, apart from the proof): measured on the test's own navigation
## maps, a route to slot 4 exists from every starting place in the living room and from the street,
## and none does once a body stands in slot 3. The proof is the shared reach probe's, unchanged
## (`tests/_ai/reach_probe.gd`): every member ends in the slot it claimed, never takes the back of
## the stack or aborts, in time, keeping out of the doorway's view and never bumping a teammate.

const Reach := preload("res://tests/_ai/reach_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
## Where each member starts.
const STARTS := {
		&"near": "in the same room, near along the wall, on the order's side",
		&"wrong": "in the same room, on the wrong side of the door",
		&"beyond": "in the room beyond (the kitchen)",
		&"outside": "outside (the street, south of the house)",
}
## The starting places in the living room or the street, from which the premise measures a route to
## slot 4 (the member `beyond` starts in the kitchen).
const ROUTE_STARTS := [Vector2(-150, -250), Vector2(-150, -100), Vector2(100, 90)]
## The stack's size, and the slots the premise names.
const STACK := 4
const POCKET_SLOT := 4
const BLOCKING_SLOT := 3
## A body standing in a slot: the character's radius (px).
const BODY := 14.0
## How close (px) to the slot a route must end to reach it.
const REACH := 20.0


func describe() -> Dictionary:
	return {
		"name": "A stack member reaches a slot whose only way in runs through the slot before it",
		"description": "Issue #170: 4 invaders ordered to stack (held) at the bungalow's kitchen "
			+ "door, seed 1: slot 4 lies in a pocket reached only past slot 3's holder, and the "
			+ "member sent there never arrives, the teammate in slot 3 blocking it (rule 9).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted", "gap"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	# Doors off until #159 makes this family door-aware.
	s.switch(&"worldgen.doors", false)
	s.house(1, "bungalow")
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Vector2(-150, -250), { "max_health": 1_000_000.0 })
	s.actor(&"wrong", &"invader", Vector2(-150, -100), { "max_health": 1_000_000.0 })
	s.actor(&"beyond", &"invader", Vector2(-340, -240), { "max_health": 1_000_000.0 })
	s.actor(&"outside", &"invader", Vector2(100, 90), { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(-900, 300),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var f := Reach.frame(t, Vector2(-230, -170), "kitchen")
	if not t.require(not f.is_empty(), "set-up: the doorway to the kitchen is in the house"):
		return
	if not await _pocket_behind_slot_three(t, f):
		return
	await Reach.run(t, f, &"lead", 1, STARTS)


## Whether slot 4 of the stack (the AI's published layout, side 1) can be walked to from every
## place of `ROUTE_STARTS` on the plain navigation map and from none once a body stands in slot 3
## (an avoid map carved with the body's footprint, `NavBuilder.avoid_map`); a failed check says
## why not.
func _pocket_behind_slot_three(t: TestContext, f: Dictionary) -> bool:
	var map := t.world.get_world_2d().navigation_map
	var spots := _spots(t, f, map)
	if spots.is_empty():
		return false
	for from: Vector2 in ROUTE_STARTS:
		var plain := NavBuilder.route(map, from, spots["pocket"])
		if not t.require(
			plain[plain.size() - 1].distance_to(spots["pocket"]) <= REACH,
			"set-up: slot %d (%s) can be walked to from %s on the plain map" % [
				POCKET_SLOT, str(spots["pocket"]), str(from),
			],
		):
			return false
	return await _cut_off_by_body(t, map, spots)


## Slot 4's and slot 3's spots on the navigation map `map` (`{ pocket, blocker }`); {} when the
## AI's layout does not hold the stack.
func _spots(t: TestContext, f: Dictionary, map: RID) -> Dictionary:
	var entry := Slots.entry_geometry(t.world.openings, t.rooms)
	if not t.require(entry != null, "set-up: the AI's entry geometry is there"):
		return {}
	var space := t.world.get_world_2d().direct_space_state
	var g: Dictionary = entry.geometry(f["id"], f["room_key"], map, space)
	var slots: Array = Slots.layout(g, STACK, 1)["slots"]
	if not t.require(
		slots.size() == STACK,
		"set-up: the stack of %d has %d slots" % [STACK, slots.size()],
	):
		return {}
	return {
		"pocket": NavBuilder.snap(map, _slot(slots, POCKET_SLOT)),
		"blocker": NavBuilder.snap(map, _slot(slots, BLOCKING_SLOT)),
	}


## Whether no place of `ROUTE_STARTS` reaches the pocket once a body (a 12-gon of radius `BODY`)
## stands on the blocker's spot.
func _cut_off_by_body(t: TestContext, map: RID, spots: Dictionary) -> bool:
	var region := NavBuilder.planning_region(map)
	if not t.require(region != null, "set-up: there is a planning region to carve a body in"):
		return false
	var body := PackedVector2Array()
	for i in 12:
		body.append(spots["blocker"] + Vector2.RIGHT.rotated(TAU * i / 12.0) * BODY)
	var avoid := NavBuilder.avoid_map(region, "slot_through_another", [body])
	var waited := 0
	while not NavBuilder.ready(avoid) and waited < 240:
		await t.frames(1)
		waited += 1
	if not t.require(NavBuilder.ready(avoid), "set-up: the avoid map came up"):
		return false
	for from: Vector2 in ROUTE_STARTS:
		var detour := NavBuilder.route(avoid, from, spots["pocket"])
		if not t.require(
			detour[detour.size() - 1].distance_to(spots["pocket"]) > REACH,
			"set-up: with a body in slot %d (%s), slot %d is out of reach from %s" % [
				BLOCKING_SLOT, str(spots["blocker"]), POCKET_SLOT, str(from),
			],
		):
			return false
	return true


## The point of slot `n` among `slots` (`{ n, point, side, row }`).
func _slot(slots: Array, n: int) -> Vector2:
	for s: Dictionary in slots:
		if int(s["n"]) == n:
			return s["point"]
	return Vector2.INF
