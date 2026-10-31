extends GameTest
## D38 (`docs/leadership.md`, LD13): a held stack's member whose fight walks it up to the doorway it
## is held at, to fire through it, stops outside: the entry guard never sends it into the room it is
## held to enter. One invader is ordered (quiet, held for the go) to stack on the bare Terrace
## house's back door from its north side; once it stands ready, a defender walks into its view in
## the kitchen and fires at it, and it advances halfway to the defender, to a point outside the
## kitchen by the doorway. It fights from there: it never stands in the kitchen, never radios going
## in by the back door, and makes no claim there but its order's own.
##
## Scripted Von (COMBAT > ADVANCE > halfway): the subject is the walk, not the decision. The test
## requires that the advance's walk ends outside the kitchen within reach of the doorway (a walk
## into the doorway's view to fire through it, which D38 leaves as it is).
##
## Switches and props: the defender is a puppet that cannot die, as is the invader (the premise is
## the walk, not the fight); `ai.hostile_on_trespass` off, so the defender is the invader's only
## reason to fight; the squad's leader, a puppet far out in the garden, only issues the order.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const HeldFight := preload("res://tests/_ai/held_fight_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
## The advance Von is scripted to pick.
const ADVANCE := "advance/advance_half"
## Within this (px) of the doorway's centre the advance's goal is up to the doorway.
const AT_DOOR := 90.0
## How long (s) the advance is watched.
const WATCH := 15.0


func describe() -> Dictionary:
	return {
		"name": "A held member's advance to the doorway stays out of the held room",
		"description": "An invader held at the back door for its leader's go advances on a "
			+ "defender in the kitchen to a point by the doorway: it fights from there and is "
			+ "never sent into the kitchen by entry (D38).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "combat", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	# Back to cover beside the stack first, as the slot offers no advance; from there, halfway.
	s.von_script([
		{ "pick": "advance_half" },
		{ "pick": "advance" },
		{ "pick": "fall_cover" },
		{ "pick": "retreat" },
	])
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(960, 60), { "max_health": 1_000_000.0 })
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
			await t.until(func(): return Order.all_called(t, [&"a"], "ready", door), 30.0),
			"set-up: the invader stands ready in its slot",
	):
		return
	var walk := await _fight(t, a)
	if not t.require(
			not walk["goals"].is_empty(),
			"premise: seeing the defender, the invader advances (act %s)" % Follow.act(a),
	):
		return
	if not t.require(
			walk["goals"].any(func(g): return (
				not Entry.in_room(Entry.BACK, g) and g.distance_to(Entry.BACK["pos"]) <= AT_DOOR
			)),
			"premise: the advance walks up to the doorway, outside the kitchen (goals %s)"
				% str(walk["goals"]),
	):
		return
	_check_stayed_out(t, walk)


## The advance `walk` (`_fight`) stopped outside: the invader never stood in the kitchen, never
## radioed going in by the back door, and made no claim there but under its order.
func _check_stayed_out(t: TestContext, walk: Dictionary) -> void:
	var door: String = Entry.BACK["id"]
	t.check(
		walk["in_room"] == INF,
		"the invader never stood in the kitchen while held (first at %s s, at %s)"
			% [str(walk["in_room"]), str(walk["at"])],
	)
	t.check(
		Entry.calls(t, "going_in", &"a").filter(
			func(d): return String(d.get("opening", "")) == door
		).is_empty(),
		"it never radioed going in by the back door while held",
	)
	var unordered := Entry.calls(t, "", &"a").filter(func(d): return (
		String(d.get("opening", "")) == door and String(d.get("order_id", "")) == ""
	))
	t.check(
		unordered.is_empty(),
		"it made no claim on the back door but its order's (unordered: %s)"
			% str(unordered.map(func(d): return d.get("entry_step", ""))),
	)


## The defender walks into view in the kitchen and fires at `a` every `HeldFight.FIRE_EVERY` s for
## `WATCH` s, while `a`'s advance is watched: the goals its advance walked to (`goals`, each once)
## and the first time it stood in the kitchen (`in_room`, INF for never) and where (`at`).
func _fight(t: TestContext, a: Node2D) -> Dictionary:
	HeldFight.arm(t, &"d")
	var d := t.puppet(&"d")
	d.walk_to(HeldFight.IN_VIEW)
	var next := [0.0]
	var out := { "goals": [], "in_room": INF, "at": Vector2.INF }
	var watch := func() -> bool:
		if d.has_arrived() and t.time >= next[0]:
			next[0] = t.time + HeldFight.FIRE_EVERY
			d.aim_at(a)
			d.shoot()
		if Follow.act(a).ends_with(ADVANCE):
			var goal := Follow.walk_target(a).round()
			if not out["goals"].has(goal):
				out["goals"].append(goal)
		if out["in_room"] == INF and Entry.in_room(Entry.BACK, a.global_position):
			out["in_room"] = snappedf(t.time, 0.01)
			out["at"] = a.global_position.round()
		return false
	await t.until(watch, WATCH)
	return out
