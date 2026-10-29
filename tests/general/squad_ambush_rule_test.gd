extends GameTest
## The defenders' ambush rule (#128, interface 21): an AI-led defender squad, on a threat its side's
## radio places outside the leader's room (a COMBAT callout's `target_pos`), orders an `ambush` of
## the doorway into the leader's room the attack comes through, from that room, to its living NPC
## members holding no order, the leader included; with three or more of them the last in spawn order
## (never the leader) is kept back as rear guard. It re-orders only on a new doorway, at most every
## `reorder_gap` (8 s), to members holding no order, with at least `min_recipients` (2) of them; the
## key and the cool-down start afresh with a new leader, and a dead AI leader's ambushes stand. A
## member that radioed its order `refused` (no post for it) holds none for the rule: it is a
## recipient of the next.
##
## Mechanism test (scripted): the radio calls are the test's own, posted by a household puppet that
## is a squad member but no NPC (so never a recipient), and the cancels are the test's, issued as
## the leader's menu would. The crew is a real defender crew in the Terrace house's living room,
## squads declared as a match builds them (`s.squads`, `MatchBuilder.build_squads`). Premise
## switches: the crew's `movement:speed` is 0, so the leader's room stays the living room while the
## rule is read, and Von is scripted (a crew left alone searches the house and walks the leader out
## of its room).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
## The spec's numbers (#128 rule 7), this test's own copy.
const REORDER_GAP := 8.0
const MIN_RECIPIENTS := 2
const FRONT_CHAIN := "door_150_360"  # outside by the front door -> the hall -> the living room
const KITCHEN_DOOR := "door_480_150"  # from the kitchen into the living room
const OUTSIDE_FRONT := Vector2(-100, 415)
const IN_KITCHEN := Vector2(700, 100)
const IN_LIVING := Vector2(400, 250)


