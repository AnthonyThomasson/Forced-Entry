extends GameTest
## The brief's item 4 (#182): in the house an elevator lobby is an ordinary room, and an entry
## stack clears it. In the district's `bodega_tower` (the shop on the street, the lobby behind it)
## two invaders that know the house, stacked on its doorway, are sent to search the lobby (a plain
## search order, scripted Von); a household puppet stands in the lobby beside the doorway, out of
## sight of the room outside. The point goes through the doorway by tactical entry (`going_in`
## radioed before the funnel, no pause in it), and the stack reaches the lobby and shoots the
## hostile there dead.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const EntryWatch := preload("res://tests/_ai/entry_watch_probe.gd")
const PLAN := "bodega_tower"
const SEED := 7
## Seconds the invader has to get through the doorway and kill the household puppet.
const DURATION := 70.0
## Where the household puppet stands, hidden from the room outside by the wall beside the doorway:
## `HIDE_DEPTH` px in from the doorway's wall and `ASIDE` px along it from the doorway's centre.
const HIDE_DEPTH := 20.0
const ASIDE := 80.0
## The invader starts this far (px) out from the doorway, on its axis.
const STACK_AT := 120.0
## The two invaders of the stack: the second stands this far (px) behind the first.
const IDS := [&"a", &"b"]
const STACK_GAP := 45.0


func describe() -> Dictionary:
	return {
		"name": "Entry clears the elevator lobby",
		"description": "Sent to search the district tower's elevator lobby, a stack of two "
			+ "goes through its doorway by tactical entry and kills the hostile standing in it.",
		"tags": ["ai", "entry", "guard", "lobby", "district", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED, PLAN)
	Entry.guard_rules(s, ["room_elevator_lobby", "engage"])
	for id in IDS:
		Entry.npc(s, id, Vector2.ZERO, { "tuning:entry:ready_timeout": 30.0 })
		s.set_props(id, "GoalController", { "tuning:memory:familiar_with_house": true })
	s.actor(&"defender", &"puppet", Vector2.ZERO, { "faction": &"household" })


func run(t: TestContext) -> void:
	var lobby := _room_of_type(t, "elevator_lobby")
	var door := _lobby_door(t, lobby)
	if not t.require(not door.is_empty(), "premise: the lobby has an interior doorway"):
		return
	var defender := t.actor(&"defender")
	for i in IDS.size():
		var at: float = STACK_AT + STACK_GAP * i
		t.actor(IDS[i]).global_position = (door["pos"] as Vector2) + (door["out"] as Vector2) * at
	var side := (door["out"] as Vector2).orthogonal()
	defender.global_position = (
		(door["pos"] as Vector2) - (door["out"] as Vector2) * HIDE_DEPTH + side * ASIDE
	)
	defender.facing = -side
	t.puppet(&"defender").aim_at(defender.global_position - side * 80.0)
	await t.frames(3)
	var done := func() -> bool: return defender.is_dead
	var samples: Array = await EntryWatch.watch(t, IDS, door, DURATION, done)
	if not t.require(
			done.call(),
			"the invader killed the hostile in the lobby (act %s)"
					% Entry.brain(t, IDS[0]).current_act(),
	):
		return
	var point: StringName = IDS[0]
	for id in IDS:
		if Entry.first_call_time(t, "going_in", id, door["id"]) < Entry.first_call_time(
				t, "going_in", point, door["id"]):
			point = id
	EntryWatch.check_entered(t, samples, point, door)
	t.check(
		IDS.any(func(id): return lobby.grow(20.0).has_point(t.actor(id).global_position)),
		"an invader is in the lobby",
	)


## The first room of the house whose type is `type`.
func _room_of_type(t: TestContext, type: String) -> Rect2:
	for room: Dictionary in t.rooms:
		if room["type"] == type:
			return room["rect"]
	return Rect2()


## The frame (`entry_probe.gd`'s door dictionary) of the lobby's one interior doorway: its place
## and width, `out` the unit normal pointing out of the lobby (the side the team stacks on), `room`
## the lobby.
func _lobby_door(t: TestContext, lobby: Rect2) -> Dictionary:
	for opening: Dictionary in t.world.openings:
		var pos: Vector2 = opening["pos"]
		if not lobby.grow(14.0).has_point(pos) or opening["front"] or opening["exit"]:
			continue
		var out := _normal_out_of(lobby, pos)
		return {
			"id": "door_%d_%d" % [roundi(pos.x), roundi(pos.y)],
			"pos": pos,
			"width": opening["width"],
			"out": out,
			"room": lobby,
			"room_key": "elevator_lobby",
		}
	return {}


## The axis direction from `rect` toward `pos`, a point on its wall.
func _normal_out_of(rect: Rect2, pos: Vector2) -> Vector2:
	var gaps := {
		Vector2.LEFT: absf(pos.x - rect.position.x),
		Vector2.RIGHT: absf(pos.x - rect.end.x),
		Vector2.UP: absf(pos.y - rect.position.y),
		Vector2.DOWN: absf(pos.y - rect.end.y),
	}
	var best := Vector2.LEFT
	for direction: Vector2 in gaps:
		if gaps[direction] < gaps[best]:
			best = direction
	return best
