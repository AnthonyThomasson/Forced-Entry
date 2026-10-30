extends GameTest
## D31 (`docs/leadership.md`, LD13): a held stack's member standing in the doorway of the room it is
## held to enter is not in that room: a fight's walk from there whose plain way runs through the
## room goes round it. One invader, which has seen the living room through the back door, is ordered
## (quiet, held for the go) to stack on the bare Terrace house's back door from its north side. Once
## it stands ready, held, it stands in the back doorway, just on the kitchen's side of the wall
## plane; a defender in its view in the kitchen, its aim already on it, fires, and it falls back to
## the living room from the doorway: the plain way there runs through the kitchen. It goes round the
## house, never on into the kitchen past the doorway.
##
## Scripted Von (COMBAT > RETREAT > the living room): the subject is the walk, not the decision.
##
## Switches and props: the invader is kept in the doorway once held, frame by frame, until its
## retreat sets out (the premise: a held member standing there as it falls back, which a fight's
## walk or a shove can leave it in, and no walk of its own takes it to on purpose, as the guard
## keeps it out); the defender is a puppet that cannot die, as is the
## invader (the premise is the walk, not the fight); `ai.hostile_on_trespass` off, as in the other
## held-fight tests, so the household is hostile by its shots only; the squad's leader, a puppet far
## out in the garden, only issues the order.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const HeldFight := preload("res://tests/_ai/held_fight_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
## Where the invader stands: in the back doorway, 4 px on the kitchen's side of its plane.
const START := Vector2(836, 190)
## How deep (px) into a room a walker still stands in the doorway it is by: half the wall's
## thickness (12 px) and a body's radius (14 px), the spec's measure.
const DOORWAY := 20.0
## Where the defender stands: in the kitchen, in front of the invader (in its view as it looks in)
## and clear of its line to the living room's doorway.
const DEFENDER := Vector2(700, 260)
## The retreat Von is scripted to pick.
const RETREAT := "retreat/fall_living_room"
## How long (s) the retreat is watched.
const WATCH := 15.0


func describe() -> Dictionary:
	return {
		"name": "A held member's retreat from the held room's doorway goes round it",
		"description": "An invader standing in the back doorway, held there for its leader's "
			+ "go, falls back to the living room under fire: it goes round the house, never on "
			+ "into the kitchen it is held to enter (D31).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "retreat", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "combat" }, { "pick": "retreat" }, { "pick": "fall_living_room" }])
	s.switch(&"ai.hostile_on_trespass", false)
	# In line with the back door and the living room's doorway: it sees the living room before it
	# stacks, so it knows that room to fall back to.
	s.actor(
		&"a",
		&"invader",
		Vector2(1100, 215),
		{ "max_health": 1_000_000.0, "facing": Vector2.LEFT },
	)
	s.actor(
		&"lead",
		&"puppet",
		Vector2(1400, 800),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })
	Entry.target(s, &"d", DEFENDER, START)


func run(t: TestContext) -> void:
	var a := t.actor(&"a")
	await t.seconds(0.3)
	var order := Order.stack_order(
		t.world.squad(&"invader"),
		[a],
		Order.BACK_NORTH,
		"quiet",
		true,
	)
	if not t.require(not order.is_empty(), "the squad posts the held stack order (issue)"):
		return
	if not t.require(
			await t.until(
				func(): return Order.all_called(t, [&"a"], "ready", Entry.BACK["id"]),
				30.0,
			),
			"set-up: the invader stands ready in its slot",
	):
		return
	HeldFight.arm(t, &"d")
	t.puppet(&"d").aim_at(a)
	await t.frames(2)
	var from := await _shot_at(t, a)
	if not t.require(
			from != Vector2.INF,
			"set-up: under the defender's fire, the invader falls back to the living room (act %s)"
				% Follow.act(a),
	):
		return
	if not t.require(
			_in_doorway(from),
			"premise: it sets out from the back doorway (at %s)" % str(from.round()),
	):
		return
	var walk := await _watch(t, a)
	t.check(
		walk["in_room"] == INF,
		"it never went on into the kitchen past the doorway (first at %s s, at %s; ways %s)"
			% [str(walk["in_room"]), str(walk["at"]), str(walk["ways"])],
	)
	t.check(
		walk["ways"].has("doors"),
		"it went the way round the kitchen (ways %s)" % [walk["ways"]],
	)


## Whether `p` stands in the back doorway: within `DOORWAY` of its wall plane, within its width.
func _in_doorway(p: Vector2) -> bool:
	return (absf(Entry.outward(Entry.BACK, p)) <= DOORWAY
			and absf(Entry.lateral(Entry.BACK, p)) <= float(Entry.BACK["width"]) * 0.5)


## Whether `p` is in the kitchen past the back doorway (deeper than `DOORWAY`).
func _past_doorway(p: Vector2) -> bool:
	return Maps.HOUSE_KITCHEN.has_point(p) and Entry.outward(Entry.BACK, p) < -DOORWAY


## The defender fires at `a` every `HeldFight.FIRE_EVERY` s until `a` falls back to the living room
## (10 s at most), `a` kept at `START` until then: where `a` stood when it did, or INF.
func _shot_at(t: TestContext, a: Node2D) -> Vector2:
	var d := t.puppet(&"d")
	var next := [0.0]
	var fell_back := func() -> bool:
		if Follow.act(a).ends_with(RETREAT):
			return true
		a.global_position = START
		if t.time >= next[0]:
			next[0] = t.time + HeldFight.FIRE_EVERY
			d.aim_at(a)
			d.shoot()
		return false
	if not await t.until(fell_back, 10.0):
		return Vector2.INF
	return a.global_position


## The retreat, watched `WATCH` s: the ways the walk went, in order, each once per change
## (`ways`), and the first time it went on into the kitchen (`in_room`, INF for never) and where.
func _watch(t: TestContext, a: Node2D) -> Dictionary:
	var brain := Follow.brain_of(a)
	var out := { "ways": [], "in_room": INF, "at": Vector2.INF }
	var sample := func() -> bool:
		var way := str(brain.debug_state().get("loco", {}).get("way", ""))
		if out["ways"].is_empty() or out["ways"][-1] != way:
			out["ways"].append(way)
		if out["in_room"] == INF and _past_doorway(a.global_position):
			out["in_room"] = snappedf(t.time, 0.01)
			out["at"] = a.global_position.round()
		return false
	await t.until(sample, WATCH)
	return out
