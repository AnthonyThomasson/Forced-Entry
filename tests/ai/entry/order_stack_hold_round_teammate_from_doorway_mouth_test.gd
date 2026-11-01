extends GameTest
## Issue #154, D38: a held stack's member left just outside the doorway of the room it is held to
## enter goes round the teammate resting in slot 1 back to its own slot beyond it. At rest, its own
## body is carved out of the steering map, so the way round the teammate starts where that map puts
## it, in the doorway's mouth just across the wall plane: that start was read as a way into the room
## it keeps out of, every way round was refused, and it stood held behind the teammate for good
## (the flake of `order_stack_hold_fights_stack_side`, after a fight left it there).
##
## Scripted Von (COMBAT > ENGAGE > fire from here; then the ORDER node's entry): the subject is the
## walk, not the decision. One invader is ordered (quiet, held for the go) to stack on the bare
## Terrace house's back door from its north side. A teammate (a puppet) stands in the north side's
## slot 1 and radios its claim there, so the invader's slot is slot 2, beyond the teammate along
## the wall. Once the invader stands ready in it, it is set down just outside the doorway, by its
## north jamb; a defender in the kitchen shows itself through the doorway and is gone again, and
## once that fight lapses the invader's order walks it back to its slot from there.
##
## Switches and props: the invader is set down at a spot of `MOUTH` once ready and stands still
## there (its `movement.speed` 0) until its order has taken over again after the fight and the
## steering map's way round the teammate starts across the wall plane (the premise: where a fight's
## walk leaves a held member, at rest, as the flake's stood; no walk of its own takes it there on
## purpose), then walks at its speed again; the teammate is a
## puppet that never moves and keeps its claim on the radio (the premise: slot 1 taken by a body at
## rest between the invader and its slot); the defender is a puppet that fires at the invader until
## it fights back, then is taken beyond sight (the premise: a fight, so the order's walk begins
## afresh where it stands);
## nobody can die (the premise is the walk); `ai.hostile_on_trespass` off, so the defender is fought
## only once seen; the squad's leader, a puppet far out in the back garden, only issues the order.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
const HeldFight := preload("res://tests/_ai/held_fight_probe.gd")
## Where the invader starts: in the back garden, north-east of the door (as the flake's members).
const START := Vector2(960, 60)
## Where it is set down once ready, tried in turn: 30 px out of the back doorway, by its north jamb
## (beside where the flake's member stood, (867, 164)), at spots its own body, carved out of the
## steering map at rest, leaves that map's way round the teammate starting across the doorway's wall
## plane, as the flake's did.
const MOUTH := [Vector2(870, 174), Vector2(864, 180), Vector2(870, 180)]
## The north side's slot 1, where the teammate stands (the flake's teammate stood there).
const SLOT_1 := Vector2(870, 127)
## The side of the back door its north half is on, as the radio claims say it.
const NORTH := 1
## Within this (px) of its slot's point a member stands in its slot (an NPC's 6 px slot reach,
## `docs/tactical-entry.md` E2, and a few px).
const SLOT_NEAR := 10.0
## How long (s) the defender has to be seen, and the fight to lapse once it is gone.
const FIGHT_WITHIN := 20.0
## How long (s) the invader has to reach its slot once its order walks it back: a short walk round
## the teammate.
const WITHIN := 10.0
## How long (s) the steering map has to carve the invader's body once it stands still (it is
## re-baked on an interval).
const CARVE_WITHIN := 3.0
## The invader's walking speed (px/s), given back once its walk back is to begin (a character's
## default, `movement:speed`).
const WALK_SPEED := 150.0
## How often (s) the teammate radios its claim (inside the radio's heartbeat).
const CLAIM_EVERY := 1.0


func describe() -> Dictionary:
	return {
		"name": "A held member goes round its teammate from the doorway's mouth",
		"description": "An invader held at the back door for go, left just outside the doorway "
			+ "after a fight, goes round the teammate in slot 1 back to its slot 2, never into "
			+ "the kitchen (D38).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }, { "pick": "fire_here" }])
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", START, { "max_health": 1_000_000.0 })
	s.actor(
		&"mate",
		&"puppet",
		SLOT_1,
		{ "faction": &"invader", "max_health": 1_000_000.0, "facing": Vector2.LEFT },
	)
	s.actor(
		&"lead",
		&"puppet",
		Vector2(1400, 800),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })
	HeldFight.defender(s, &"d")


