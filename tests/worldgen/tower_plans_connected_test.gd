extends GameTest
## The six tower ground-floor plans (#182) are logical and walkable, like every house plan: for each
## plan in every facing (0 to 3 quarter turns) and both mirror states, `LayoutRules.check` finds
## nothing illogical, every doorway is reachable from outside the front door, and the plan has
## exactly one front door, at most one exit and exactly one `elevator_lobby`: an empty room of about
## 240 x 200 px (swapped for an odd turn) with one interior doorway into a room its `LINKS` allow,
## no exterior door and its stencil upright. The turned layout is checked in world space; the
## one rule that reads it off the plan, the front on the south wall, is checked before the turn
## (`HouseSpawner.spawn` validates plan-local). The plans are the towers' own:
## `HouseDefinitions.get_all()` stays the house list, so a random house pick is unchanged.
## The shared reach checks are `tests/_worldgen/doorway_reach_probe.gd`.

const Reach := preload("res://tests/_worldgen/doorway_reach_probe.gd")
const TURNS := [0, 1, 2, 3]
## Seeds per mirror state: `HouseSpawner.spawn` mirrors a plan when its rng's first draw is under
## one half.
const SEEDS_PER_MIRROR := 2
const PLAN_COUNT := 6
## The lobby's size from the brief (about 240 x 200 px), each side within this much.
const LOBBY_SIZE := Vector2(240.0, 200.0)
const LOBBY_SLACK := 40.0
## The room types a tower holds (the brief): the new shop, noodle bar and stockroom and the lobby
## beside today's ripperdoc, netrunner den, security vestibule, hallway and bathroom.
const TOWER_TYPES := [
	"shop", "noodle_bar", "stockroom", "elevator_lobby", "ripperdoc", "netrunner_den",
	"security_vestibule", "hallway", "bathroom",
]


