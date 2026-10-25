extends GameTest
## LD13 (`docs/leadership.md`): a Go given before the stack is ready is latched. The `go` does not
## replace the held stack order, it releases it: the members carry on to their slots and the stack
## goes the moment the usual ready barrier (D7) is met, without a second Go.
##
## Two invaders in the back garden, a walk of some 400 px from the Terrace house's back door, are
## ordered (quiet, hold for go) to stack on it from its north side; half a second later, while both
## are still walking, the leader's Go is posted through the squad. Their claims say the stack is
## held (`order_hold`), the Go names both, and once both are ready the point goes in with no further
## order.
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's alone.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const IDS := [&"a", &"b"]


func describe() -> Dictionary:
	return {
		"name": "A go given before the stack is ready is latched",
		"description": "Two invaders ordered to stack on the back door, hold for go, are given the "
			+ "go while still walking; once both are ready the point goes in without a second go "
			+ "(LD13).",
		"tags": ["ai", "entry", "leadership", "order", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(1200, 420))
	s.actor(&"b", &"invader", Vector2(1240, 470))
	s.actor(&"lead", &"puppet", Vector2(1250, 650), { "faction": &"invader" })
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var door: String = Entry.BACK["id"]
	var squad := t.squad(&"invader")
	await t.seconds(0.3)
	var order := Order.stack_order(
		squad,
		IDS.map(func(id): return t.actor(id)),
		Order.BACK_NORTH,
		"quiet",
		true,
	)
	if not t.require(not order.is_empty(), "the squad posts the held stack order (issue)"):
		return
	await t.seconds(0.5)
	if not t.require(
			not Order.all_called(t, IDS, "ready", door),
			"both are still on their way when the go is given (premise)",
	):
		return
	var go := Order.go(squad, Order.BACK_NORTH)
	if not t.require(
			not go.is_empty(),
			"the leader's go is posted while they walk (issue of kind go returned %s)" % str(go),
	):
		return
	t.check(
		(go.get("to", []) as Array).size() == 2,
		"the go names both holders of the held stack (%s)"
			% str((go.get("to", []) as Array).map(func(n): return n.name)),
	)
	var gos_before := Order.orders(t).filter(
		func(o): return String(o.get("kind", "")) == Order.GO,
	).size()

	if not await _claimed_held(t, door):
		return
	await _goes_on_latched_go(t, door, gos_before)


## Both claim the back door under the order, and their claims say it was ordered held. False when
## they never claimed.
func _claimed_held(t: TestContext, door: String) -> bool:
	var claimed := func():
		return IDS.all(func(id): return not Order.ordered_claims(t, t.actor(id), door).is_empty())
	if not t.require(
			await t.until(claimed, 10.0),
			"both claim the back door under the order (claims carrying order_id)",
	):
		return false
	for id in IDS:
		var held := Order.ordered_claims(t, t.actor(id), door).filter(
			func(c): return c.get("order_hold") == true,
		)
		t.check(not held.is_empty(), "%s's claims say the stack was ordered held (order_hold)" % id)
	return true


## The stack forms, and the point goes in once it is ready, on the latched go, with no second go
## than the `gos_before` already posted.
func _goes_on_latched_go(t: TestContext, door: String, gos_before: int) -> void:
	if not t.require(
			await t.until(func(): return Order.all_called(t, IDS, "ready", door), 30.0),
			"the stack forms: both radio ready",
	):
		return
	var ready_at: float = IDS.map(
		func(id): return Entry.first_call_time(t, "ready", id, door),
	).max()
	t.check(
		await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), 20.0),
		"the point goes in once the stack is ready, on the latched go",
	)
	var going := Order.first_time(
		t,
		&"callout",
		func(d): return String(d.get("entry_step", "")) == "going_in",
	)
	t.check(
		going >= ready_at,
		"no earlier than the ready barrier (ready at %.2f s, going in at %.2f s)"
			% [ready_at, going],
	)
	var gos_after := Order.orders(t).filter(
		func(o): return String(o.get("kind", "")) == Order.GO,
	).size()
	t.expect_eq(gos_after, gos_before, "with no second go")
