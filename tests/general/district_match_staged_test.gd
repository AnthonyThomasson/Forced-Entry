extends GameTest
## A district match is staged (#182): `MatchBuilder.stage` generates the downtown district, the
## match is fought over the house in the centre block alone, and the rest of the district is
## scenery to the AI.
##
## - The handle carries the `district` and its `house` (the centre tower), and its `rooms` and
##   `openings` are the house's.
## - Every defender stands in a room of the house, none in a neighbour tower.
## - Every NPC's controller is handed the house's rooms and openings and nothing of a neighbour's
##   (so a neighbour counts as outside for confinement, entry and spawning).
## - Every room of every tower has a light (a fixture of the lighting, or a piece's own light) and
##   no two rooms of the district share a key, so a neighbour's room never hides behind the
##   house's.

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const SEED := 7
const PLAN := "garage_home"
const TOWERS := 9
const DEFENDERS := 6
const INVADERS := 4


func describe() -> Dictionary:
	return {
		"name": "A district match is fought over the house alone, and every tower room is lit",
		"description": "A match declared on s.district: the handle carries the district and its "
			+ "house, with the house's rooms and openings; defenders spawn only in house rooms; "
			+ "every NPC is bound to the house's rooms and openings; every tower room has light, "
			+ "under unique room keys.",
		"tags": ["setup", "match", "district", "spawn", "lighting"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED, PLAN)
	s.von_down()
	s.declared_match({
		"defenders": { "count": DEFENDERS },
		"invaders": { "count": INVADERS },
	})


func run(t: TestContext) -> void:
	var handle: Dictionary = t.world.match_handle
	if not t.require(not handle.is_empty(), "the world holds the match's handle"):
		return
	var district := handle.get("district") as Node2D
	if not t.require(district != null, "the handle carries the district"):
		return
	t.expect_eq(DistrictReads.get_towers(district).size(), TOWERS, "nine towers stand")
	var house := WorldGen.house_of(district)
	t.check(handle.get("house") == house, "the handle's house is the district's centre tower")
	var rooms := WorldGen.get_rooms(house)
	var openings := WorldGen.get_openings(house)
	t.check(handle.get("rooms") == rooms, "the handle's rooms are the house's")
	t.check(handle.get("openings") == openings, "the handle's openings are the house's")
	var all_rooms := WorldGen.district_rooms(district)
	if not t.require(rooms.size() < all_rooms.size(), "premise: the towers have more rooms"):
		return
	_check_defenders(t, handle, rooms, all_rooms)
	_check_bound(t, handle, rooms, openings)
	_check_lit(t, all_rooms)


## Every defender stands in a room of the house: in no room of a neighbour tower.
func _check_defenders(t: TestContext, handle: Dictionary, rooms: Array, all_rooms: Array) -> void:
	var neighbours := all_rooms.filter(
		func(r: Dictionary) -> bool: return not rooms.any(
			func(h: Dictionary) -> bool: return h["rect"] == r["rect"],
		),
	)
	var defenders: Array = handle["combatants"].filter(
		func(c: Node) -> bool: return c.get("faction") == MatchBuilder.DEFENDER_FACTION,
	)
	t.expect_eq(defenders.size(), DEFENDERS, "every defender is placed")
	for defender: Node2D in defenders:
		var at := defender.global_position
		t.check(
			rooms.any(func(r: Dictionary) -> bool: return (r["rect"] as Rect2).has_point(at)),
			"%s stands in a room of the house" % defender.name,
		)
		t.check(
			not neighbours.any(
				func(r: Dictionary) -> bool: return (r["rect"] as Rect2).has_point(at),
			),
			"%s stands in no neighbour's room" % defender.name,
		)


## Every NPC's controller holds the house's rooms and openings, not the district's.
func _check_bound(t: TestContext, handle: Dictionary, rooms: Array, openings: Array) -> void:
	var count := 0
	for c: Node in handle["combatants"]:
		var brain := TestContext.controller_of(c)
		if brain == null:
			continue
		count += 1
		t.check(brain.rooms == rooms, "%s knows the house's rooms only" % c.name)
		t.check(brain.openings == openings, "%s knows the house's openings only" % c.name)
	t.expect_eq(count, DEFENDERS + INVADERS, "every NPC has a controller to check")


## Every room of the district holds a light, and the keys of the rooms are all different.
func _check_lit(t: TestContext, all_rooms: Array) -> void:
	var lighting := Probe.require_lighting(t)
	if lighting == null:
		return
	var keys := {}
	for room: Dictionary in all_rooms:
		keys[room["key"]] = true
	t.expect_eq(keys.size(), all_rooms.size(), "no two rooms share a key")
	var lights: Array = lighting.lights()
	for room: Dictionary in all_rooms:
		var rect: Rect2 = room["rect"]
		t.check(
			lights.any(func(l: Node2D) -> bool: return rect.has_point(l.global_position)),
			"room %s is lit" % room["key"],
		)
