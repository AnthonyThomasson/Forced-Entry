extends GameTest
## LD13 / D14 (`docs/leadership.md`): a held stack's go comes from its own stack only. A claim left
## on the radio from an earlier entry through the same doorway (a member still holding the room on
## `cover`, under no order) is no member of the held stack crossing: it releases nothing. The held
## stack keeps holding (nobody slices the pie, calls a bang or crosses) and `Squad.view()` says its
## orders are `held`, until the leader's `go`, which releases it and in they go.
##
## Three invaders are ordered (quiet, hold for go) to stack on the Terrace house's back door, from
## beside it on its north side, through `Squad.issue` by a puppet leader. Meanwhile a puppet in the
## kitchen radios a `cover` claim on that doorway into the kitchen, as a member left from an earlier
## entry does (it keeps its claim live with the heartbeat). Once all three are ready they are
## watched holding for `HOLD` s; then the leader's go is posted through the squad.
##
## The whole AI pipeline with the real Von server; the set-up `require`s that the members took the
## ordered path (their claims at the back door carry the order's id), so a different Von choice
## reads as a set-up finding. Premise: the earlier entry's member is a puppet radioing its claim on
## the bus (in the wire format's field names, interface 10), not an AI that cleared the kitchen: an
## AI's cover ends on its own clock (`tuning.entry.cover_time`) and its clear marks the room
## cleared, which
## changes what the ordered members do; the stack reads only the bus, so a puppet's claim is
## exactly what it hears from an AI. The squad is built in the run over the leader and the three
## (`Order.squad`, through `MatchBuilder.build_squads`), not declared with `s.squads`: the earlier
## entry's puppet is an invader too, and no member of the held stack's squad.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const IDS := [&"a", &"b", &"c"]
## Where the earlier entry's member holds the kitchen: in its north-west, away from the back door
## and its funnel, covering the kitchen / living room doorway.
const COVER_AT := Vector2(560, 70)
const COVERING := "door_480_150"
## How long (s) the held stack is watched not crossing once every member is ready.
const HOLD := 10.0
## How often (s) the earlier entry's member repeats its claim (the NPCs' heartbeat is 2 s).
const REPEAT := 1.0


func describe() -> Dictionary:
	return {
		"name": "A held stack ignores a claim left from an earlier entry through its doorway",
		"description": "Three invaders ordered to stack on the back door, hold for go, while a "
			+ "member of an earlier entry radios cover into the kitchen: they hold (no pie, no "
			+ "crossing) and the squad's view says held until the leader's go, then they go in "
			+ "(LD13, D14).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "von", "callout"],
		"requires_von": true,
		"timeout": 150.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(960, 60))
	s.actor(&"b", &"invader", Vector2(985, 110))
	s.actor(&"c", &"invader", Vector2(1010, 20))
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })
	s.actor(&"earlier", &"puppet", COVER_AT, { "faction": &"invader", "max_health": 1_000_000.0 })


func run(t: TestContext) -> void:
	var door: String = Entry.BACK["id"]
	var into: String = Entry.BACK["room_key"]
	var members := IDS.map(func(id): return t.actor(id))
	var squad := Order.squad(t, &"invader", [t.actor(&"lead")] + members, t.actor(&"lead"))
	if not t.require(squad != null, "the squad is built over the leader and the three"):
		return
	# The earlier entry's member keeps its cover claim on the radio for the whole test.
	var covering := [true]
	_keep_covering(t, door, into, covering)
	await t.seconds(0.3)
	var order := Order.stack_order(squad, members, Order.BACK_NORTH, "quiet", true)
	if not t.require(
			not order.is_empty() and order.get("wait_go") == true,
			"the squad posts the held order (issue: %s)" % str(order),
	):
		return
	if not t.require(
			String(order.get("into", "")) == into,
			"set-up: the order goes into the %s, the room the cover claim holds" % into,
	):
		return
	if not await _stack_ready(t, members, door):
		return

	if not await _holds(t, squad, members):
		return

	if not await _go_then_in(t, squad, members, door):
		return
	covering[0] = false


## All three take the ordered path and radio ready. False when they did not.
func _stack_ready(t: TestContext, members: Array, door: String) -> bool:
	var claimed := func():
		return members.all(func(m): return not Order.ordered_claims(t, m, door).is_empty())
	if not t.require(
			await t.until(claimed, 30.0),
			"set-up: all three took the ordered path (claims at the back door carrying the order)",
	):
		return false
	var ready := await t.until(func(): return Order.all_called(t, IDS, "ready", door), 45.0)
	t.check(ready, "the stack forms: all three radio ready")
	return ready


## Watches the held stack `HOLD` s: nobody radios going_in, slices the pie or crosses, and the
## squad's view says held. False when it broke.
func _holds(t: TestContext, squad: Node, members: Array) -> bool:
	var broke := ""
	var hold_end := t.time + HOLD
	while t.time < hold_end and broke == "":
		if not Entry.calls(t, "going_in").filter(
				func(c): return c.get("speaker") in members
		).is_empty():
			broke = "a member radioed going_in"
		elif _phases(t).has("pie") or _phases(t).has("cross"):
			broke = "a member sliced the pie or crossed (phases %s)" % str(_phases(t))
		elif not _held(squad, members):
			broke = "the squad's view no longer says held"
		await t.frames(1)
	t.check(
		broke == "",
		"the held stack keeps holding through the earlier entry's cover claim for %.0f s: %s"
			% [HOLD, broke if broke != "" else "it held"],
	)
	return broke == ""


## The leader's go is posted; it releases the held orders, and all three go in, none before it.
## False when the go was not posted.
func _go_then_in(t: TestContext, squad: Node, members: Array, door: String) -> bool:
	var go := Order.go(squad, Order.BACK_NORTH)
	if not t.require(not go.is_empty(), "the leader's go is posted (issue of kind go)"):
		return false
	var go_at := t.time
	t.check(
		await t.until(func(): return not _held(squad, members), 2.0),
		"after the go the squad's view no longer says the orders are held",
	)
	var all_in := func():
		return IDS.all(func(id): return Entry.first_call_time(t, "going_in", id, door) < INF)
	t.check(
		await t.until(all_in, 45.0),
		"after the go all three go in (going_in from %s)" % str(IDS.filter(
			func(id): return Entry.first_call_time(t, "going_in", id, door) < INF,
		)),
	)
	t.check(
		IDS.all(func(id): return Entry.first_call_time(t, "going_in", id, door) >= go_at),
		"nobody went in before the go (go at %.2f s)" % go_at,
	)
	return true


## Whether the squad's view says every one of `members`' orders is held.
func _held(squad: Node, members: Array) -> bool:
	return members.all(
		func(m): return bool(Order.member_view(squad, m).get("held", false))
	)


## Each member's entry phase.
func _phases(t: TestContext) -> Array:
	return IDS.map(
		func(id): return String(Entry.entry(Entry.brain(t, id)).get("phase", ""))
	)


## Keep the earlier entry's member (`earlier`) radioing `cover` on doorway `door` into `into` every
## `REPEAT` s while `on[0]` holds, as a member holding a cleared room does.
func _keep_covering(t: TestContext, door: String, into: String, on: Array) -> void:
	var c := t.actor(&"earlier")
	while on[0] and is_instance_valid(c):
		EventBus.post(&"callout", {
			"speaker": c, "faction": c.faction, "position": c.global_position, "status": "",
			"path": "", "label": "", "target_id": 0, "point": c.global_position,
			"opening": door, "into": into, "slot": 1, "side": 1, "entry_step": "cover",
			"covering": COVERING,
		})
		await t.seconds(REPEAT)
