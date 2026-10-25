extends GameTest
## LD17 (`docs/leadership.md`, ticket #65 round 2, rule 10): an unordered joiner's grace counts from
## the last ordered member. An unordered member joining an ordered stack (D10) is waited for
## `entry_ready_timeout` (6 s), counted from the moment every ordered member is in its slot, not
## from the point's own arrival: a point that has stood in its slot far longer than that still waits
## for a joiner that reaches its slot within the grace of the last ordered member.
##
## The squad is built and bound as a match's (`s.squads`, a puppet standing in for the human
## leader). At the Terrace house's (bare) back door, north of it: the human orders `point` (beside
## the door) and `far` (held still in the garden, `speed` 0) to stack, quiet, go-when-ready, and is
## killed at once. `joiner`, the sergeant, leads from then on (LD4), deciding on its own, and the
## stack order is carried to its end (LD26). The point stands in its slot about 15 s; then `far` is
## let go, and only then does `joiner`, unordered, take the quiet ENTER on the same door on its own
## (scripted Von, held back until then) and claim behind them, from the garden north of the living
## room, so it reaches its slot about 2 s after `far`: well within 6 s of the last ordered member,
## long after the point's own 6 s, and its own approach well under `entry_approach_time` (it never
## claims and then stands still). Its claim is an AI leader's own, which rallies only members
## holding no order (LD24: nobody here) and holds up no ordered stack (only the human leader is
## waited for, D22). The point may slice the pie meanwhile, but must not cross (radio `going_in`)
## before the joiner is ready.
##
## Scripted Von (SEARCH > ENTER > the back door: the joiner's own choice; the ordered members' order
## level asks nothing), every ask failing (Von down: the joiner holds steady) until `far` is let go.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const ORDERED := [&"point", &"far"]
## How long (s) the point stands in its slot before the far member is let go: well past
## `entry_ready_timeout`.
const POINT_ALONE := 15.0
## The joiner's grace (`entry_ready_timeout`), counted from the last ordered member's arrival.
const GRACE := 6.0
const WALK_SPEED := 150.0
## Where the joiner starts: outside, north of the living room, about 2 s of walking farther from its
## slot than `far` is from its own.
const JOINER_START := Vector2(250, -120)
## How long (s) the joiner may take to claim once its ENTER is answered: before `far` reaches its
## slot, so the stack waits for it.
const JOINER_CLAIM := 2.0


