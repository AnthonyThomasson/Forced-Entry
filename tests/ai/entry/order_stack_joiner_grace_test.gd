extends GameTest

## LD17 (`docs/leadership.md`, ticket #65 round 2, rule 10): an unordered joiner's grace counts from the last ordered member. An unordered
## member joining an ordered stack (D10) is waited for `entry_ready_timeout` (6 s), counted from the moment every ordered member is in its
## slot, not from the point's own arrival: a point that has stood in its slot far longer than that still waits for a joiner that reaches
## its slot within the grace of the last ordered member.
##
## At the Terrace house's (bare) back door, north of it: the leader (a puppet) orders `point` (beside the door) and `far` (held still in the
## garden, `speed` 0) to stack, quiet, go-when-ready. The point stands in its slot about 15 s; then `far` is let go, and only then does
## `joiner`, unordered, take the quiet ENTER on the same door on its own (scripted Von, held back until then) and claim behind them, from
## the garden north of the living room, so it reaches its slot about 2 s after `far`: well within 6 s of the last ordered member, long
## after the point's own 6 s, and its own approach well under `entry_approach_time` (it never claims and then stands still). The point
## may slice the pie meanwhile, but must not cross (radio `going_in`) before the joiner is ready.
##
## Scripted Von (SEARCH > ENTER > the back door: the joiner's own choice; the ordered members' order level asks nothing), every ask
## failing (Von down: the joiner holds steady) until `far` is let go.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

const ORDERED := [&"point", &"far"]
## How long (s) the point stands in its slot before the far member is let go: well past `entry_ready_timeout`.
const POINT_ALONE := 15.0
## The joiner's grace (`entry_ready_timeout`), counted from the last ordered member's arrival.
const GRACE := 6.0
const WALK_SPEED := 150.0
## Where the joiner starts: outside, north of the living room, about 2 s of walking farther from its slot than `far` is from its own.
const JOINER_START := Vector2(250, -120)
## How long (s) the joiner may take to claim once its ENTER is answered: before `far` reaches its slot, so the stack waits for it.
const JOINER_CLAIM := 2.0


func describe() -> Dictionary:
	return {
		"name": "An ordered stack waits for a joiner from its last ordered member's arrival",
		"description": "An unordered joiner reaching its slot 2 s after the last ordered member is waited for, though the point has stood in its slot 15 s: entry_ready_timeout counts from the moment every ordered member is in its slot (LD17).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"point", Vector2(960, 60), 0.4)
	Entry.npc(s, &"far", Vector2(1150, -150), 0.45, {}, { "speed": 0.0 })
	Entry.npc(s, &"joiner", JOINER_START, 0.7)
	s.set_static(DecisionStub, &"fail", true)
	s.actor(&"lead", &"puppet", Vector2(1300, 700), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var door: Dictionary = Entry.BACK
	var squad := Order.raid(t, ORDERED + [&"joiner"], &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	var order := Order.stack_order(squad, ORDERED.map(func(id): return t.actor(id)), Order.BACK_NORTH, "quiet", false)
	if not t.require(not order.is_empty(), "the squad posts the stack order (issue)"):
		return
	var claimed := func(): return ORDERED.all(func(id): return Entry.first_call_time(t, "claim", id, door["id"]) < INF)
	if not t.require(await t.until(claimed, 8.0), "the point and the far member claim the back door"):
		return
	if not t.require(await t.until(func(): return Entry.first_call_time(t, "ready", &"point", door["id"]) < INF, 10.0), "the point is ready in its slot"):
		return
	var point_ready := Entry.first_call_time(t, "ready", &"point", door["id"])

	var crossed := func(): return Entry.first_call_time(t, "going_in", &"point", door["id"]) < INF
	if await t.until(crossed, POINT_ALONE):
		t.require(false, "set-up: the point holds for the ordered far member while it is held (it went in at %.1f s, ready at %.1f s)"
				% [Entry.first_call_time(t, "going_in", &"point", door["id"]), point_ready])
		return
	if not t.require(Entry.first_call_time(t, "claim", &"joiner") == INF, "set-up: the joiner claims nothing while Von is down (it holds steady)"):
		return
	t.actor(&"far").set("speed", WALK_SPEED)
	DecisionStub.fail = false   # Von answers now: the joiner takes the quiet ENTER on the back door.
	var joiner_claimed := func(): return Entry.first_call_time(t, "claim", &"joiner", door["id"]) < INF
	if not t.require(await t.until(joiner_claimed, JOINER_CLAIM), "set-up: the joiner claims the back door once Von answers"):
		return
	if not t.require(Order.ordered_claims(t, t.actor(&"joiner"), door["id"]).is_empty(), "set-up: the joiner's claims carry no order (unordered)"):
		return
	var order_of := Order.by_slot(t, ORDERED + [&"joiner"], door["id"])
	if not t.require(order_of == [&"point", &"far", &"joiner"], "set-up: the stack is point, far, joiner by slot (%s)" % str(order_of)):
		return
	var far_ready := func():
		return Entry.first_call_time(t, "ready", &"far", door["id"]) < INF
	if not t.require(await t.until(far_ready, 15.0), "the far member, let go, reaches its slot"):
		return
	var last_ordered := Entry.first_call_time(t, "ready", &"far", door["id"])
	if not t.require(Entry.first_call_time(t, "ready", &"joiner", door["id"]) == INF, "set-up: the joiner is still on its way when the far member is ready"):
		return
	var joiner_ready := func():
		return Entry.first_call_time(t, "ready", &"joiner", door["id"]) < INF
	var joined := await t.until(joiner_ready, GRACE + 4.0)
	var joiner_at := Entry.first_call_time(t, "ready", &"joiner", door["id"])
	if not t.require(joined and joiner_at - last_ordered <= GRACE - 1.0,
			"set-up: the joiner reaches its slot within the grace of the last ordered member's arrival (%.1f s after it)" % (joiner_at - last_ordered)):
		return
	await t.until(crossed, 20.0)
	var point_in := Entry.first_call_time(t, "going_in", &"point", door["id"])
	t.check(point_ready <= last_ordered - POINT_ALONE + 1.0, "premise: the point stood in its slot far longer than the grace (%.1f s)" % (last_ordered - point_ready))
	t.check(point_in >= joiner_at, "the point waits for the joiner: it goes in (going_in) after the joiner is ready (the last ordered member ready at %.2f s, the joiner at %.2f s, the point went in at %.2f s)"
			% [last_ordered, joiner_at, point_in])
	t.check(point_in < INF, "and then the stack goes in (the point's going_in)")
