extends GameTest
## A hold's verdict on its slot (`AgentEntry.slot_reach`) carves the bodies at rest out of the map
## it reads, and each distinct set used to bake a map of its own, a district-size bake a hold asked
## for every frame (#194). Now a set of bodies within `EntryBodyMaps.TOLERANCE` of a kept
## one (a body swaying a pixel, one asked twice) is that map, and a body further than
## `AgentEntry.BODY_CORRIDOR` off the plain route is not carved at all (the route cannot meet it):
## the plain map answers when none is near. A set that differs for real is a map of its own.
## Premise: the plain route from the start to the slot runs through the living room's open floor.

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const EntryBodyMaps := preload("res://scenes/ai/perception/entry/entry_body_maps.gd")
const FROM := Vector2(-150, -250)
const TO := Vector2(-230, -170)
## A body on the plain route, and where it stands a pixel or two off it.
const BODY := Vector2(-190, -210)
const SWAY := Vector2(-188.5, -211.5)
## Well off the route (more than the corridor), and a body of the route moved well away from it.
const FAR := Vector2(-150, -250 + 150)
const MOVED := Vector2(-176, -214)


func describe() -> Dictionary:
	return {
		"name": "A hold's verdict shares its bodies' avoid map between asks that differ by a hair",
		"description": "slot_reach on one set of bodies, again with each a pixel off and one "
			+ "asked twice (the same map, no new bake), with a body far from the route added "
			+ "(the same), with none near (the plain map), and with one moved well off (a bake).",
		"tags": ["ai", "entry", "navigation", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.switch(&"worldgen.doors", false)
	s.house(1, "bungalow")
	s.von_down()


func run(t: TestContext) -> void:
	var map := NavWorld.map_of(t.world)
	await t.until(func() -> bool: return NavBuilder.ready(map), 20.0)
	if not t.require(
		NavBuilder.planning_region(map) != null, "premise: the map has a planning region to carve",
	):
		return
	var to := NavBuilder.snap(map, TO)
	var plain := NavBuilder.route(map, FROM, to)
	if not t.require(plain.size() >= 2, "premise: a plain route runs from the start to the slot"):
		return
	var entry := AgentEntry.new()
	var starts := NavBuilder.avoid_starts
	var first := await _verdict(t, entry, map, to, [BODY])
	t.check(first != -1, "premise: the verdict on one body at rest comes (%d)" % first)
	t.check(NavBuilder.avoid_starts == starts + 1, "premise: the first set baked one map")
	starts = NavBuilder.avoid_starts
	_check_key(t, map)
	var swayed: int = entry.slot_reach(FROM, to, map, [SWAY, BODY + Vector2(0.5, 0.0)])
	t.check(swayed == first, "a body a pixel or two off, asked twice, is as answered (%d)" % swayed)
	t.check(NavBuilder.avoid_starts == starts, "and bakes no map of its own")
	var far: int = entry.slot_reach(FROM, to, map, [BODY, FAR])
	t.check(far == first, "a body far off the route changes nothing (%d)" % far)
	t.check(NavBuilder.avoid_starts == starts, "and bakes no map of its own either")
	t.check(
		entry.slot_reach(FROM, to, map, [FAR]) != -1,
		"no body near the route: the plain map answers at once",
	)
	t.check(NavBuilder.avoid_starts == starts, "and nothing is baked for it")
	var moved: int = entry.slot_reach(FROM, to, map, [MOVED])
	t.check(moved == -1, "a body well off its first place is a set of its own, baking (%d)" % moved)
	t.check(NavBuilder.avoid_starts == starts + 1, "one map more")
	_check_last_kept(t, entry, map, to)


## The verdict `entry` gives on bodies `bodies`, asked every frame until its map is up.
func _verdict(
	t: TestContext, entry: RefCounted, map: RID, to: Vector2, bodies: Array,
) -> int:
	var verdict := -1
	var waited := 0
	while verdict == -1 and waited < 240:
		verdict = entry.slot_reach(FROM, to, map, bodies)
		if verdict == -1:
			await t.frames(1)
			waited += 1
	return verdict


## A kept set's key carries its planning region's id: a new region on the map never reuses it.
func _check_key(t: TestContext, map: RID) -> void:
	var region := NavBuilder.planning_region(map)
	var kept: Array = region.get_meta(EntryBodyMaps.META, [])
	var prefix := "bodies:%d:" % region.get_instance_id()
	t.check(
		not kept.is_empty() and str(kept[0]["key"]).begins_with(prefix),
		"a kept set's key carries its planning region's id",
	)


## The set asked for last is the one kept longest (the first one, asked again).
func _check_last_kept(t: TestContext, entry: RefCounted, map: RID, to: Vector2) -> void:
	var kept: Array = NavBuilder.planning_region(map).get_meta(EntryBodyMaps.META)
	var first_key := str(kept[0]["key"])
	entry.slot_reach(FROM, to, map, [BODY])
	t.check(
		str(kept[-1]["key"]) == first_key,
		"the set asked for last is the one kept longest",
	)