func describe() -> Dictionary:
	return {
		"name": "A defender crew's leader orders the ambush of the attack doorway",
		"description": "On a threat its radio places outside the leader's room the AI-led "
			+ "defender squad orders the ambush of the doorway the attack comes by, to its free "
			+ "NPCs and the leader, a rear guard kept back at three; it re-orders only on a new "
			+ "doorway, past the cool-down, to members holding no order; a new leader starts "
			+ "afresh and a dead leader's ambushes stand (#128).",
		"tags": ["ai", "leadership", "squad", "order", "ambush"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	var still := { "movement:speed": 0.0 }  # premise: the leader's room stays the living room
	s.actor(&"d1", &"defender", Vector2(240, 180), still)
	s.actor(&"d2", &"defender", Vector2(320, 260), still)
	s.actor(&"d3", &"defender", Vector2(180, 280), still)
	s.actor(&"p", &"puppet", Vector2(600, 415), { "faction": &"household" })
	s.von_script([{ "pick": "wait" }])
	s.squads()


func run(t: TestContext) -> void:
	var squad: Node = t.world.squad(&"household")
	var d1 := t.actor(&"d1")
	var d2 := t.actor(&"d2")
	if not t.require(squad != null and squad.leader() == d1, "the crew's squad, led by d1"):
		return
	await t.seconds(0.5)
	var first := await _first_order(t, squad)
	if first.is_empty():
		return
	await _cool_down(t, squad, first)
	var second := _ambushes(t).back() as Dictionary
	Order.issue(squad, { "kind": Order.CANCEL, "to": [d2] })
	await _wait_past(t, second)
	var third := await _call(t, OUTSIDE_FRONT)
	t.check(
		_is_ambush(third, FRONT_CHAIN) and _names(third.get("to", [])) == ["d2", "d3"],
		"with d1 still holding its order, the new doorway goes to the free d2 and d3, two: no rear "
			+ "guard kept back at two (%s)" % _describe(third),
	)
	t.expect_eq(
		str(Order.member_view(squad, d1).get("order", {}).get("id", "")),
		str(second.get("id", "")),
		"d1, holding an order, is skipped and keeps it",
	)
	var fresh := await _new_leader(t, squad, third)
	if not fresh.is_empty():
		var next := await _refused(t, fresh)
		await _one_free(t, squad, next)


## The first threat: the doorway its attack comes by, to d1 and d2, d3 kept back as rear guard and
## the puppet (no NPC) never named; a call naming the same doorway, or a threat in the leader's own
## room, orders nothing more. Returns the order ({} when the test ended).
func _first_order(t: TestContext, squad: Node) -> Dictionary:
	var first := await _call(t, OUTSIDE_FRONT)
	if not t.require(
			_is_ambush(first, FRONT_CHAIN),
			"a threat outside the front door orders the ambush of the hall's doorway into the "
				+ "living room (%s)" % _describe(first),
	):
		return {}
	t.expect_eq(String(first.get("room", "")), "living_room", "from the leader's room")
	t.expect_eq(_names(first.get("to", [])), ["d1", "d2"], "to the leader and d2")
	t.check(
		Order.member_view(squad, t.actor(&"d3")).get("order", {}).is_empty()
			and squad.follows(t.actor(&"d3")),
		"d3, the last spawned of three, is the rear guard: no order, it follows",
	)
	t.check(
		await _call(t, OUTSIDE_FRONT + Vector2(-40, 20)) == {},
		"a second threat by the same doorway orders nothing",
	)
	t.check(await _call(t, IN_LIVING) == {}, "a threat in the leader's own room orders nothing")
	t.check(await _call(t, Vector2.INF) == {}, "a call placing nothing orders nothing")
	return first


## Within the cool-down a new doorway orders nothing, though two members are free again; past it the
## same call orders the new doorway, d3 again the rear guard.
func _cool_down(t: TestContext, squad: Node, first: Dictionary) -> void:
	Order.issue(squad, { "kind": Order.CANCEL, "to": [t.actor(&"d1"), t.actor(&"d2")] })
	t.check(
		await _call(t, IN_KITCHEN) == {},
		"within %.0f s of the last ambush ordered a new doorway orders nothing" % REORDER_GAP,
	)
	await _wait_past(t, first)
	var again := await _call(t, IN_KITCHEN)
	t.check(
		_is_ambush(again, KITCHEN_DOOR) and _names(again.get("to", [])) == ["d1", "d2"],
		"past the cool-down a threat in the kitchen orders the kitchen's doorway to d1 and d2 (%s)"
			% _describe(again),
	)


## d1 dies holding its order: the ambushes it gave stand; d2 leads, and the key and the cool-down
## start afresh, so the same doorway as the last order, called within its cool-down, is ordered
## again to the members then free. Returns that order ({} when the test ended).
func _new_leader(t: TestContext, squad: Node, third: Dictionary) -> Dictionary:
	var d1 := t.actor(&"d1")
	var d2 := t.actor(&"d2")
	var d3 := t.actor(&"d3")
	var before := Order.orders(t).size()
	d1.take_damage(1.0e9)
	await t.frames(2)
	if not t.require(d1.is_dead and squad.leader() == d2, "d1 dead, d2 leads (premise)"):
		return {}
	t.check(
		Order.orders(t).slice(before).is_empty(),
		"the leader's death posts no order (its ambushes are not cancelled)",
	)
	for m in [d2, d3]:
		t.expect_eq(
			str(Order.member_view(squad, m).get("order", {}).get("id", "")),
			str(third.get("id", "")),
			"%s still holds the ambush the dead leader gave" % m.name,
		)
	Order.issue(squad, { "kind": Order.CANCEL, "to": [d2, d3] })
	var fresh := await _call(t, OUTSIDE_FRONT, d2)
	t.check(
		_is_ambush(fresh, FRONT_CHAIN) and _names(fresh.get("to", [])) == ["d2", "d3"],
		"the new leader's own call, the same doorway within the cool-down, orders it again (%s)"
			% _describe(fresh),
	)
	return fresh


## d2 and d3 radio the order they hold `refused` (there is no post for them): past the cool-down a
## new doorway is ordered to both, members that refused their order holding none for the rule.
## Returns that order.
func _refused(t: TestContext, held: Dictionary) -> Dictionary:
	await _wait_past(t, held)
	for id in [&"d2", &"d3"]:
		var m := t.actor(id)
		EventBus.post(&"callout", {
			"speaker": m, "faction": &"household", "position": m.global_position,
			"status": "", "path": "", "label": "", "target_id": 0, "point": m.global_position,
			"order_id": held["id"], "order_step": "refused",
		})
	var next := await _call(t, IN_KITCHEN, t.actor(&"d2"))
	t.check(
		_is_ambush(next, KITCHEN_DOOR) and _names(next.get("to", [])) == ["d2", "d3"],
		"having refused their order, d2 and d3 are ordered the kitchen's doorway (%s)"
			% _describe(next),
	)
	return next


## d3's order cancelled, d2 (the leader) still holding `held`: past the cool-down a new doorway
## would go to d3 alone, fewer than `MIN_RECIPIENTS`, so nothing is ordered.
func _one_free(t: TestContext, squad: Node, held: Dictionary) -> void:
	Order.issue(squad, { "kind": Order.CANCEL, "to": [t.actor(&"d3")] })
	await _wait_past(t, held)
	t.check(
		await _call(t, OUTSIDE_FRONT, t.actor(&"d2")) == {},
		"a new doorway with only d3 free (under %d recipients) orders nothing" % MIN_RECIPIENTS,
	)


## Post a COMBAT callout placing a hostile at `target` from `speaker` (the puppet by default), wait
## two frames, and return the ambush order it gave rise to, or {}.
func _call(t: TestContext, target: Vector2, speaker: Node = null) -> Dictionary:
	var who: Node = speaker if speaker != null else t.actor(&"p")
	var before := _ambushes(t).size()
	EventBus.post(&"callout", {
		"speaker": who, "faction": &"household", "position": who.global_position,
		"status": "", "path": "combat/t_1/engage/here", "label": "COMBAT", "target_id": 0,
		"point": who.global_position, "target_pos": target,
	})
	await t.frames(2)
	var after := _ambushes(t)
	return after.back() if after.size() > before else {}


## Wait until `REORDER_GAP` s (and a little) of game time have passed since `order` was posted.
func _wait_past(t: TestContext, order: Dictionary) -> void:
	var gap := int((REORDER_GAP + 0.2) * Engine.physics_ticks_per_second)
	var due := int(order.get("frame", 0)) + gap
	await t.until(
		func(): return GameClock.frame() >= due,
		REORDER_GAP + 2.0,
		"the cool-down passes",
	)


## The ambush orders posted so far.
func _ambushes(t: TestContext) -> Array:
	return Order.orders(t).filter(func(o): return String(o.get("kind", "")) == Order.AMBUSH)


## Whether `order` is an ambush of doorway `opening`.
func _is_ambush(order: Dictionary, opening: String) -> bool:
	return (
		String(order.get("kind", "")) == Order.AMBUSH
			and String(order.get("opening", "")) == opening
	)


## `order` in words for a check's message.
func _describe(order: Dictionary) -> String:
	if order.is_empty():
		return "none"
	var to := str(_names(order.get("to", [])))
	return "%s %s from %s to %s" % [order.get("kind"), order.get("opening"), order.get("room"), to]


## The names of `nodes`, sorted.
func _names(nodes: Array) -> Array:
	var out := nodes.map(func(n): return String(n.name) if n is Node else str(n))
	out.sort()
	return out
