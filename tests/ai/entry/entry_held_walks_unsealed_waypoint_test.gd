extends GameTest

## Ticket #65 round 2, `docs/tactical-entry.md` E2 / "Bodies on the way": a walk to the stack held by a body drops the waypoints the hold
## seals, and only those: a next waypoint whose way does not pass the body is still walked. Two rooms and a doorway between them; the
## invader (ENTER the doorway, scripted Von, alone: slot 1 on the south side of the door) stands north of a pocket of counters by the
## south wall whose one gap a body (an invader puppet, no part of the stack) stands in. Its approach's first waypoint, out from the wall
## at its own depth, lies in that pocket behind the body: held short of it, it must give that waypoint up, never go into the pocket, and
## walk on to the next, the point past its slot along the wall, which the way east round the counters reaches, and so into its slot.

const Entry := preload("res://tests/_ai/entry_probe.gd")

const WEST := Rect2(0, 0, 600, 400)
const EAST := Rect2(600, 0, 300, 400)
const DOOR := { "id": "door_600_200", "pos": Vector2(600, 200), "width": 80.0, "out": Vector2.LEFT, "room": EAST, "room_key": "east" }
## The pocket: two counters along y = 280 with a gap between them, and one down to the south wall at its east end.
const POCKET := Rect2(0, 285, 280, 115)
const GAP := Vector2(140, 280)
const START := Vector2(140, 215)
## Within this (px) of a waypoint it walked to it (`Entry.WAYPOINT_REACH` and a few px).
const WAYPOINT_NEAR := 30.0
## Within this (px) of its slot's point it is in its slot (`Entry.SLOT_REACH` and a few px).
const SLOT_NEAR := 10.0
## How long (s) it may stand held before it walks on: the hold's re-plan (`Locomotion.WAIT`) and a little.
const ON_S := 1.5
## How long (s) from walking on it may take to stand in its slot: the way east round the counters, walked.
const REACH_S := 8.0
## It stands when it moves less than this (px) over `STILL_WINDOW` s.
const STILL_PX := 3.0
const STILL_WINDOW := 0.25


func describe() -> Dictionary:
	return {
		"name": "A held walk still walks a waypoint the hold does not seal",
		"description": "An invader's first approach waypoint lies in a pocket whose only gap a body stands in: held short of it, it drops that waypoint, keeps out of the pocket and walks on to the next one, the point past its slot, and into its slot.",
		"tags": ["ai", "entry", "stack", "navigation", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": WEST },
		{ "key": "east", "type": "kitchen", "rect": EAST },
	], [{ "pos": DOOR["pos"], "width": DOOR["width"] }])
	s.object(&"counter_w", "kitchen_counter", Vector2(50, 280))
	s.object(&"counter_e", "kitchen_counter", Vector2(230, 280))
	s.object(&"counter_s", "kitchen_counter", Vector2(280, 345), { "rotated": true })
	Entry.rules(s, DOOR)
	Entry.npc(s, &"walker", START)
	s.actor(&"body", &"puppet", GAP, { "faction": &"invader", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	var brain := Entry.brain(t, &"walker")
	var st := { "first": [], "next": Vector2.INF, "spot": Vector2.INF, "still_at": INF, "on_at": INF, "near_next": INF,
			"in_slot_at": INF, "in_pocket": false, "slots": [], "trail": [] }
	while t.time < 25.0:
		for c in Entry.calls(t, "claim", &"walker"):
			if not (st["slots"] as Array).has(int(c["slot"])):
				(st["slots"] as Array).append(int(c["slot"]))
		var e: Dictionary = brain.debug_entry_view().get("entry", {})
		var phase := String(e.get("phase", ""))
		var here: Vector2 = walker.global_position
		if (st["first"] as Array).is_empty() and phase == "approach" and not (e.get("waypoints", []) as Array).is_empty():
			st["first"] = (e["waypoints"] as Array).duplicate()
			st["spot"] = e["my_slot"]
			if (st["first"] as Array).size() > 1:
				st["next"] = st["first"][1]
		if POCKET.has_point(here):
			st["in_pocket"] = true
		var trail: Array = st["trail"]
		trail.append([t.time, here])
		while trail.size() > 1 and float(trail[0][0]) < t.time - STILL_WINDOW:
			trail.pop_front()
		var still: bool = float(trail[0][0]) <= t.time - STILL_WINDOW + 0.02 and (trail[0][1] as Vector2).distance_to(here) < STILL_PX
		if st["still_at"] == INF and phase == "approach" and still and here.distance_to(GAP) < 100.0:
			st["still_at"] = t.time - STILL_WINDOW
		elif st["still_at"] != INF and st["on_at"] == INF and not still:
			st["on_at"] = t.time - STILL_WINDOW
		if st["next"] != Vector2.INF and here.distance_to(st["next"]) <= WAYPOINT_NEAR:
			st["near_next"] = minf(float(st["near_next"]), t.time)
		if st["in_slot_at"] == INF and phase == "stack" and here.distance_to(st["spot"]) <= SLOT_NEAR:
			st["in_slot_at"] = t.time
			break
		if not Entry.calls(t, "abort", &"walker").is_empty():
			break
		t.trace("walker_to_body", here.distance_to(GAP))
		await t.frames(1)
	var first: Array = st["first"]
	if not t.require(not first.is_empty() and POCKET.has_point(first[0]) and st["next"] != Vector2.INF and not POCKET.has_point(st["next"]),
			"premise: its approach's first waypoint lies in the pocket behind the body and the next one outside it (%s)" % [first]):
		return
	if not t.require(st["still_at"] != INF, "premise: its walk to the first waypoint stood held short of the body in the gap"):
		return
	t.check(Entry.calls(t, "abort", &"walker").is_empty(), "it never gives the entry up (abort)")
	t.check((st["slots"] as Array) == [1], "it keeps slot 1 (claimed %s)" % [st["slots"]])
	t.check(not bool(st["in_pocket"]), "it never goes into the pocket the body holds")
	t.check(st["on_at"] != INF and float(st["on_at"]) - float(st["still_at"]) <= ON_S,
		"it walks on within %.1f s of standing held (stood at %.2f s, on at %.2f s)" % [ON_S, st["still_at"], st["on_at"]])
	t.check(st["near_next"] != INF,
		"it walks to the next waypoint, the point past its slot (%s), which the hold does not seal" % [st["next"]])
	t.check(st["in_slot_at"] != INF and st["on_at"] != INF and float(st["in_slot_at"]) - float(st["on_at"]) <= REACH_S,
		"it stands in its slot within %.0f s of walking on (on at %.2f s, in its slot at %.2f s)" % [REACH_S, st["on_at"], st["in_slot_at"]])
