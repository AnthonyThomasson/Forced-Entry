extends GameTest
## Issue #154, D38: a member of a stack held for its leader's go that falls back under fire falls
## back on the stack's side of the doorway. Offered a retreat into a room its way back from runs
## through the room it is held to enter, it took one (into the living room, beyond the kitchen it
## stacks on) and, its walk back kept out of the kitchen, went the long way round the house (a hall
## to clear, out by the front door, round the north side) and was not back in its slot in time.
##
## Scripted Von (one mechanism: what RETREAT offers a held member): COMBAT > RETREAT, the first
## spot offered. Two invaders are ordered (quiet, hold for go) to stack on the bare Terrace house's
## back door from its north side, their leader a puppet human far off in the garden; once both
## stand ready, a defender in the kitchen fires at them through the doorway. Premises: the members
## and the defender are never killed (`max_health`), so the stack stays held through the fight;
## the members know the house (`familiar_with_house`), as one that has been round it in the fight
## knows the rooms beyond the kitchen (the flake's member had, by the front door).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const HeldFight := preload("res://tests/_ai/held_fight_probe.gd")
const IDS := [&"a", &"b"]
## How long (s) the stack has, once ordered, to stand ready.
const READY_WITHIN := 20.0
## How long (s) the defender fires at the stack while a member is asked where to fall back to.
const FIRE_WITHIN := 10.0
## The rooms the way back from to the stack's side of the back door runs through the kitchen: the
## living room (by the kitchen's west doorway) and the hall (by the kitchen's south doorway), named
## by their room type.
const BEYOND := ["fall_living_room", "fall_hallway"]


func describe() -> Dictionary:
	return {
		"name": "A held member falls back on the stack's side",
		"description": "Two invaders stacked on the back door, held for go, are shot at from the "
			+ "kitchen: no retreat into a room beyond the kitchen is offered to them.",
		"tags": ["ai", "entry", "leadership", "order", "combat", "retreat", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "combat" }, { "pick": "retreat" }])
	# Never killed (premise): the stack stays held through the fight. Familiar with the house
	# (premise): the rooms beyond the kitchen are known, so a retreat there could be offered.
	s.actor(&"a", &"invader", Vector2(960, 60), { "max_health": 1_000_000.0 })
	s.actor(&"b", &"invader", Vector2(985, 110), { "max_health": 1_000_000.0 })
	for id in IDS:
		s.set_props(id, "GoalController", { "tuning:memory:familiar_with_house": true })
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })
	s.squads({ "human": &"lead" })
	HeldFight.defender(s, &"d")


func run(t: TestContext) -> void:
	var door: String = Entry.BACK["id"]
	var squad: Node = t.world.squad(&"invader")
	var members: Array = IDS.map(func(id): return t.actor(id))
	HeldFight.arm(t, &"d")
	await t.seconds(0.3)
	var order := Order.stack_order(squad, members, Order.BACK_NORTH, "quiet", true)
	if not t.require(
			not order.is_empty() and order.get("wait_go") == true,
			"the squad posts the stack order, held for go (issue)",
	):
		return
	if not t.require(
			await t.until(func(): return Order.all_called(t, IDS, "ready", door), READY_WITHIN),
			"set-up: both claim the back door under the order and stand ready",
	):
		return
	if not _knows_beyond(t):
		return
	for r: Dictionary in await _retreats_asked(t, members):
		var beyond: Array = (r["options"] as Array).filter(func(o): return BEYOND.has(String(o)))
		t.check(
			beyond.is_empty(),
			"no retreat beyond the kitchen is offered to a held member (offered %s)"
				% str(r["options"]),
		)


## Premise: each member knows the living room and the hall, so a retreat there is one the snapshot
## could offer.
func _knows_beyond(t: TestContext) -> bool:
	for id in IDS:
		var known := _known_rooms(t, id)
		if not t.require(
				known.has("living room") and known.has("hallway"),
				"premise: %s knows the living room and the hall (rooms %s)" % [id, known],
		):
			return false
	return true


## Walk the defender into view and fire at the stack until a held member is asked where to fall
## back to: the RETREAT requests asked meanwhile (`DecisionStub.requests`), [] when none was.
func _retreats_asked(t: TestContext, members: Array) -> Array:
	var puppet := t.puppet(&"d")
	puppet.walk_to(HeldFight.IN_VIEW)
	var asked := DecisionStub.requests.size()
	var clock := { "next": 0.0 }
	var retreats := func() -> Array:
		return DecisionStub.requests.slice(asked).filter(func(r): return (
			(r["options"] as Array).any(func(o): return String(o).begins_with("fall_"))
		))
	var firing := func() -> bool:
		if puppet.has_arrived() and t.time >= clock["next"]:
			clock["next"] = t.time + HeldFight.FIRE_EVERY
			puppet.aim_at(members[0])
			puppet.shoot()
		return not retreats.call().is_empty()
	if not t.require(
			await t.until(firing, FIRE_WITHIN),
			"set-up: shot at through the doorway, a held member is asked where to fall back to",
	):
		return []
	return retreats.call()


## The types of the rooms the NPC `id` knows of (`debug_room_zones`: every room not `unknown`).
func _known_rooms(t: TestContext, id: StringName) -> Array:
	var zones: Array = t.controller(id, &"debug_room_zones").debug_room_zones()
	return zones.filter(func(z): return z.get("status", "") != "unknown").map(
		func(z): return String(z["type"])
	)
