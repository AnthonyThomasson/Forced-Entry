extends GameTest
## Performance guard for an ambush order (`docs/leadership.md` LD15, LD29, Performance): a crew of
## three AI defenders in a generated house (the match guards' house, `Perf.MATCH_SEED` on
## `Perf.MATCH_PLAN`, built as Main builds a match with no invaders) is ordered, inside the measured
## window, to ambush a doorway nobody has ranked the posts of yet: a doorway of its leader's room
## into the next room, from the leader's room, the leader itself among the recipients as the
## defenders' ambush rule orders it. Each recipient's decision snapshot lays its post (the doorway's
## candidate posts ranked: hidden first, then shielded from an entry's grenade, `EntryPosts`), one
## decision a frame (`DecisionBudget`). Every frame of the window holds the smooth-match standard
## (`Perf.within_frames`), the worst one the frame the ranking lands in. Scripted Von; nobody
## fights. Headless measures CPU only.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const OrderBrain := preload("res://tests/_ai/order_brain_probe.gd")
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const CREW := 3
## Test seconds before the window: the house's doorways are laid (`AgentEntry.warm_geometry`) and
## the crew has made its first decisions.
const WARMUP_S := 2.0
## The window, and the frame of it the order is posted on.
const MEASURE_FRAMES := 120
const ORDER_AT := 10
## The primitive an ambusher runs.
const AMBUSH := "ambush"


func describe() -> Dictionary:
	return {
		"name": "An ambush order to a crew stays within the frame budget",
		"description": "Three AI defenders ordered to ambush a doorway not yet ranked; every frame "
			+ "of the window, the ones their posts are laid in too, holds the smooth-match "
			+ "standard (LD15, LD29).",
		"tags": ["ai", "scripted", "leadership", "ambush"],
		"timeout": 40.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	s.house(Perf.MATCH_SEED, Perf.MATCH_PLAN)
	s.von_script([])
	s.switch(&"audio.sound", false)
	s.declared_match({ "defenders": { "count": CREW }, "invaders": { "count": 0 } })


func run(t: TestContext) -> void:
	var crew: Array = t.world.match_handle.get("combatants", [])
	var squad: Node = t.world.squad(MatchBuilder.DEFENDER_FACTION)
	if not t.require(
			crew.size() == CREW and squad != null and squad.leader() != null,
			"premise: a crew of %d with its squad and an AI leader (%d)" % [CREW, crew.size()],
	):
		return
	await t.seconds(WARMUP_S)
	var rooms: Array = t.world.match_handle["rooms"]
	var room := HouseRooms.key_at(squad.leader().global_position, rooms)
	var opening := _interior_doorway(t.world.match_handle["openings"], room)
	if not t.require(
			opening != "",
			"premise: the leader stands in a room (%s) with a doorway into another" % room,
	):
		return
	var posted_orders: Array = []  # A lambda captures a var by value: filled in place.
	var post := func(i: int) -> void:
		if i == ORDER_AT:
			posted_orders.append(
				squad.issue({ "kind": "ambush", "to": crew, "opening": opening, "room": room }),
			)
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES, post)
	if not t.require(
			not posted_orders.is_empty() and not (posted_orders[0] as Dictionary).is_empty(),
			"premise: the ambush order was posted (%s)" % [posted_orders],
	):
		return
	var posted := crew.filter(
		func(c): return OrderBrain.primitive(TestContext.controller_of(c, &"debug_state")) == AMBUSH
	)
	if not t.require(
			posted.size() == CREW,
			"premise: every member took its ambush within the window (%d of %d)"
				% [posted.size(), CREW],
	):
		return
	Perf.within_frames(t, "ambush order", stats)


## The id of the first doorway (by id) of room `room` that joins it to another room, or "".
func _interior_doorway(openings: Array, room: String) -> String:
	var ids: Array = []
	for o: Dictionary in openings:
		var joins: Array = (o.get("rooms", []) as Array).map(func(k): return String(k))
		if joins.size() == 2 and joins.has(room):
			ids.append(AgentEntry.opening_id(o))
	ids.sort()
	return "" if ids.is_empty() else String(ids[0])
