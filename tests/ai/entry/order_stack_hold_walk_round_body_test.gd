extends GameTest
## D31 (`docs/leadership.md`, LD13): a held stack's member whose order walks it to its slot round a
## body at rest on its way never goes round that body by a way into the room it is held to enter.
## One invader, out in the front garden south-west of the bare Terrace house, is ordered (quiet,
## held for the go) to stack on the back door from its north side: its way there goes round the
## house by the west, as the kitchen is kept out of. A teammate (a puppet that stands still) stands
## on that way, along the house's west wall. The shortest way round the teammate runs in by the
## front door, through the hall and the kitchen; the invader never takes it: it never stands in the
## kitchen nor goes into the hall by entry, and claims no doorway but the back door under its
## order.
##
## Scripted Von (no hostile: the ORDER node's entry): the subject is the walk, not the decision.
## The test requires that the walk met the teammate (its way went `round` or `held`).
##
## Switches and props: the teammate (which never moves) and the invader are puppets / NPCs that
## cannot die (the premise is the walk); the squad's leader, a puppet far out in the back garden,
## only issues the order.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
## Where the teammate stands: along the house's west wall, on the way round the house.
const MATE := Vector2(-45, 220)
## How long (s) the walk is watched.
const WATCH := 25.0


func describe() -> Dictionary:
	return {
		"name": "A held member's walk round a body keeps out of the held room",
		"description": "An invader held at the back door for its leader's go walks round the "
			+ "house to its slot past a teammate standing on its way: it never goes round the "
			+ "teammate through the hall and the kitchen (D31).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "movement", "scripted"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.actor(&"a", &"invader", Vector2(-60, 560), { "max_health": 1_000_000.0 })
	s.actor(
		&"mate",
		&"puppet",
		MATE,
		{ "faction": &"invader", "max_health": 1_000_000.0, "facing": Vector2.DOWN },
	)
	s.actor(
		&"lead",
		&"puppet",
		Vector2(1400, 800),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


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
	var door: String = Entry.BACK["id"]
	var other := Entry.calls(t, "", &"a").filter(func(d): return (
		String(d.get("opening", "")) != door or String(d.get("order_id", "")) == ""
	))
	t.check(
		other.is_empty(),
		"it claimed no doorway but the back door under its order (others: %s)"
			% str(other.map(func(d): return [d.get("opening", ""), d.get("entry_step", "")])),
	)


## The walk, watched `WATCH` s: the ways it went, in order, each once per change (`ways`), and the
## first time it stood in the kitchen (`in_room`, INF for never) and where (`at`).
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
