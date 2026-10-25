extends GameTest
## Issue #49: a room's tactical zone was drawn outside the generated house instead of in its room,
## on some houses right after a match starts. The room options the snapshot offers (go to a room,
## search it, explore it) point at the room's centre snapped onto the navmesh, and the room zones
## are what the tactics overlay draws. Desired: every room point an NPC weighs lies inside the room
## it is named for.
##
## The match is built through the match module (`MatchBuilder.build`: generate the house, bake its
## navmesh, place the NPCs) in a world of its own (`MainProbe.viewport`: a `SubViewport` with its
## own `World2D`, so the test world's stage is not laid twice) whose navigation map is already live
## with another navmesh, an arena's, as the map is when a match starts after the menu or a previous
## match. Premise: the build does not wait for the maps (`wait_nav` off), so the NPCs are placed in
## the frame the navmesh is baked and their first decisions meet a map still answering with the
## arena. What is tested is the AI's own hold on a room point until the map has taken the new
## navmesh in (`NavBuilder.ready`); a match that waits, as Main's does, never meets that map at all.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const ArenaBuilder := preload("res://scenes/testing/arena_builder.gd")
const SEED := 18
## The arena whose navmesh the match's world is live with first.
const ARENA := Rect2(0, 0, 800, 500)
## Far from `ARENA`, so a point snapped onto the wrong navmesh is plainly outside the house.
const FRONT_ENTRANCE := Vector2(4000, 3000)
## Categories of `debug_zones()` that stand for a room (the `waypoint` ones — post, entrance — are
## not rooms).
const ROOM_CATEGORIES := [&"room", &"search"]


func describe() -> Dictionary:
	return {
		"name": "Room zones lie inside their rooms",
		"description": "A match is built over a live navigation map without waiting for it: every "
			+ "room point the defender and the invader weigh on their first decisions is inside a "
			+ "room of the house, and the one named for a room is in a room of that kind.",
		"tags": ["ai", "perception", "zones", "navigation", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.von_script([{ "pick": "search" }])
	s.switch(&"ai.hostile_on_trespass", false)   # nobody to fight: the NPCs just weigh rooms


func run(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var map: RID = viewport.world_2d.navigation_map
	var arena := ArenaBuilder.build(TestSetup.new().arena(ARENA).world, viewport)
	NavBuilder.build(arena, WorldGen.get_rooms(arena), viewport)
	if not t.require(
			await t.until(func(): return NavBuilder.ready(map), 5.0),
			"premise: the match's world's navigation map is live with the arena's navmesh",
	):
		return
	var world := Node2D.new()
	world.name = "World"
	viewport.add_child(world)
	var spec := MatchBuilder.spec({
		"seed": SEED,
		"entrance": FRONT_ENTRANCE,
		"wait_nav": false,
		"defenders": { "count": 1 },
		"invaders": { "count": 1 },
	})
	var handle: Dictionary = await MatchBuilder.build(spec, world)
	if not t.require(
			(handle.get("combatants", []) as Array).size() == 2,
			"a defender and an invader placed",
	):
		return
	var rooms: Array = handle["rooms"]
	if not t.require(
			not NavBuilder.ready(map),
			"premise: the NPCs are placed while the map has not taken the house's navmesh in",
	):
		return

	await t.seconds(2.0)
	var misplaced: Array = []
	var seen := 0
	for npc in handle["combatants"]:
		seen += _room_zones(npc, rooms, misplaced)
	t.require(seen > 0, "the NPCs weighed room points")
	t.check(misplaced.is_empty(), "every room point lies in its room: %s" % [misplaced])


## How many room points `npc` weighs; each that is not in its room is added to `misplaced`.
func _room_zones(npc: Node, rooms: Array, misplaced: Array) -> int:
	var seen := 0
	var brain: Node = TestContext.controller_of(npc)
	for zone: Dictionary in brain.debug_zones():
		if not ROOM_CATEGORIES.has(zone["category"]):
			continue
		seen += 1
		var why := _problem(rooms, zone)
		if why != "":
			misplaced.append("%s: %s (%s) at %s %s"
					% [npc.name, zone["label"], zone["category"], zone["point"], why])
	return seen


## What is wrong with `zone`'s point ("" = nothing): outside every room, or in a room of another
## kind than the zone names. Explore zones name a direction only ("unexplored north"), so only the
## first test applies to them.
func _problem(rooms: Array, zone: Dictionary) -> String:
	var p: Vector2 = zone["point"]
	var room := {}
	for r in rooms:
		if (r["rect"] as Rect2).has_point(p):
			room = r
			break
	if room.is_empty():
		return "is outside every room of the house"
	var label := str(zone["label"])
	if label.begins_with("the ") and label != "the front entrance":
		var kind := str(room["type"]).replace("_", " ")
		if label != "the %s" % kind:
			return "is in the %s, not %s" % [kind, label]
	return ""
