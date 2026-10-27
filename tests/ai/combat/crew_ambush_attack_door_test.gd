extends GameTest
## The defenders' ambush rule (#128), the scenario: a defender crew of three in the bare Terrace
## house's living room, declared as a match declares its squads (`s.squads`: the first spawned
## leads), and an invader come in by the front door (it starts in the hall's west end, by the door:
## an invader still outside slices the pie of the front door for some seconds, long enough for the
## crew's own search to take its leader into the hall). Once the crew's radio places it (a COMBAT
## callout: the invader seen, or where its shots came from), the leader orders the ambush of the
## doorway into its room the attack comes through, the hall's doorway into the living room
## (`door_150_360`), to itself and the next member; the last spawned, the rear guard, holds no order
## and follows. Each of the two holds the ambush at its post (`in_position`), or, in contact as it
## takes the order up, ends it `done` at once (D18).
##
## Real Von, the whole pipeline. Required first (set-up findings otherwise): the radio places the
## invader, and the leader is still in the living room when it orders. Premise: the
## defenders are unkillable (no death moves the lead), so the fight ends with the invader's.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
## The doorway into the living room the invader's attack from the hall comes through.
const HALL_DOOR := "door_150_360"
const CREW := [&"d1", &"d2", &"d3"]
const TOUGH := 1_000_000.0


func describe() -> Dictionary:
	return {
		"name": "A defender crew ambushes the doorway an invader comes through",
		"description": "An invader comes in by the front door; once a defender sees it in the "
			+ "hall, the leader orders itself and the next member to ambush the hall's doorway "
			+ "into its room, the last spawned kept back as rear guard, following (#128).",
		"tags": ["ai", "combat", "leadership", "squad", "order", "ambush", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"d1", &"defender", Vector2(240, 180), { "max_health": TOUGH })
	s.actor(&"d2", &"defender", Vector2(320, 250), { "max_health": TOUGH })
	s.actor(&"d3", &"defender", Vector2(380, 120), { "max_health": TOUGH })
	s.actor(&"inv", &"invader", Vector2(30, 415))
	s.squads()


func run(t: TestContext) -> void:
	var squad: Node = t.world.squad(&"household")
	var d1 := t.actor(&"d1")
	if not t.require(
		squad != null and squad.leader() == d1,
		"premise: the crew's squad, led by d1",
	):
		return
	var at := await _first_ambush(t, d1)
	if at.is_empty():
		return
	var order: Dictionary = at["order"]
	t.expect_eq(String(order.get("opening", "")), HALL_DOOR, "of the hall's doorway")
	t.expect_eq(String(order.get("room", "")), "living_room", "from the leader's room")
	t.expect_eq(_names(order.get("to", [])), ["d1", "d2"], "to the leader and the next member")
	var d3 := t.actor(&"d3")
	t.check(
		Order.member_view(squad, d3).get("order", {}).is_empty() and squad.follows(d3),
		"d3, the last spawned of three, is the rear guard: no order, it follows",
	)
	for id in [&"d1", &"d2"]:
		var m := t.actor(id)
		var holds := func(): return not _steps(t, m, order, ["in_position", "done"]).is_empty()
		t.check(
			await t.until(holds, 25.0),
			"%s holds the ambush at its post, or ends it done in contact (steps %s)"
				% [id, _steps(t, m, order, [])],
		)


## Wait for the crew's radio to place the invader and the first ambush order after it, keeping the
## room the leader `lead` stands in until the order: `{ order, room }`, or {} when the test ended (a
## set-up finding: nobody placed it, no order, or the leader out of the living room by then).
func _first_ambush(t: TestContext, lead: Node2D) -> Dictionary:
	var crew: Array = CREW.map(func(id): return t.actor(id))
	if not t.require(
			await t.until(func(): return not _sightings(t, crew).is_empty(), 40.0),
			"the crew's radio places the invader (a COMBAT callout)",
	):
		return {}
	var room_then := { "key": _room_of(lead) }
	var ordered := func():
		if _ambushes(t).is_empty():
			room_then["key"] = _room_of(lead)
			return false
		return true
	if not t.require(await t.until(ordered, 3.0), "the leader orders an ambush"):
		return {}
	if not t.require(
			room_then["key"] == "living_room",
			"set-up: the leader was still in the living room (%s)" % room_then["key"],
	):
		return {}
	return { "order": _ambushes(t)[0], "room": room_then["key"] }


## The ambush orders posted so far.
func _ambushes(t: TestContext) -> Array:
	return Order.orders(t).filter(func(o): return String(o.get("kind", "")) == Order.AMBUSH)


## The COMBAT callouts of the crew `crew` that place a hostile.
func _sightings(t: TestContext, crew: Array) -> Array:
	return t.events_of(&"callout", func(c): return (
		crew.has(c.get("speaker"))
		and String(c.get("path", "")).begins_with("combat")
		and c.get("target_pos", Vector2.INF) is Vector2
		and (c["target_pos"] as Vector2).is_finite()
	))


## The progress steps `member` radioed about `order`, those of `steps` only (all with []).
func _steps(t: TestContext, member: Node, order: Dictionary, steps: Array) -> Array:
	return Order.progress(t, "", member).filter(
		func(c): return (
			str(c.get("order_id", "")) == str(order.get("id", ""))
			and (steps.is_empty() or steps.has(String(c.get("order_step", ""))))
		),
	).map(func(c): return String(c.get("order_step", "")))


## The key of the Terrace room `c` stands in ("" for none).
func _room_of(c: Node2D) -> String:
	var p := c.global_position
	if Maps.HOUSE_LIVING.has_point(p):
		return "living_room"
	if Maps.HOUSE_KITCHEN.has_point(p):
		return "kitchen"
	return "hall" if Maps.HOUSE_HALL.has_point(p) else ""


## The names of `nodes`, sorted.
func _names(nodes: Array) -> Array:
	var out := nodes.map(func(n): return String(n.name) if n is Node else str(n))
	out.sort()
	return out
