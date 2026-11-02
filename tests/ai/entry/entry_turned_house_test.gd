extends GameTest
## An invader stack breaches a turned house (#182): in a district match the house's front door
## faces any of the four streets, so nothing in the entry may assume it faces south. Three invaders
## start beside the front door as a match places them, scripted Von sends them into it (ENTER, the
## front doorway), and they must stack outside it, go in through it one after the other and clear
## the room behind it, whether the house faces north, east or west.
##
## Each facing is its own match over a district whose seed turns the house that way (the test's own
## scan of seeds), built whole as Main builds one (`MatchBuilder.build`) in a world of its own
## (`MainProbe.viewport`); the house is a forced plan, its front door at `ENTRANCE`. The door's
## frame (its id, its room, the way out) is read off the house's rooms and openings by the test
## (`tests/_ai/slots_probe.gd`), the entry off the radio (the callouts' `entry_step`).

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const PLAN := "starter_home"
## Where the house's front door lands; the AI names a doorway `door_<x>_<y>` of its position.
const ENTRANCE := Vector2(440, 350)
const INVADERS := 3
## The ways the house must face, as the way out of its front door: north, east and west.
const FACINGS := [Vector2.UP, Vector2.RIGHT, Vector2.LEFT]
## The seeds scanned for a house facing each way.
const SEEDS := 80
## Most sim seconds a stack takes to breach and clear the room.
const TIME := 70.0


## The front doorway's id as the AI names it.
func _front_id() -> String:
	return "door_%d_%d" % [ENTRANCE.x, ENTRANCE.y]


func describe() -> Dictionary:
	return {
		"name": "An invader stack breaches and clears a house facing north, east and west",
		"description": "In a district match over a forced house turned to each of three facings, "
			+ "three invaders sent into the front door stack, all go in through it and radio the "
			+ "room behind it clear.",
		"tags": ["ai", "entry", "scripted", "district", "callout"],
		"timeout": 300.0,
		"allowed_logs": [
			"Navigation map synchronization error",
			"NavigationPolygon polygon convex partition failed",
		],
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 300, 300))
	Entry.rules(s, { "id": _front_id() })


func run(t: TestContext) -> void:
	var seeds := _seeds_by_facing()
	if not t.require(seeds.size() == FACINGS.size(), "premise: seeds turn the house each way"):
		return
	for facing: Vector2 in FACINGS:
		await _breach(t, facing, seeds[facing])


## `{ facing: first seed }` for each of `FACINGS` that a house of `PLAN` takes, over `SEEDS` seeds.
func _seeds_by_facing() -> Dictionary:
	var out := {}
	for seed_value in range(1, SEEDS + 1):
		var layout := DistrictLayout.compute(seed_value, PLAN)
		var facing: Vector2 = layout["blocks"][DistrictLayout.HOUSE_BLOCK]["outward"]
		if facing in FACINGS and not out.has(facing):
			out[facing] = seed_value
	return out


## The match of `seed_value` (the house facing `facing`) run until its invaders have gone in and
## cleared the front room, or `TIME` runs out; judged, and freed.
func _breach(t: TestContext, facing: Vector2, seed_value: int) -> void:
	var label := "facing %s (seed %d)" % [str(facing), seed_value]
	var viewport := MainProbe.viewport(t)
	var world := Node2D.new()
	world.name = "World"
	viewport.add_child(world)
	var handle: Dictionary = await MatchBuilder.build(
		MatchBuilder.spec({
			"seed": seed_value,
			"plan": PLAN,
			"entrance": ENTRANCE,
			"defenders": { "count": 0 },
			"invaders": { "count": INVADERS },
		}),
		world,
	)
	if t.require(not handle.is_empty(), "%s: the match is built" % label):
		var frame := _front_frame(handle)
		if t.require(
				not frame.is_empty() and frame["id"] == _front_id() and frame["out"] == facing,
				"%s: premise: the front door %s faces that way (out %s)"
					% [label, _front_id(), str(frame.get("out"))],
		):
			var invaders: Array = handle["combatants"]
			var cleared := func() -> bool: return not _calls(t, "clear", invaders).is_empty()
			await t.until(cleared, TIME)
			_check(t, label, frame, invaders)
	viewport.queue_free()
	await t.frames(2)


## The frame of the house's front door (`Slots.frame` into the room it opens to), {} with none.
func _front_frame(handle: Dictionary) -> Dictionary:
	for o: Dictionary in handle["openings"]:
		if o.get("front", false):
			return Slots.frame(o, String(o["rooms"][0]), handle["rooms"])
	return {}


## Every invader went in by the front door, one of them radioed the front room clear and an invader
## stands in it.
func _check(t: TestContext, label: String, frame: Dictionary, invaders: Array) -> void:
	var room_key: String = frame["room_key"]
	var cleared := _calls(t, "clear", invaders)
	t.check(
		not cleared.is_empty(),
		"%s: the room behind the front door was radioed clear" % label,
	)
	if not cleared.is_empty():
		t.expect_eq(
			String(cleared[0].get("cleared_room", "")),
			room_key,
			"%s: the call names the room behind the front door" % label,
		)
	for invader: Node2D in invaders:
		var went_in := _calls(t, "in", [invader]).any(
			func(d: Dictionary) -> bool: return String(d.get("opening", "")) == _front_id(),
		)
		t.check(went_in, "%s: %s went in through the front door" % [label, invader.name])
	t.check(
		invaders.any(
			func(c: Node2D) -> bool: return (frame["room"] as Rect2).has_point(c.global_position),
		),
		"%s: an invader stands in the front room" % label,
	)


## The entry callouts of step `step` radioed by `speakers` so far (their data).
func _calls(t: TestContext, step: String, speakers: Array) -> Array:
	return t.events_of(
		&"callout",
		func(d: Dictionary) -> bool:
			return String(d.get("entry_step", "")) == step and speakers.has(d.get("speaker")),
	)