func run(t: TestContext) -> void:
	var a := t.actor(&"a")
	var door: String = Entry.BACK["id"]
	var claim := _claimer(t)
	claim.call()
	await t.seconds(1.5)
	var order := Order.stack_order(t.world.squad(&"invader"), [a], Order.BACK_NORTH, "quiet", true)
	if not t.require(not order.is_empty(), "the squad posts the held stack order (issue)"):
		return
	var ready := func() -> bool:
		claim.call()
		return Order.all_called(t, [&"a"], "ready", door)
	if not t.require(await t.until(ready, 40.0), "set-up: the invader stands ready in its slot"):
		return
	var slot: Vector2 = Entry.entry(Follow.brain_of(a)).get("stack_point", Vector2.INF)
	if not t.require(
			await _fight_at_mouth(t, a, claim),
			"set-up: set down by the doorway, the invader fights the defender seen through it, "
				+ "then its order takes over again (act %s)" % Follow.act(a),
	):
		return
	var start := await _route_start(t, a, slot, claim)
	if not t.require(
			start.x < Entry.BACK["pos"].x,
			"premise: at rest by the doorway, the way round the teammate to its slot starts across "
				+ "the doorway's wall plane (at %s from %s)" % [str(start), str(a.global_position)],
	):
		return
	a.movement.speed = WALK_SPEED
	var out := await _walk_back(t, a, claim)
	if not t.require(
			out["slot"] == 2 and out["point"].distance_to(SLOT_1) > SLOT_NEAR * 3.0,
			"premise: with the teammate's claim on slot 1, the invader's slot is 2, beyond it "
				+ "(slot %d at %s)" % [out["slot"], str(out["point"])],
	):
		return
	t.check(
		out["back"] != INF,
		"the invader went round the teammate back into its slot within %.0f s (now at %s)"
			% [WITHIN, str(a.global_position.round())],
	)
	t.check(
		out["in_room"] == INF,
		"it never stood in the kitchen while held (first at %s s)" % str(out["in_room"]),
	)


## Where the way round bodies at rest from `a`, standing still at each spot of `MOUTH` in turn, to
## `slot` starts, once the steering map has had `CARVE_WITHIN` s to carve `a`'s body there
## (`NavBuilder.route` on the steering map, interface 9): the first start across the doorway's wall
## plane, else the last.
func _route_start(t: TestContext, a: Node2D, slot: Vector2, claim: Callable) -> Vector2:
	var steer := NavBuilder.steering_map(a.get_world_2d().navigation_map)
	var start := [Vector2.INF]
	var carved := func() -> bool:
		claim.call()
		var route := NavBuilder.route(steer, a.global_position, slot)
		start[0] = route[0] if not route.is_empty() else Vector2.INF
		return start[0].x < Entry.BACK["pos"].x
	for spot in MOUTH:
		a.global_position = spot
		if await t.until(carved, CARVE_WITHIN):
			break
	return start[0]


## A callable that has the teammate radio its claim on the north side's slot 1 every
## `CLAIM_EVERY` s.
func _claimer(t: TestContext) -> Callable:
	var mate := t.actor(&"mate")
	var next := [0.0]
	return func() -> void:
		if t.time >= next[0]:
			next[0] = t.time + CLAIM_EVERY
			Entry.radio_claim(mate, Entry.BACK["id"], "kitchen", Vector2i(1, NORTH), 0)


## Set `a` down at `MOUTH`'s first spot, standing still, while the defender walks into its view in
## the kitchen and fires at it every `HeldFight.FIRE_EVERY` s until `a` fights it, then is taken
## beyond sight; true once `a`'s order has taken over again.
func _fight_at_mouth(t: TestContext, a: Node2D, claim: Callable) -> bool:
	HeldFight.arm(t, &"d")
	var d := t.puppet(&"d")
	d.walk_to(HeldFight.IN_VIEW)
	var state := { "fought": false, "next": 0.0 }
	a.global_position = MOUTH[0]
	a.movement.speed = 0.0
	var fight := func() -> bool:
		claim.call()
		if not state["fought"] and d.has_arrived() and t.time >= state["next"]:
			state["next"] = t.time + HeldFight.FIRE_EVERY
			d.aim_at(a)
			d.shoot()
		var act := Follow.act(a)
		if act.begins_with("combat/") and not state["fought"]:
			state["fought"] = true
			d.stop()
			t.actor(&"d").global_position = HeldFight.OFFSTAGE
		return state["fought"] and act.begins_with("order/stack")
	return await t.until(fight, FIGHT_WITHIN)


## `a`'s walk back to its slot, watched `WITHIN` s: its slot and slot point (`slot`, `point`), when
## it first stood in the kitchen (`in_room`, INF for never) and when it stood in its slot (`back`,
## INF for never).
func _walk_back(t: TestContext, a: Node2D, claim: Callable) -> Dictionary:
	var out := { "slot": 0, "point": Vector2.INF, "in_room": INF, "back": INF }
	var walk := func() -> bool:
		claim.call()
		var e := Entry.entry(Follow.brain_of(a))
		if String(e.get("opening", "")) == Entry.BACK["id"]:
			out["slot"] = int(e.get("slot", 0))
			out["point"] = e.get("stack_point", Vector2.INF)
		if out["in_room"] == INF and Entry.in_room(Entry.BACK, a.global_position):
			out["in_room"] = snappedf(t.time, 0.01)
		if (out["point"] != Vector2.INF
				and a.global_position.distance_to(out["point"]) <= SLOT_NEAR):
			out["back"] = snappedf(t.time, 0.01)
			return true
		return false
	await t.until(walk, WITHIN)
	return out
