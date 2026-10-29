extends GameTest
## The defenders' ambush rule (#128) before contact, the scenario: a defender crew of three in a
## one-room house (its front door, in the south wall, opens straight into the room), declared as a
## match declares its squads (`s.squads`: the first spawned leads), and an invader walking up and
## down outside the north wall, within the leader's hearing and out of every defender's sight. The
## leader hears the steps and declines the lead (INVESTIGATE – STAY: a lead outside the house,
## Von's call); its callout carries the lead's spot (`lead_pos`), so the leader orders the ambush of
## the doorway into its room an attack from there comes through, the front door, to itself and the
## next member, and both are at their posts (`in_position`) before any defender has seen the
## invader.
##
## One room, so the crew has nothing to search: in the Terrace house its search walks the leader
## from room to room, and Von keeps that plan until a walk ends. Real Von, the whole pipeline.
## Required first (set-up findings otherwise): the leader heard the steps and took INVESTIGATE –
## STAY. Premise: the invader is a puppet (the thing to be heard: a real invader would come in),
## unkillable, that never shoots.

const Order := preload("res://tests/_ai/order_probe.gd")
const ROOM := Rect2(0, 0, 600, 400)
const FRONT_DOOR := "door_300_400"
const CREW := [&"d1", &"d2", &"d3"]
## The invader's lane, outside the north wall: within earshot of the leader, far from the door.
const LANE := [Vector2(150, -50), Vector2(450, -50)]


func describe() -> Dictionary:
	return {
		"name": "A defender crew is at its ambush posts before contact",
		"description": "An invader walks outside a one-room house; the leader hears it, "
			+ "declines the lead (STAY), and orders itself and the next member to ambush the "
			+ "doorway its attack would come by; both are posted before anyone sees it (#128).",
		"tags": ["ai", "investigate", "hearing", "leadership", "squad", "ambush", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(
		[{ "key": "living_room", "type": "living_room", "rect": ROOM, "floor": "oak_planks" }],
		[{ "pos": Vector2(300, 400), "width": 80.0 }],
	)
	s.actor(&"d1", &"defender", Vector2(300, 120))
	s.actor(&"d2", &"defender", Vector2(360, 180))
	s.actor(&"d3", &"defender", Vector2(240, 180))
	s.actor(&"inv", &"puppet", LANE[0], { "faction": &"invader", "max_health": 1_000_000.0 })
	s.squads()


func run(t: TestContext) -> void:
	var squad: Node = t.world.squad(&"household")
	var d1 := t.actor(&"d1")
	if not t.require(
		squad != null and squad.leader() == d1,
		"premise: the crew's squad, led by d1",
	):
		return
	var crew: Array = CREW.map(func(id): return t.actor(id))
	var order := await _ordered(t, d1)
	if order.is_empty():
		return
	t.expect_eq(String(order.get("opening", "")), FRONT_DOOR, "of the front door")
	t.expect_eq(String(order.get("room", "")), "living_room", "from the leader's room")
	t.expect_eq(_names(order.get("to", [])), ["d1", "d2"], "to the leader and the next member")
	var posted := func():
		_pace(t)
		return [&"d1", &"d2"].all(
			func(id): return not _steps(t, t.actor(id), order, "in_position").is_empty()
		)
	t.check(await t.until(posted, 30.0), "the leader and d2 reach their posts (in_position)")
	var seen := _sightings(t, crew)
	t.check(
		seen.is_empty(),
		"no defender has seen the invader by then (COMBAT callouts: %s)"
			% [seen.map(func(c): return c.get("path"))],
	)


## Walk the invader up and down its lane until the leader takes INVESTIGATE – STAY and the squad
## orders an ambush: the order, or {} when the test ended (a set-up finding).
func _ordered(t: TestContext, lead: Node2D) -> Dictionary:
	if not await _stayed(t, lead):
		return {}
	var ordered := func():
		_pace(t)
		return not _ambushes(t).is_empty()
	if not t.require(await t.until(ordered, 3.0), "the leader orders an ambush"):
		return {}
	return _ambushes(t)[0]


## Walk the invader up and down its lane until the leader takes INVESTIGATE – STAY: whether it did,
## its callout placing the lead (`lead_pos`).
func _stayed(t: TestContext, lead: Node2D) -> bool:
	var stayed := func():
		_pace(t)
		return not _stays(t, lead).is_empty()
	if not t.require(
			await t.until(stayed, 40.0),
			"the leader hears the steps and declines the lead: INVESTIGATE – STAY (act %s)"
				% t.controller(&"d1", &"current_act").current_act(),
	):
		return false
	var said: Dictionary = _stays(t, lead)[0]
	return t.require(
		said.get("lead_pos", Vector2.INF) is Vector2 and (said["lead_pos"] as Vector2).is_finite(),
		"its callout places the lead (lead_pos %s)" % [said.get("lead_pos")],
	)


## Keep the invader walking its lane: on to the other end once it is at one.
func _pace(t: TestContext) -> void:
	var walker := t.puppet(&"inv")
	if walker.has_arrived():
		var p: Vector2 = t.actor(&"inv").global_position
		walker.walk_to(LANE[1] if p.distance_to(LANE[0]) < p.distance_to(LANE[1]) else LANE[0])


## The leader's INVESTIGATE – STAY callouts.
func _stays(t: TestContext, lead: Node) -> Array:
	return t.events_of(&"callout", func(c): return (
		c.get("speaker") == lead and String(c.get("path", "")).begins_with("investigate/stay")
	))


## The COMBAT callouts of the crew `crew`.
func _sightings(t: TestContext, crew: Array) -> Array:
	return t.events_of(&"callout", func(c): return (
		crew.has(c.get("speaker")) and String(c.get("path", "")).begins_with("combat")
	))


## The ambush orders posted so far.
func _ambushes(t: TestContext) -> Array:
	return Order.orders(t).filter(func(o): return String(o.get("kind", "")) == Order.AMBUSH)


## The `step` callouts `member` radioed about `order`.
func _steps(t: TestContext, member: Node, order: Dictionary, step: String) -> Array:
	return Order.progress(t, step, member).filter(
		func(c): return str(c.get("order_id", "")) == str(order.get("id", "")),
	)


## The names of `nodes`, sorted.
func _names(nodes: Array) -> Array:
	var out := nodes.map(func(n): return String(n.name) if n is Node else str(n))
	out.sort()
	return out