func describe() -> Dictionary:
	return {
		"name": "The six tower plans are logical and walkable, each with one elevator lobby",
		"description": "Every tower plan in all four facings and both mirrors: LayoutRules finds "
			+ "it logical, every doorway is reachable from the front door, it has one front door, "
			+ "at most one exit and exactly one elevator lobby with one interior doorway.",
		"tags": ["worldgen", "navigation", "tower", "layout", "lobby"],
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var plans := TowerDefinitions.get_all()
	t.require(plans.size() == PLAN_COUNT, "there are %d tower plans (found %d)"
			% [PLAN_COUNT, plans.size()])
	for key: String in plans:
		t.check(
			not HouseDefinitions.get_all().has(key),
			"%s is a tower plan, not a house plan" % key,
		)
		_check_plan(t, key)
	var seeds := _mirror_seeds()
	t.require(
		seeds.any(_mirrors) and seeds.any(func(n: int) -> bool: return not _mirrors(n)),
		"the seeds cover both mirror states",
	)
	for key: String in plans:
		for turn: int in TURNS:
			for house_seed: int in seeds:
				await _check_turned(t, key, house_seed, turn)


## Whether `HouseSpawner.spawn` mirrors a plan for `house_seed` (its rng's first draw).
func _mirrors(house_seed: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = house_seed
	return rng.randf() < 0.5


## The first `SEEDS_PER_MIRROR` seeds of each mirror state.
func _mirror_seeds() -> Array:
	var mirrored: Array = []
	var plain: Array = []
	var n := 1
	while mirrored.size() < SEEDS_PER_MIRROR or plain.size() < SEEDS_PER_MIRROR:
		var bucket := mirrored if _mirrors(n) else plain
		if bucket.size() < SEEDS_PER_MIRROR:
			bucket.append(n)
		n += 1
	return mirrored + plain


## Plan `key` from `house_seed`, turned `turn` quarter turns: reachable and logical in world space,
## with its one upright-stencilled lobby.
func _check_turned(t: TestContext, key: String, house_seed: int, turn: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = house_seed
	var house := HouseSpawner.spawn(key, Reach.FAR_AWAY, rng, t.world, { "turn": turn })
	var label := "%s seed %d turn %d" % [key, house_seed, turn]
	if not t.require(house != null, "%s builds" % label):
		return
	_check_world_lobby(t, label, house, turn)
	_check_dressed(t, label, key, house)
	await Reach.check_built(t, house, label, turn != 0)


## Whatever way the tower stands, its front door gets an awning and a glyph sign (`TowerDressing`),
## the sign hung on the wall beside it.
func _check_dressed(t: TestContext, label: String, key: String, house: Node2D) -> void:
	var rooms: Array = WorldGen.get_rooms(house)
	var front: Dictionary = WorldGen.get_openings(house).filter(
		func(o: Dictionary) -> bool: return o["front"],
	)[0]
	var dressing := TowerDressing.dress({
		"node": house,
		"plan": key,
		"rect": WorldGen.bounds(rooms),
		"front": front,
	})
	t.check(dressing["awning"] != null, "%s: no awning over the front door" % label)
	t.check(dressing["sign"] != null, "%s: no glyph sign beside the front door" % label)


## The plan-level rules of tower plan `key`: its types, front door, exits and lobby.
func _check_plan(t: TestContext, key: String) -> void:
	var plan := TowerDefinitions.get_plan(key)
	var rooms: Array = plan["rooms"]
	var openings: Array = plan["openings"]
	for room: Dictionary in rooms:
		t.check(
			TOWER_TYPES.has(room["type"]),
			"%s: %s is not a tower room type" % [key, room["type"]],
		)
	var fronts := openings.filter(func(o: Dictionary) -> bool: return o.get("front", false))
	var exits := openings.filter(func(o: Dictionary) -> bool: return o.get("exit", false))
	t.check(fronts.size() == 1, "%s has %d front doors" % [key, fronts.size()])
	t.check(exits.size() <= 1, "%s has %d exits" % [key, exits.size()])
	_check_lobby(t, key, rooms, openings)


## Exactly one lobby in `rooms`, of about LOBBY_SIZE, whose only doorway is one interior one.
func _check_lobby(t: TestContext, key: String, rooms: Array, openings: Array) -> void:
	var lobbies := rooms.filter(func(r: Dictionary) -> bool: return r["type"] == "elevator_lobby")
	if not t.check(lobbies.size() == 1, "%s has %d elevator lobbies" % [key, lobbies.size()]):
		return
	var lobby: Dictionary = lobbies[0]
	var size: Vector2 = (lobby["rect"] as Rect2).size
	var off := (size - LOBBY_SIZE).abs()
	t.check(off.x <= LOBBY_SLACK and off.y <= LOBBY_SLACK,
		"%s: the lobby is %s, not about %s" % [key, size, LOBBY_SIZE])
	var doorways := openings.filter(func(o: Dictionary) -> bool:
		return HouseSpawner.room_keys_on(rooms, o).has(lobby["key"]))
	t.check(doorways.size() == 1, "%s: the lobby has %d doorways" % [key, doorways.size()])
	for o: Dictionary in doorways:
		t.check(HouseSpawner.room_keys_on(rooms, o).size() == 2 and not o.get("front", false)
				and not o.get("exit", false),
			"%s: the lobby's doorway at %s is not an interior one" % [key, o["pos"]])


## The built (turned) `house` has one lobby in world space: the lobby room's rect (swapped for an
## odd `turn`), one interior doorway and a stencil drawn upright.
func _check_world_lobby(t: TestContext, label: String, house: Node2D, turn: int) -> void:
	var lobbies := WorldGen.get_lobbies(house)
	if not t.check(lobbies.size() == 1, "%s has %d lobbies" % [label, lobbies.size()]):
		return
	var rooms := WorldGen.get_rooms(house).filter(
		func(r: Dictionary) -> bool: return r["type"] == "elevator_lobby",
	)
	if not t.check(rooms.size() == 1, "%s has %d lobby rooms" % [label, rooms.size()]):
		return
	var rect: Rect2 = rooms[0]["rect"]
	t.check(lobbies[0]["rect"] == rect, "%s: the stencil's rect is not the lobby's" % label)
	var size := LOBBY_SIZE if turn % 2 == 0 else Vector2(LOBBY_SIZE.y, LOBBY_SIZE.x)
	t.check(
		(rect.size - size).abs().x <= LOBBY_SLACK and (rect.size - size).abs().y <= LOBBY_SLACK,
		"%s: the lobby is %s, not about %s" % [label, rect.size, size],
	)
	var doorways := WorldGen.get_openings(house).filter(
		func(o: Dictionary) -> bool: return (o["rooms"] as Array).has(rooms[0]["key"]),
	)
	t.check(
		doorways.size() == 1 and doorways[0]["rooms"].size() == 2,
		"%s: the lobby has %d doorways" % [label, doorways.size()],
	)
	t.check(
		absf((lobbies[0]["node"] as Node2D).global_rotation) < 0.001,
		"%s: the lobby stencil is turned" % label,
	)
