extends GameTest
## The six tower ground-floor plans (#182) are logical and walkable, like every house plan: for each
## plan and several seeds (both mirror states) `LayoutRules.check` finds nothing illogical, every
## doorway is reachable from outside the front door, and the plan has exactly one front door, at
## most one exit and exactly one `elevator_lobby`: an empty room of about 240 x 200 px with one
## interior doorway into a room its `LINKS` allow and no exterior door. The plans are the towers'
## own: `HouseDefinitions.get_all()` stays the house list, so a random house pick is unchanged.
## The shared reach checks are `tests/_worldgen/doorway_reach_probe.gd`.

const Reach := preload("res://tests/_worldgen/doorway_reach_probe.gd")
const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8]
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
		"description": "Every tower plan, over several seeds and both mirrors: LayoutRules finds "
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
	for key: String in plans:
		for house_seed in SEEDS:
			await Reach.check_house(t, key, house_seed)


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
