extends GameTest
## The human steps out of the front door (#182): in a played match the district's house turns by
## the seed, so its front door faces any of the four streets; the human who invades starts
## `run.entrance_distance` (70 px) out from the front door along the way out of the house, whichever
## street that is, outside every room, and the invaders gather round that spot on the street. The
## front door itself stands at Main's anchor (the scene's `Player`, where the game used to put the
## player 70 px below the door).
##
## Main is run whole (`tests/_main/main_probe.gd`: its own world, built at once as a scripted
## restart builds), with the house's seed picked by the test's own scan of seeds so that across the
## four matches the house takes every facing. The doorway's frame (its centre and the way out of
## its room) is the test's own, read off the house's rooms and openings
## (`tests/_ai/slots_probe.gd`).

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
## Where the scene's `Player` stands: Main's anchor.
const ANCHOR := Vector2(440, 350)
## How far (px) out from the front door the human starts (`run.entrance_distance`).
const STEP := 70.0
## How near (px) the human's spot the invaders pack (the team's group radius), and the most
## (px) the human may stand off its spot.
const GROUP_RADIUS := 110.0
const SLACK := 2.0
const INVADERS := 4
const DEFENDERS := 2
## The seeds scanned for a house facing each way.
const SEEDS := 80
const FACINGS := 4


func describe() -> Dictionary:
	return {
		"name": "The human invader starts 70 px out of the front door, whichever street it faces",
		"description": "Main's district match over four seeds that turn the house to every "
			+ "facing: the front door at Main's anchor, the human 70 px out along the way out of "
			+ "the house and outside every room, the invaders packed round it on the street.",
		"tags": ["setup", "match", "spawn", "district", "main"],
		"timeout": 120.0,
		"allowed_logs": [
			"Navigation map synchronization error",
			"NavigationPolygon polygon convex partition failed",
		],
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 300, 300))
	s.von_down()


func run(t: TestContext) -> void:
	var seeds := _seeds_by_facing()
	if not t.require(seeds.size() == FACINGS, "premise: seeds turn the house to every facing"):
		return
	var outs := {}
	for turn in seeds:
		var seed_value: int = seeds[turn]
		var label := "seed %d (turn %d)" % [seed_value, turn]
		var played := await _play(t, seed_value)
		if not t.require(not played.is_empty(), "%s: Main built the match" % label):
			return
		outs[(played["out"] as Vector2).round()] = true
		_check(t, label, played)
	t.expect_eq(outs.size(), FACINGS, "the house faced every way: %s" % str(outs.keys()))


## `{ turn: first seed }` for each quarter turn the district's house takes, over `SEEDS` seeds.
func _seeds_by_facing() -> Dictionary:
	var out := {}
	for seed_value in range(1, SEEDS + 1):
		var layout := DistrictLayout.compute(seed_value, "")
		var turn: int = layout["blocks"][DistrictLayout.HOUSE_BLOCK]["turn"]
		if not out.has(turn):
			out[turn] = seed_value
	return out


## Main's match over the district of `seed_value`, played by an invader, read once built:
## `{ front, out, rooms, all_rooms, human, invaders }` (the doorway's centre and way out, the
## house's rooms and every tower's, and where the human and each invader stand), {} when none was
## built.
func _play(t: TestContext, seed_value: int) -> Dictionary:
	var viewport := MainProbe.viewport(t)
	Engine.set_meta("skip_setup", true)
	MainProbe.open(
		viewport,
		{
			"house_seed": seed_value,
			"invader_count": INVADERS,
			"defender_count": DEFENDERS,
			"player_side": &"invader",
			"spectator_mode": false,
		},
		ANCHOR,
	)
	Engine.remove_meta("skip_setup")
	var out := {}
	if await t.until(func(): return _npcs(viewport).size() >= INVADERS + DEFENDERS, 20.0):
		out = _read(viewport)
	await MainProbe.close(t, viewport)
	return out


## The match Main built in `viewport`, read: {} when its district or door is missing.
func _read(viewport: SubViewport) -> Dictionary:
	var district := _district(viewport)
	var house := WorldGen.house_of(district)
	if house == null:
		return {}
	var rooms := WorldGen.get_rooms(house)
	var frame := {}
	for o: Dictionary in WorldGen.get_openings(house):
		if o.get("front", false):
			frame = Slots.frame(o, String(o["rooms"][0]), rooms)
	if frame.is_empty():
		return {}
	var invaders := _npcs(viewport).filter(func(c): return c.get("faction") == &"invader")
	return {
		"front": frame["pos"],
		"out": frame["out"],
		"rooms": rooms,
		"all_rooms": WorldGen.district_rooms(district),
		"human": (_world(viewport).get_node("Player") as Node2D).global_position,
		"invaders": invaders.map(func(n): return (n as Node2D).global_position),
	}


## The district root of the match in `viewport`, null with none.
func _district(viewport: SubViewport) -> Node2D:
	for child in _world(viewport).get_children():
		if child is Node2D and child.has_meta("house"):
			return child
	return null


## The `match_world` node Main built its match under in `viewport`.
func _world(viewport: SubViewport) -> Node:
	for node in viewport.get_tree().get_nodes_in_group(&"match_world"):
		if viewport.is_ancestor_of(node):
			return node
	return null


## The NPCs of Main's match in `viewport`: the characters with an AI controller.
func _npcs(viewport: SubViewport) -> Array:
	var out: Array = []
	var world := _world(viewport)
	for child in world.get_children() if world != null else []:
		var brain := TestContext.controller_of(child)
		if child is CharacterBody2D and brain != null and "rooms" in brain:
			out.append(child)
	return out


## The front door at Main's anchor, the human `STEP` out of it along the way out and in no room,
## the invaders round it and in no room.
func _check(t: TestContext, label: String, played: Dictionary) -> void:
	var front: Vector2 = played["front"]
	var human: Vector2 = played["human"]
	var out: Vector2 = played["out"]
	var all_rooms: Array = played["all_rooms"]
	t.check(
		front.distance_to(ANCHOR) <= SLACK,
		"%s: the front door %s stands at Main's anchor %s" % [label, str(front.round()), ANCHOR],
	)
	t.check(
		human.distance_to(front + out * STEP) <= SLACK,
		"%s: the human at %s stands %.0f px out of the door %s along %s"
			% [label, str(human.round()), STEP, str(front.round()), str(out)],
	)
	t.check(
		not _in_a_room(all_rooms, human),
		"%s: the human stands outside every room" % label,
	)
	var invaders: Array = played["invaders"]
	t.expect_eq(invaders.size(), INVADERS, "%s: every invader is placed" % label)
	for p: Vector2 in invaders:
		t.check(
			p.distance_to(human) <= GROUP_RADIUS,
			"%s: an invader at %s packs round the human %s" % [
				label,
				str(p.round()),
				str(human.round()),
			],
		)
		t.check(
			not _in_a_room(all_rooms, p),
			"%s: an invader at %s stands on the street" % [label, str(p.round())],
		)


## Whether `p` stands in a room of `rooms` (each `{ rect }`).
func _in_a_room(rooms: Array, p: Vector2) -> bool:
	return rooms.any(func(r: Dictionary) -> bool: return (r["rect"] as Rect2).has_point(p))
