extends GameTest
## LD13 / D14 (`docs/leadership.md`, interface 21): a held stack's go read off the radio is latched
## by the squad. Once the claims say the go came (a claim under the held order saying `order_go`, or
## a member of that stack crossing), `Squad.view()` says the order is no longer `held`, and it stays
## so after the claims stop saying it, as each member keeps its own go.
##
## The squad is declared (`s.squads`, built and bound as a match's) over three puppet teammates and
## a puppet standing in for the human leader (`human`), on the Terrace house, keeping a claim as
## long as the NPCs keep a callout (`claim_ttl`, `CLAIM_TTL`: a match reads it off the side's NPCs,
## and puppets have none), so a claim that stops saying the go is still on the radio, saying
## something else. Two held stacks (`wait_go`) are ordered: `t1` and `t2` at the back door, `t3` at
## the hall / living room doorway. At the back door `t1` radios `order_go` once, then both radio
## plain `ready` claims again; at the hall doorway `t3` radios `going_in` (the D14 go), then `done`,
## its claim gone from the stack. No `go` is ever issued.
##
## Premise: the members are puppets radioing their claims on the bus, in the wire format's field
## names (interface 10), not AI invaders. What an AI radios after its go (`order_go` repeated by its
## heartbeat, its own crossing) keeps saying the go came, so only puppets can make the claims stop
## saying it; the squad reads only the bus, so a puppet's claim is exactly what it hears from an AI.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
## A click in the living room, on the hall / living room doorway's axis (its wall plane is y 360).
const IN_LIVING := Vector2(150, 330)
## How long (s) the claims say nothing of the go before the first look, and after it.
const QUIET := 1.0
const AFTER := 3.0
## How often (s) the puppets repeat their claims (the NPCs' heartbeat is 2 s).
const REPEAT := 0.5
## How long (s) the squad keeps a claim: the NPCs' `callout_ttl` (6 s).
const CLAIM_TTL := 6.0


func describe() -> Dictionary:
	return {
		"name": "The squad latches a held stack's go read off the claims",
		"description": "Two held stacks; one's claims say order_go once, the other's member "
			+ "crosses then is done: Squad.view() stops saying held for each, and keeps not "
			+ "saying it after the claims stop saying the go came (LD13, D14).",
		"tags": ["ai", "leadership", "squad", "order", "stack"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"t1", &"puppet", Vector2(960, 330), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(1000, 420), { "faction": &"invader" })
	s.actor(&"t3", &"puppet", Vector2(1040, 520), { "faction": &"invader" })
	s.actor(&"me", &"puppet", Vector2(1100, 600), { "faction": &"invader" })
	s.squads({ "human": &"me", "claim_ttl": CLAIM_TTL })


func run(t: TestContext) -> void:
	var t1 := t.actor(&"t1")
	var t2 := t.actor(&"t2")
	var t3 := t.actor(&"t3")
	var squad := t.squad(&"invader")
	if not t.require(squad != null, "the invaders' squad is declared (s.squads)"):
		return
	var back := Order.stack_order(squad, [t1, t2], Order.BACK_NORTH, "quiet", true)
	var hall := Order.stack_order(squad, [t3], IN_LIVING, "quiet", true)
	if not t.require(
			not back.is_empty()
				and not hall.is_empty()
				and String(back["opening"]) != String(hall["opening"]),
			"set-up: two held stacks are ordered, at two doorways",
	):
		return
	# Plain claims under each order: everyone in its slot, nobody saying the go came.
	var plain := func():
		_radio(t, &"t1", back, 1, "ready")
		_radio(t, &"t2", back, 2, "ready")
		_radio(t, &"t3", hall, 1, "ready")
	await _repeat(t, plain, QUIET)
	if not t.require(
			_held(squad, t1) and _held(squad, t2) and _held(squad, t3),
			"set-up: every member's order is held while the claims say no go",
	):
		return
	await _check_latched(t, squad, back, hall)


## The `back` door's claims say the go came, once, and the `hall`'s member crosses then is done:
## each order is no longer held, and stays so once the claims stop saying the go came.
func _check_latched(t: TestContext, squad: Node, back: Dictionary, hall: Dictionary) -> void:
	var t1 := t.actor(&"t1")
	var t2 := t.actor(&"t2")
	var t3 := t.actor(&"t3")
	EventBus.post(&"callout", _claim(t1, back, 1, "ready", true))  # Once, saying the go came.
	await t.frames(1)
	t.check(
		not _held(squad, t1) and not _held(squad, t2),
		"a claim under the back door's order saying order_go: its orders are no longer held",
	)
	t.check(_held(squad, t3), "the hall's held stack is not released by another order's go")
	# The hall's member crosses (D14), then is done: its claim leaves the stack.
	_radio(t, &"t3", hall, 1, "going_in")
	await t.frames(1)
	t.check(not _held(squad, t3), "the hall's member crossing: its order is no longer held")
	_radio(t, &"t3", hall, 1, "done")

	# The claims stop saying the go came: plain claims at the back door, none at the hall.
	var after := func():
		_radio(t, &"t1", back, 1, "ready")
		_radio(t, &"t2", back, 2, "ready")
	await _repeat(t, after, AFTER)
	t.check(
		not _held(squad, t1) and not _held(squad, t2),
		"the back door's orders stay released once the claims stop saying order_go",
	)
	t.check(
		not _held(squad, t3),
		"the hall's order stays released once its member's crossing is off the radio",
	)


## Whether `m`'s order is held in `squad`'s view.
func _held(squad: Node, m: Node) -> bool:
	return bool(Order.member_view(squad, m).get("held", false))


## Radio actor `who` (a puppet member) at entry step `step` on slot `slot` of held stack order
## `order`, the claim an ordered NPC's entry radios in the wire format's field names (interface 10).
func _radio(t: TestContext, who: StringName, order: Dictionary, slot: int, step: String) -> void:
	EventBus.post(&"callout", _claim(t.actor(who), order, slot, step, false))


## The claim puppet `c` radios at entry step `step` on slot `slot` of held stack order `order`;
## `go` its `order_go`.
func _claim(c: Node, order: Dictionary, slot: int, step: String, go: bool) -> Dictionary:
	return {
		"speaker": c, "faction": c.faction, "position": c.global_position, "status": "",
		"path": "", "label": "", "target_id": 0, "point": c.global_position,
		"opening": order["opening"], "into": order["into"], "slot": slot, "side": 1,
		"entry_step": step, "order_id": order["id"], "order_mode": "quiet", "order_hold": true,
		"order_go": go,
	}


## Call `say` every `REPEAT` s for `span` s.
func _repeat(t: TestContext, say: Callable, span: float) -> void:
	var start := t.time
	while t.time - start < span:
		say.call()
		await t.seconds(REPEAT)
