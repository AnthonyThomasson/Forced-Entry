extends GameTest
## Issue #183 (`docs/tactical-entry.md` E5): two invaders entering a generated house by its front
## door cross the threshold and take their corners inside the room behind it, never a spot on the
## far side of one of its walls. Each corner stands in the room it is the corner of, even where
## furniture fills the room's corner itself.
##
## Generated house seed 2: the front doorway (0, 0), 69 px wide in the south wall of the living
## room, the door shut as a match starts it (DR4). The furniture by the living room's south-east
## corner leaves the nearest walkable floor to it outside the house, on the street. Two invaders
## stack outside the door (scripted Von: enter, that doorway) with no defender in the house.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const SEED := 2
## The front doorway of the seed-2 house and the room behind it, framed from the street.
const FRONT := {
	"id": "door_0_0",
	"pos": Vector2(0, 0),
	"width": 69.0,
	"out": Vector2.DOWN,
	"room": Rect2(-200, -320, 400, 320),
	"room_key": "living_room",
}


func describe() -> Dictionary:
	return {
		"name": "Front-door entry pair takes its corners inside the room",
		"description": "Two invaders entering a generated house by its front door both cross and "
			+ "stop at the door-wall corners inside the room, one either side of the door.",
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
			"the seed-%d house has its living room behind the front door (%s)" % [SEED, room],
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
		"both crossed the threshold and held their corner in the living room (%s)" % str(stops),
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
