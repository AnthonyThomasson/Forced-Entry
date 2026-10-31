extends GameTest
## LD13 with D38 rule 2: a member of a stack held for its leader's go fights only on the stack's
## side of the doorway. Two invaders are ordered (quiet, hold for go) to stack on the bare Terrace
## house's back door from its north side, their leader a puppet human far off in the garden. Once
## both stand ready, a defender walks into view in the kitchen and fires at the stack through the
## doorway for `HeldFight.FIGHT` s, then walks back out of sight: they fire back from outside, and
## none crosses into the kitchen while held, nor goes after the defender lost in it
## (`HeldFight.AFTER` s).
##
## Real Von, the whole pipeline; no switch. Premises: the defender (a puppet) and the invaders are
## never killed (`max_health`), so the stack stays held through the fight.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const HeldFight := preload("res://tests/_ai/held_fight_probe.gd")
const IDS := [&"a", &"b"]
## How long (s) the stack has, once ordered, to stand ready.
const READY_WITHIN := 20.0


func describe() -> Dictionary:
	return {
		"name": "A stack held for go fights from the stack's side",
		"description": "Two invaders ordered to stack on the back door, hold for go, stand ready; "
			+ "a defender in the kitchen fires at them through the doorway: they fire back from "
			+ "outside and never cross while held.",
		"tags": ["ai", "entry", "leadership", "order", "combat", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	# Never killed (premise): the stack stays held through the fight.
	s.actor(&"a", &"invader", Vector2(960, 60), { "max_health": 1_000_000.0 })
	s.actor(&"b", &"invader", Vector2(985, 110), { "max_health": 1_000_000.0 })
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
	var seen := await HeldFight.fight(t, &"d", members)
	HeldFight.check_stack_side(t, members, seen)
