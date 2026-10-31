extends GameTest
## LD13 to LD15 (`docs/leadership.md`, interface 21): the squad's side of the new orders.
## `Squad.issue` resolves a stack's `mode` (from `mode`, else `bang`: `bang: true` with no mode is a
## stun, part 1's request) and its `wait_go` (false by default: go when ready); a `go` names the
## doorway nearest its `pos` and goes to every living member holding a held stack order there,
## whatever the request's `to` (D13), and does not replace those orders (they stay held, released);
## an `ambush` names the doorway and the room on the side of its wall plane the click lies on (D17;
## an exterior door: the house's room), and one naming its doorway by id and the room it is laid
## from (`{ kind: "ambush", opening, room }`, the defenders' ambush rule, #128) resolves and posts
## the same order as the equivalent click; `resolve` answers `go` and `ambush` too; and the leader's
## death releases the held orders it gave (D12: a `go` with `auto: true`).
##
## The squad is built the way Main builds it over three puppet teammates and a puppet standing in
## for the human leader, on the Terrace house (its doorways: the back door `door_840_190` in the
## kitchen's east wall, the hall / living room doorway `door_150_360`). No AI runs: what is read is
## what `issue` returns, the `&"order"` events and the squad's `view()`.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const BACK := "door_840_190"
const HALL_LIVING := "door_150_360"
## Clicks either side of the hall / living room doorway's wall plane (y 360), on its axis: in the
## living room, then in the hall.
const IN_LIVING := Vector2(150, 330)
const IN_HALL := Vector2(150, 392)