func describe() -> Dictionary:
	return {
		"name": "An ordered stack waits for a joiner from its last ordered member's arrival",
		"description": "An unordered joiner reaching its slot 2 s after the last ordered member is "
			+ "waited for, though the point has stood in its slot 15 s: entry_ready_timeout "
			+ "counts from the moment every ordered member is in its slot (LD17).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"point", Vector2(960, 60), 0.4)
	Entry.npc(s, &"far", Vector2(1150, -150), 0.45, {}, { "speed": 0.0 })
	Entry.npc(s, &"joiner", JOINER_START, 0.7, {}, { "rank": 1 })
	s.set_static(DecisionStub, &"fail", true)
	s.actor(&"lead", &"puppet", Vector2(1300, 700), { "faction": &"invader" })
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var door: Dictionary = Entry.BACK
	var squad := t.squad(&"invader")
	var order := Order.stack_order(
		squad,
		ORDERED.map(func(id): return t.actor(id)),
		Order.BACK_NORTH,
		"quiet",
		false,
	)
	if not t.require(not order.is_empty(), "the squad posts the stack order (issue)"):
		return
	t.actor(&"lead").take_damage(1.0e9)
	if not t.require(
			squad.leader() == t.actor(&"joiner"),
			"set-up: the human leader is killed and the sergeant, the joiner, leads (LD4; %s)"
				% str(squad.leader()),
	):
		return
	if not await _point_ready(t, door):
		return
	var point_ready := Entry.first_call_time(t, "ready", &"point", door["id"])

	if not await _point_holds(t, door, point_ready):
		return
	if not await _joiner_claims(t, door):
		return
	await _joiner_waited_for(t, door, point_ready)


## The point and the far member claim the back door, and the point is ready in its slot. False when
## either never happens.
func _point_ready(t: TestContext, door: Dictionary) -> bool:
	var claimed := func():
		return ORDERED.all(func(id): return Entry.first_call_time(t, "claim", id, door["id"]) < INF)
	if not t.require(
			await t.until(claimed, 8.0),
			"the point and the far member claim the back door",
	):
		return false
	return t.require(
		await t.until(
			func(): return Entry.first_call_time(t, "ready", &"point", door["id"]) < INF,
			10.0,
		),
		"the point is ready in its slot",
	)


## The set-up: the point holds `POINT_ALONE` s for the far member while it is held, and the joiner
## claims nothing while Von is down. False when either does not hold.
func _point_holds(t: TestContext, door: Dictionary, point_ready: float) -> bool:
	var crossed := func(): return Entry.first_call_time(t, "going_in", &"point", door["id"]) < INF
	if await t.until(crossed, POINT_ALONE):
		t.require(
			false,
			("set-up: the point holds for the ordered far member while it is held (it went in at "
					+ "%.1f s, ready at %.1f s)")
				% [Entry.first_call_time(t, "going_in", &"point", door["id"]), point_ready],
		)
		return false
	return t.require(
		Entry.first_call_time(t, "claim", &"joiner") == INF,
		"set-up: the joiner claims nothing while Von is down (it holds steady)",
	)


## The far member is let go and Von answers: the joiner claims the back door, unordered, behind
## the point and the far member. False when it does not.
func _joiner_claims(t: TestContext, door: Dictionary) -> bool:
	t.actor(&"far").set("speed", WALK_SPEED)
	# Von answers now: the joiner takes the quiet ENTER on the back door.
	DecisionStub.fail = false
	var joiner_claimed := func():
		return Entry.first_call_time(t, "claim", &"joiner", door["id"]) < INF
	if not t.require(
			await t.until(joiner_claimed, JOINER_CLAIM),
			"set-up: the joiner claims the back door once Von answers",
	):
		return false
	if not t.require(
			Order.ordered_claims(t, t.actor(&"joiner"), door["id"]).is_empty(),
			"set-up: the joiner's claims carry no order (unordered)",
	):
		return false
	var order_of := Order.by_slot(t, ORDERED + [&"joiner"], door["id"])
	return t.require(
		order_of == [&"point", &"far", &"joiner"],
		"set-up: the stack is point, far, joiner by slot (%s)" % str(order_of),
	)


## The far member reaches its slot, then the joiner within the grace; the point, ready since
## `point_ready`, goes in only after the joiner is ready.
func _joiner_waited_for(t: TestContext, door: Dictionary, point_ready: float) -> void:
	var far_ready := func():
		return Entry.first_call_time(t, "ready", &"far", door["id"]) < INF
	if not t.require(await t.until(far_ready, 15.0), "the far member, let go, reaches its slot"):
		return
	var last_ordered := Entry.first_call_time(t, "ready", &"far", door["id"])
	if not t.require(
			Entry.first_call_time(t, "ready", &"joiner", door["id"]) == INF,
			"set-up: the joiner is still on its way when the far member is ready",
	):
		return
	var joiner_ready := func():
		return Entry.first_call_time(t, "ready", &"joiner", door["id"]) < INF
	var joined := await t.until(joiner_ready, GRACE + 4.0)
	var joiner_at := Entry.first_call_time(t, "ready", &"joiner", door["id"])
	if not t.require(
			joined and joiner_at - last_ordered <= GRACE - 1.0,
			("set-up: the joiner reaches its slot within the grace of the last ordered member's "
					+ "arrival (%.1f s after it)") % (joiner_at - last_ordered),
	):
		return
	var crossed := func(): return Entry.first_call_time(t, "going_in", &"point", door["id"]) < INF
	await t.until(crossed, 20.0)
	var point_in := Entry.first_call_time(t, "going_in", &"point", door["id"])
	t.check(
		point_ready <= last_ordered - POINT_ALONE + 1.0,
		"premise: the point stood in its slot far longer than the grace (%.1f s)"
			% (last_ordered - point_ready),
	)
	t.check(
		point_in >= joiner_at,
		("the point waits for the joiner: it goes in (going_in) after the joiner is ready (the "
				+ "last ordered member ready at %.2f s, the joiner at %.2f s, the point went in "
				+ "at %.2f s)") % [last_ordered, joiner_at, point_in],
	)
	t.check(point_in < INF, "and then the stack goes in (the point's going_in)")
