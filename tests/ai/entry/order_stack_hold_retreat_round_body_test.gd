extends GameTest
## D38 (`docs/leadership.md`, LD13): a held stack's member whose fight walks it to a room behind the
## room it is held to enter goes round that room, though a body at rest stands on its plain way. One
## invader, which has seen the living room through the back door, is ordered (quiet, held for the
## go) to stack on the bare Terrace house's back door from its north side; a teammate (a puppet
## that stands still) stands between its slot and the doorway. Once it stands ready, a defender
## walks into its view in the kitchen and fires at it, and it falls back to the living room: the
## plain way there runs through the kitchen, past the teammate. It goes round the house, never into
## the kitchen, whether it first goes round the teammate or waits short of it.
##
## Scripted Von (COMBAT > RETREAT > the living room): the subject is the walk, not the decision.
## The test requires that the walk met the teammate (its way went `round` or `held`).
##
## Switches and props: the teammate (which never fires) and the defender are puppets that cannot
## die, as is the invader (the premise is the walk, not the fight); the squad's leader, a puppet far
## out in the garden, only issues the order.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const HeldFight := preload("res://tests/_ai/held_fight_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
## Where the teammate stands: on the plain way from the north slot into the doorway.
const MATE := Vector2(862, 160)
## The retreat Von is scripted to pick.
const RETREAT := "retreat/fall_living_room"
## How long (s) the retreat is watched.
const WATCH := 15.0


func describe() -> Dictionary:
	return {
		"name": "A held member's retreat goes round the held room past a body on its way",
		"description": "An invader held at the back door for its leader's go falls back to the "
			+ "living room past a teammate standing on its plain way: it goes round the house, "
			+ "never through the kitchen (D38).",
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
		&"mate",
		&"puppet",
		MATE,
		{ "faction": &"invader", "max_health": 1_000_000.0, "facing": Vector2.UP },
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
	if not t.require(
			await _shot_at(t, a),
			"set-up: seeing the defender, the invader falls back to the living room (act %s)"
				% Follow.act(a),
	):
		return
	var walk := await _watch(t, a)
	if not t.require(
			walk["ways"].has("round") or walk["ways"].has("held"),
			"premise: the walk met the teammate on its way (ways %s)" % [walk["ways"]],
	):
		return
	t.check(
		walk["in_room"] == INF,
		"the invader never stood in the kitchen while held (first at %s s, at %s; ways %s)"
			% [str(walk["in_room"]), str(walk["at"]), str(walk["ways"])],
	)
	t.check(
		walk["ways"].has("doors"),
		"it went the way round the kitchen (ways %s)" % [walk["ways"]],
	)


## The defender walks into view in the kitchen and fires at `a` every `HeldFight.FIRE_EVERY` s
## until `a` falls back to the living room (10 s at most): whether it did.
func _shot_at(t: TestContext, a: Node2D) -> bool:
	HeldFight.arm(t, &"d")
	var d := t.puppet(&"d")
	d.walk_to(HeldFight.IN_VIEW)
	var next := [0.0]
	var fell_back := func() -> bool:
		if d.has_arrived() and t.time >= next[0]:
			next[0] = t.time + HeldFight.FIRE_EVERY
			d.aim_at(a)
			d.shoot()
		return Follow.act(a).ends_with(RETREAT)
	return await t.until(fell_back, 10.0)


## The retreat, watched `WATCH` s: the ways the walk went, in order, each once per change
## (`ways`), and the first time it stood in the kitchen (`in_room`, INF for never) and where (`at`).
func _watch(t: TestContext, a: Node2D) -> Dictionary:
	var brain := Follow.brain_of(a)
	var out := { "ways": [], "in_room": INF, "at": Vector2.INF }
	var sample := func() -> bool:
		var way := str(brain.debug_state().get("loco", {}).get("way", ""))
		if out["ways"].is_empty() or out["ways"][-1] != way:
			out["ways"].append(way)
		if out["in_room"] == INF and Entry.in_room(Entry.BACK, a.global_position):
			out["in_room"] = snappedf(t.time, 0.01)
			out["at"] = a.global_position.round()
		return false
	await t.until(sample, WATCH)
	return out
