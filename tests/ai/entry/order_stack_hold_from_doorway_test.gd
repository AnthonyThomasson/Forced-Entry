extends GameTest
## D31 (`docs/leadership.md`, LD13): a held stack's member standing in a doorway of the room it is
## held to enter is not in that room: its walk to its slot keeps out of the room as from outside.
## One invader stands in the doorway between the bare Terrace house's hall and its kitchen, just on
## the kitchen's side of the wall plane (within the wall and a body's reach of it), and is ordered
## (quiet, held for the go) to stack on the back door from its north side. The plain way there runs
## through the kitchen and out by the back door; it never takes it: it never goes on into the
## kitchen past the doorway, claims no doorway but the back door under its order, and comes to its
## slot by the way round the house.
##
## Scripted Von (no hostile: the ORDER node's entry): the subject is the walk, not the decision.
##
## Switches and props: the invader cannot die (the premise is the walk); the squad's leader, a
## puppet far out in the back garden, only issues the order.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
## Where the invader stands: in the hall-kitchen doorway, 5 px on the kitchen's side of its plane.
const START := Vector2(690, 355)
## How deep (px) into a room a walker still stands in the doorway it is by: half the wall's
## thickness (12 px) and a body's radius (14 px), the spec's measure.
const DOORWAY := 20.0
## How near (px) the back door's north side the walk must come (its slot is there).
const SLOT_NEAR := 90.0
## How long (s) the walk is watched.
const WATCH := 35.0


func describe() -> Dictionary:
	return {
		"name": "A held member in the held room's doorway walks round it",
		"description": "An invader standing in the hall-kitchen doorway, held at the back door "
			+ "for its leader's go, walks round the house to its slot, never through the "
			+ "kitchen it is held to enter (D31).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "movement", "scripted"],
		"timeout": 50.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.actor(&"a", &"invader", START, { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(1400, 800),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var a := t.actor(&"a")
	if not t.require(
			Maps.HOUSE_KITCHEN.has_point(START) and not _past_doorway(START),
			"premise: the invader stands in the doorway, on the kitchen's side of its plane",
	):
		return
	# The order comes at once: left to itself, the invader would go its own way first.
	await t.frames(2)
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
			not _past_doorway(a.global_position),
			"premise: it still stands in the doorway as the order comes (at %s)"
				% str(a.global_position.round()),
	):
		return
	var walk := await _watch(t, a)
	t.check(
		walk["in_room"] == INF,
		"the invader never went on into the kitchen past the doorway (first at %s s, at %s)"
			% [str(walk["in_room"]), str(walk["at"])],
	)
	t.check(
		walk["near"] != INF,
		"it came to its slot by the back door's north side (ended at %s)"
			% str(a.global_position.round()),
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


## Whether `p` is in the kitchen and clear of the hall-kitchen doorway (deeper than `DOORWAY`).
func _past_doorway(p: Vector2) -> bool:
	return Maps.HOUSE_KITCHEN.has_point(p) and p.y < Maps.DOOR_HALL_KITCHEN.y - DOORWAY


## The walk, watched `WATCH` s: the first time it went on into the kitchen past the doorway
## (`in_room`, INF for never) and where (`at`), and the first time it stood near its slot (`near`).
func _watch(t: TestContext, a: Node2D) -> Dictionary:
	var out := { "in_room": INF, "at": Vector2.INF, "near": INF }
	var sample := func() -> bool:
		if out["in_room"] == INF and _past_doorway(a.global_position):
			out["in_room"] = snappedf(t.time, 0.01)
			out["at"] = a.global_position.round()
		if out["near"] == INF and a.global_position.distance_to(Order.BACK_NORTH) <= SLOT_NEAR:
			out["near"] = snappedf(t.time, 0.01)
		return false
	await t.until(sample, WATCH)
	return out