func describe() -> Dictionary:
	return {
		"name": "The squad resolves go, ambush, the stack's mode and hold",
		"description": "Squad.issue gives a stack its mode (from bang when no mode) and wait_go, a "
			+ "go to every holder of a held stack at that doorway only (latched, the stack orders "
			+ "kept), an ambush its doorway and the click side's room; the leader's death "
			+ "releases its held orders (LD13 to LD15, D12, D13, D17).",
		"tags": ["ai", "leadership", "squad", "order"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"t1", &"puppet", Vector2(960, 330), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(1000, 420), { "faction": &"invader" })
	s.actor(&"t3", &"puppet", Vector2(1040, 520), { "faction": &"invader" })
	s.actor(&"me", &"puppet", Vector2(1100, 600), { "faction": &"invader" })
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var squad: Node = t.world.squad(&"invader")
	if not t.require(
			squad != null,
			"the invaders' squad is declared (s.squads)",
	):
		return
	_check_modes(t, squad)
	var held := _held_stack(t, squad)
	if held.is_empty():
		return
	_check_go(t, squad, held)
	_check_go_without_holder(t, squad)
	_check_ambush(t, squad)
	_check_ambush_by_id(t, squad)
	await _check_leader_death(t, squad)


## The stack's mode and hold: a part-1 request (bang, no mode, no wait_go) is a stun stack that
## goes when ready; quiet likewise; a frag stack keeps its mode.
func _check_modes(t: TestContext, squad: Node) -> void:
	var t3 := t.actor(&"t3")
	var stun := Order.issue(
		squad,
		{ "kind": Order.STACK, "to": [t3], "pos": Order.BACK_NORTH, "bang": true },
	)
	t.expect_eq(
		String(stun.get("mode", "")),
		"stun",
		"a part-1 stack request with bang and no mode is a stun stack (mode %s)"
			% str(stun.get("mode")),
	)
	t.expect_eq(stun.get("wait_go"), false, "and goes when ready (wait_go false)")
	t.expect_eq(stun.get("bang"), true, "its bang kept for part 1 (true)")
	var quiet := Order.issue(
		squad,
		{ "kind": Order.STACK, "to": [t3], "pos": Order.BACK_NORTH, "bang": false },
	)
	t.expect_eq(
		String(quiet.get("mode", "")),
		"quiet",
		"bang false and no mode is a quiet stack (mode %s)" % str(quiet.get("mode")),
	)
	var frag := Order.issue(
		squad,
		{
			"kind": Order.STACK,
			"to": [t3],
			"pos": Order.BACK_NORTH,
			"bang": true,
			"mode": "frag",
			"wait_go": false,
		},
	)
	t.expect_eq(
		String(frag.get("mode", "")),
		"frag",
		"a frag stack keeps its mode (mode %s)" % str(frag.get("mode")),
	)
	t.expect_eq(frag.get("bang"), true, "with bang true (mode != quiet)")


## A held stun stack at the back door for t1 and t2: the order `squad` posted, {} when it posted
## none (the test ended).
func _held_stack(t: TestContext, squad: Node) -> Dictionary:
	var t1 := t.actor(&"t1")
	var t2 := t.actor(&"t2")
	var held := Order.issue(
		squad,
		{
			"kind": Order.STACK,
			"to": [t1, t2],
			"pos": Order.BACK_NORTH,
			"bang": true,
			"mode": "stun",
			"wait_go": true,
		},
	)
	if not t.require(not held.is_empty(), "the held stack is posted (issue)"):
		return held
	t.expect_eq(
		held.get("wait_go"),
		true,
		"the held stack carries wait_go true (%s)" % str(held.get("wait_go")),
	)
	t.expect_eq(String(held.get("mode", "")), "stun", "and its mode, stun")
	t.expect_eq(String(held.get("opening", "")), BACK, "at the back door")
	return held


## Go: resolved to the doorway, to the holders of the `held` stack there only, whatever the request
## names; the stack orders stay held.
func _check_go(t: TestContext, squad: Node, held: Dictionary) -> void:
	var t1 := t.actor(&"t1")
	var t2 := t.actor(&"t2")
	var t3 := t.actor(&"t3")
	t.check(
		not squad.resolve({ "kind": "go", "pos": Order.BACK_NORTH }).is_empty(),
		"resolve answers a go at the back door (%s)"
			% str(squad.resolve({ "kind": "go", "pos": Order.BACK_NORTH })),
	)
	var go := Order.issue(squad, { "kind": "go", "to": [t3], "pos": Order.BACK_NORTH })
	if t.check(not go.is_empty(), "the go is posted (issue returned %s)" % str(go)):
		t.expect_eq(String(go.get("kind", "")), "go", "as an order of kind go")
		t.expect_eq(String(go.get("opening", "")), BACK, "naming the back door")
		t.expect_eq(
			Order.names(go.get("to", [])),
			Order.names([t1, t2]),
			"to every holder of the held stack there, not the request's t3 (D13)",
		)
	var posted := Order.orders(t).filter(func(o): return String(o.get("kind", "")) == "go")
	t.check(posted.size() == 1, "one go order on the bus (%d)" % posted.size())
	for m in [t1, t2]:
		var kept: Dictionary = Order.member_view(squad, m).get("order", {})
		t.check(
			String(kept.get("kind", "")) == Order.STACK
				and str(kept.get("id", "")) == str(held.get("id", "")),
			"%s still holds its stack order after the go (latched: released, not replaced) (%s)"
				% [m.name, str(kept)],
		)


## A go where nobody holds a held stack: nothing to post. t3's latest stack (go when ready) at the
## back door does not count.
func _check_go_without_holder(t: TestContext, squad: Node) -> void:
	var none := Order.issue(squad, { "kind": "go", "pos": Vector2(690, 330) })
	t.check(none.is_empty(), "a go at a doorway with no held stack posts nothing (%s)" % str(none))


## Ambush: the doorway and the room on the click's side of its wall plane; an exterior door's is the
## house's room.
func _check_ambush(t: TestContext, squad: Node) -> void:
	var t3 := t.actor(&"t3")
	var from_living := Order.issue(squad, { "kind": "ambush", "to": [t3], "pos": IN_LIVING })
	if t.check(
			not from_living.is_empty(),
			"an ambush is posted (issue returned %s)" % str(from_living),
	):
		t.expect_eq(String(from_living.get("kind", "")), "ambush", "as an order of kind ambush")
		t.expect_eq(
			String(from_living.get("opening", "")),
			HALL_LIVING,
			"at the hall / living room doorway",
		)
		t.expect_eq(
			String(from_living.get("room", "")),
			"living_room",
			"from the living room, the side clicked (D17)",
		)
		t.check(
			from_living.get("pos") is Vector2,
			"with a target point for the markers (pos %s)" % str(from_living.get("pos")),
		)
	var from_hall: Dictionary = squad.resolve({ "kind": "ambush", "pos": IN_HALL })
	t.expect_eq(
		String(from_hall.get("room", "")),
		"hall",
		"clicked on the hall side, the ambush is from the hall (resolve %s)" % str(from_hall),
	)
	t.expect_eq(String(from_hall.get("opening", "")), HALL_LIVING, "at the same doorway")
	var exterior: Dictionary = squad.resolve({ "kind": "ambush", "pos": Order.BACK_SOUTH })
	t.expect_eq(
		String(exterior.get("room", "")),
		"kitchen",
		"an exterior door clicked from outside: the house's room (resolve %s)" % str(exterior),
	)


## An ambush named by doorway id and room resolves as the click on that room's side does, and posts
## the same order; a doorway the house does not have, or a room the doorway does not join, names
## nothing.
func _check_ambush_by_id(t: TestContext, squad: Node) -> void:
	var t3 := t.actor(&"t3")
	var cases := [
		[HALL_LIVING, "living_room", IN_LIVING],
		[HALL_LIVING, "hall", IN_HALL],
		[BACK, "kitchen", Order.BACK_SOUTH],
	]
	for c in cases:
		var by_id: Dictionary = squad.resolve({ "kind": "ambush", "opening": c[0], "room": c[1] })
		var by_click: Dictionary = squad.resolve({ "kind": "ambush", "pos": c[2] })
		t.check(
			not by_id.is_empty() and by_id == by_click,
			"the ambush of %s from the %s by id resolves as the click on that side (%s, click %s)"
				% [c[0], c[1], str(by_id), str(by_click)],
		)
	var posted := Order.issue(
		squad,
		{ "kind": "ambush", "to": [t3], "opening": HALL_LIVING, "room": "living_room" },
	)
	var clicked := Order.issue(squad, { "kind": "ambush", "to": [t3], "pos": IN_LIVING })
	t.check(
		not posted.is_empty() and _same_order(posted, clicked),
		"issued by id it posts the click's order (%s, click %s)" % [str(posted), str(clicked)],
	)
	var unknown: Dictionary = squad.resolve(
		{ "kind": "ambush", "opening": "door_1_1", "room": "kitchen" },
	)
	t.check(unknown.is_empty(), "a doorway the house lacks names nothing (%s)" % str(unknown))
	var not_joined: Dictionary = squad.resolve(
		{ "kind": "ambush", "opening": HALL_LIVING, "room": "kitchen" },
	)
	t.check(
		not_joined.is_empty(),
		"a room the doorway does not join names nothing (%s)" % str(not_joined),
	)


## Whether orders `a` and `b` are the same order but for their id and frame.
func _same_order(a: Dictionary, b: Dictionary) -> bool:
	var x := a.duplicate()
	var y := b.duplicate()
	for k in ["id", "frame"]:
		x.erase(k)
		y.erase(k)
	return x == y


## D12: the leader that gave a held order dies before any go; its held orders are released (a go
## with auto: true to their holders).
func _check_leader_death(t: TestContext, squad: Node) -> void:
	var t1 := t.actor(&"t1")
	var t2 := t.actor(&"t2")
	var me := t.actor(&"me")
	var again := Order.issue(
		squad,
		{
			"kind": Order.STACK,
			"to": [t1, t2],
			"pos": Order.BACK_NORTH,
			"bang": false,
			"mode": "quiet",
			"wait_go": true,
		},
	)
	if not t.require(not again.is_empty(), "a new held stack replaces the released one (issue)"):
		return
	var before := Order.orders(t).size()
	me.take_damage(1.0e9)
	if not t.require(me.is_dead, "the leader is dead (premise)"):
		return
	await t.frames(2)
	var released := Order.orders(t).slice(before).filter(
		func(o): return String(o.get("kind", "")) == "go" and o.get("auto") == true,
	)
	t.check(
		released.size() == 1,
		"the leader's death posts one go with auto true (%s)" % str(
			Order.orders(t).slice(before).map(func(o): return [o.get("kind"), o.get("auto")]),
		),
	)
	if not released.is_empty():
		t.expect_eq(
			Order.names(released[0].get("to", [])),
			Order.names([t1, t2]),
			"to the holders of its held stack",
		)
		t.expect_eq(String(released[0].get("opening", "")), BACK, "at the back door")
