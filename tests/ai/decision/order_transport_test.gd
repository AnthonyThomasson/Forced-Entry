extends GameTest
## LD5 (`docs/leadership.md`): order transport. An order on the `&"order"` bus topic
## (`{ id, leader, faction, to, kind, room? ... }`) is taken only by the recipients named in `to`,
## which then have the snapshot fact `ordered`; it ends only when it is done, cancelled or replaced,
## never on a ttl (it is still held after three times the callout ttl); a newer order replaces it
## and `cancel` clears it.
##
## Scripted Von (the first option offered; the order level asks nothing): three defenders in the
## Terrace house's hall, two of them ordered to defend the kitchen by the third. The orders are
## posted straight onto the bus, as the squad posts them.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const OrderBrain := preload("res://tests/_ai/order_brain_probe.gd")
## The defenders' `callout_ttl` (s): the radio's memory, which an order must outlive.
const CALLOUT_TTL := 6.0


func describe() -> Dictionary:
	return {
		"name": "An order reaches its recipients only and never lapses",
		"description": "An order on the bus sets `ordered` on the NPCs it names and no other; it "
			+ "is still held after 3 x the callout ttl; a newer order replaces it and a cancel "
			+ "clears it (LD5).",
		"tags": ["ai", "decision", "leadership", "order", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.actor(&"a", &"defender", Vector2(300, 415))
	s.actor(&"b", &"defender", Vector2(420, 415))
	s.actor(&"c", &"defender", Vector2(540, 415))


func run(t: TestContext) -> void:
	var a := OrderBrain.brain(t, &"a")
	var b := OrderBrain.brain(t, &"b")
	var c := OrderBrain.brain(t, &"c")
	var boss := t.actor(&"c")
	await t.seconds(0.5)
	var c_walks := OrderBrain.decisions(c)
	Order.post({
		"id": "o1",
		"leader": boss,
		"faction": boss.faction,
		"to": [t.actor(&"a"), t.actor(&"b")],
		"kind": Order.DEFEND,
		"room": "kitchen",
	})
	await _check_first_order(t, a, b, c, c_walks)
	await _check_held(t, a)
	await _check_replaced(t, a, b, boss)
	await _check_cancelled(t, a, b, boss)


func _check_first_order(t: TestContext, a: Node, b: Node, c: Node, c_walks: int) -> void:
	t.check(
		await t.until(func(): return OrderBrain.on_order(a) and OrderBrain.on_order(b), 3.0),
		"both recipients take the order (acts %s, %s)" % [a.current_act(), b.current_act()],
	)
	t.check(OrderBrain.ordered(a) and OrderBrain.ordered(b), "and decide with the fact `ordered`")
	t.check(
		await t.until(func(): return OrderBrain.decisions(c) > c_walks, 5.0),
		"the NPC not named decides meanwhile (premise)",
	)
	t.check(
		not OrderBrain.ordered(c) and not OrderBrain.on_order(c),
		"the NPC not named takes no order (act %s, ordered %s)"
			% [c.current_act(), str(OrderBrain.ordered(c))],
	)


func _check_held(t: TestContext, a: Node) -> void:
	# Three times the callout ttl later the order is still held: a decision forced now (gunfire
	# beside it) still has `ordered`.
	await t.seconds(CALLOUT_TTL * 3.0 + 1.0)
	var walks := OrderBrain.decisions(a)
	Order.gunfire_near(t.actor(&"a"))
	if t.check(
			await t.until(func(): return OrderBrain.decisions(a) > walks, 3.0),
			"gunfire beside the recipient forces a decision (premise)",
	):
		t.check(
			OrderBrain.ordered(a),
			"after 3 x the callout ttl the recipient still holds its order (ordered)",
		)


func _check_replaced(t: TestContext, a: Node, b: Node, boss: Node) -> void:
	Order.post({
		"id": "o2",
		"leader": boss,
		"faction": boss.faction,
		"to": [t.actor(&"a")],
		"kind": Order.DEFEND,
		"room": "living_room",
	})
	t.check(
		await t.until(
			func(): return String(OrderBrain.params(a).get("room", "")) == "living_room",
			15.0,
		),
		"a newer order replaces the old one (a's running order: %s %s)"
			% [OrderBrain.primitive(a), str(OrderBrain.params(a))],
	)
	t.check(
		OrderBrain.on_order(b) and String(OrderBrain.params(b).get("room", "")) == "kitchen",
		"the other recipient keeps the first order (%s)" % str(OrderBrain.params(b)),
	)


func _check_cancelled(t: TestContext, a: Node, b: Node, boss: Node) -> void:
	var walks := OrderBrain.decisions(a)
	Order.post({
		"id": "o3",
		"leader": boss,
		"faction": boss.faction,
		"to": [t.actor(&"a")],
		"kind": Order.CANCEL,
	})
	t.check(
		await t.until(
			func(): return OrderBrain.decisions(a) > walks and not OrderBrain.on_order(a),
			5.0,
		),
		"a cancel ends the order (act %s)" % a.current_act(),
	)
	t.check(not OrderBrain.ordered(a), "and the recipient decides without `ordered`")
	t.check(
		OrderBrain.on_order(b),
		"the cancel named only one recipient: the other is still on its order",
	)
