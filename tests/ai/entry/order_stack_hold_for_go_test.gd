extends GameTest
## LD13 (`docs/leadership.md`): hold for go. A stack order with `wait_go` forms, claims its slots
## and radios `ready` as usual, then holds before the pie: nobody crosses until the leader's `go`.
## Each member radios `order_step` `in_position` once ready and holding. After Go the entry runs as
## a go-when-ready stack of its mode, crossing in slot order.
##
## Three invaders are ordered (quiet, hold for go) to stack on the Terrace house's back door, from
## beside it on its north side (a click north of the opening: a one-sided stack, so the crossing
## order is the slot order). They form and are ready, and nobody crosses for 15 s; the leader's Go
## is then posted through the squad, and they go in, one after another by slot.
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's alone.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const IDS := [&"a", &"b", &"c"]
## How long (s) the held stack is watched not crossing once every member is ready.
const HOLD := 15.0


func describe() -> Dictionary:
	return {
		"name": "A held stack waits for go, then crosses in slot order",
		"description": "Three invaders ordered to stack on the back door, hold for go: they claim "
			+ "every slot and are ready, nobody crosses for 15 s; after the leader's go they "
			+ "cross in slot order (LD13).",
		"tags": ["ai", "entry", "leadership", "order", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(960, 60))
	s.actor(&"b", &"invader", Vector2(985, 110))
	s.actor(&"c", &"invader", Vector2(1010, 20))
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var door: String = Entry.BACK["id"]
	var squad := Order.raid(t, IDS, &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.3)
	var order := Order.stack_order(
		squad,
		IDS.map(func(id): return t.actor(id)),
		Order.BACK_NORTH,
		"quiet",
		true,
	)
	if not t.require(not order.is_empty(), "the squad posts the order (issue)"):
		return
	t.check(
		order.get("wait_go") == true,
		"the order is held for go (wait_go %s)" % str(order.get("wait_go")),
	)
	var claimed := func():
		return IDS.all(func(id): return not Order.ordered_claims(t, t.actor(id), door).is_empty())
	if not t.require(
			await t.until(claimed, 10.0),
			"all three claim the back door under the order (claims carrying order_id)",
	):
		return
	if not t.require(
			await t.until(func(): return Order.all_called(t, IDS, "ready", door), 30.0),
			"the stack forms: all three radio ready",
	):
		return
	# Each member's slot now: its latest call at the doorway, whatever the step (a member that said
	# ready, then moved up, says so in a claim).
	var at_door := func(c): return String(c.get("opening", "")) == door
	var slots := IDS.map(
		func(id): return int(Entry.calls(t, "", id).filter(at_door).back().get("slot", 0))
	)
	slots.sort()
	t.expect_eq(slots, [1, 2, 3], "every slot claimed, one each")

	var hold_end := t.time + HOLD
	var crossed := await t.until(
		func(): return (
			not Entry.calls(t, "going_in").is_empty() or not Entry.calls(t, "bang").is_empty()
		),
		HOLD,
	)
	t.check(
		not crossed,
		("nobody crosses (nor calls a bang) while the stack is held: %s at %.1f s, %.1f s into the "
				+ "%.0f s hold")
			% [
				str(Entry.calls(t, "going_in").map(func(c): return c.get("speaker").name)),
				t.time,
				HOLD - (hold_end - t.time),
				HOLD,
			],
	)
	var phases := IDS.map(func(id): return String(Entry.entry(Entry.brain(t, id)).get("phase", "")))
	t.check(
		not phases.has("pie") and not phases.has("cross"),
		"no member slices the pie or crosses while held (phases %s)" % str(phases),
	)
	for id in IDS:
		t.check(
			not Order.progress(t, "in_position", t.actor(id)).is_empty(),
			"%s radioed in_position once ready and holding" % id,
		)
	if crossed:
		return

	var go := Order.go(squad, Order.BACK_NORTH)
	if not t.require(
			not go.is_empty(),
			"the leader's go is posted (issue of kind go returned %s)" % str(go),
	):
		return
	var go_at := t.time
	var all_in := func():
		return IDS.all(func(id): return Entry.first_call_time(t, "going_in", id, door) < INF)
	t.check(
		await t.until(all_in, 45.0),
		"after the go all three go in (going_in from %s)" % str(IDS.filter(
			func(id): return Entry.first_call_time(t, "going_in", id, door) < INF,
		)),
	)
	var order_by_slot := Order.by_slot(t, IDS, door)
	var times := order_by_slot.map(func(id): return Entry.first_call_time(t, "going_in", id, door))
	t.check(
		times.all(func(x): return x >= go_at),
		"nobody went in before the go (go at %.2f s, going_in at %s)" % [go_at, str(times)],
	)
	var in_order := true
	for i in range(1, times.size()):
		in_order = in_order and times[i] >= times[i - 1]
	t.check(
		in_order,
		"they cross in slot order (%s going in at %s)"
			% [str(order_by_slot), str(times.map(func(x): return snappedf(x, 0.01)))],
	)
