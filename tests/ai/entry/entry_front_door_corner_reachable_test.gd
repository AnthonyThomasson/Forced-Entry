extends GameTest
## Issue #183 (`docs/tactical-entry.md` E5): an entrant's corner is one it can walk to from the
## doorway. Where furniture walls a room's corner off into a pocket of floor of its own, the corner
## taken is the nearest floor to it the doorway reaches, never one whose only route leads round the
## outside of the house.
##
## Generated house seed 10: the front doorway (0, 0), 69 px wide in the south wall of the great
## room, the door shut as a match starts it (DR4). The furniture by the great room's south-east
## corner shuts a pocket of floor in it off from the doorway: a route from the street into that
## pocket ends on the street outside its wall. Two invaders stack outside the door (scripted Von:
## enter, that doorway) with no defender in the house.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const SEED := 10
## The front doorway of the seed-10 house and the room behind it, framed from the street.
const FRONT := {
	"id": "door_0_0",
	"pos": Vector2(0, 0),
	"width": 69.0,
	"out": Vector2.DOWN,
	"room": Rect2(-330, -440, 660, 440),
	"room_key": "great_room",
}


func describe() -> Dictionary:
	return {
		"name": "Front-door entry pair takes corners it can walk to",
		"description": "Two invaders entering by a front door whose room has a corner walled off "
			+ "by furniture both cross and stop at door-wall corners inside the room.",
		"tags": ["ai", "entry", "door", "navigation", "scripted"],
		"timeout": 50.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)
	Entry.rules(s, FRONT)
	Entry.npc(s, &"a", Vector2(60, 90))
	Entry.npc(s, &"b", Vector2(110, 110), { "tuning:decision:decide_interval": 0.55 })


func run(t: TestContext) -> void:
	var door := FRONT
	var room := (t.rooms.filter(func(r): return r["key"] == FRONT["room_key"]) as Array)
	if not t.require(
			room.size() == 1 and room[0]["rect"] == FRONT["room"],
			"the seed-%d house has its great room behind the front door (%s)" % [SEED, room],
	):
		return
	# Where each stands the last frame it holds its corner (the entry's `corner` phase).
	var stops := { &"a": Vector2.INF, &"b": Vector2.INF }
	var held := { &"a": false, &"b": false }
	var end := t.time + 45.0
	while t.time < end and not held.values().all(func(h): return h):
		for id in stops:
			var phase: String = Entry.entry(Entry.brain(t, id)).get("phase", "")
			if phase == "corner":
				stops[id] = t.actor(id).global_position
			elif stops[id] != Vector2.INF:
				held[id] = true
		await t.frames(1)
	t.check(
		stops.values().all(func(p): return p != Vector2.INF and Entry.in_room(door, p)),
		"both crossed the threshold and held their corner in the great room (%s)" % str(stops),
	)
	if stops.values().any(func(p): return p == Vector2.INF or not Entry.in_room(door, p)):
		return
	t.check(
		signf(Entry.lateral(door, stops[&"a"])) != signf(Entry.lateral(door, stops[&"b"])),
		"they took opposite sides of the door (%s / %s)"
			% [stops[&"a"].round(), stops[&"b"].round()],
	)
	for id in stops:
		t.check(
			Entry.outward(door, stops[id]) > -130.0
				and absf(Entry.lateral(door, stops[id])) > float(door["width"]) * 0.5,
			"%s stopped in a corner on the door's wall (%s)" % [id, stops[id].round()],
		)
