class_name WorldGen
## The World Generation domain's single entry point. Given a seed, an optional forced
## floorplan, and where the front entrance should land, it picks a plan, seeds one RNG for the
## whole run (the plan pick is its first draw, so a seed reproduces everything), and builds
## the house via HouseSpawner. Callers (Main) never touch HouseDefinitions/HouseSpawner
## directly — `generate`, `get_rooms`, `get_openings`, `bounds`, `annotate_layout`, the read-only
## catalogue lookups and the test reads `get_wear`, `get_clutter`, `get_street` and
## `get_streetlights` and `get_lobbies` are the whole surface World-Gen exposes, with
## `generate_district` and its reads `house_of` and `district_rooms` (a district's test reads are
## `DistrictReads`).


## Build a house and return its root Node2D (parented under `parent`). `rng_seed` of 0 picks a
## fresh random layout each run; `force_plan` ("" = random) pins a specific floorplan. A doorway
## holds a door as the floorplan's rules roll (`get_doors`) and is an open archway otherwise; the
## house has one front entrance (on its south wall) and, in most floorplans, a back/side/garage
## exit.
static func generate(
	rng_seed: int,
	force_plan: String,
	front_entrance_world: Vector2,
	parent: Node,
) -> Node2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else randi()
	var all_plans: Array = HouseDefinitions.get_all()
	var pick: String = all_plans[rng.randi() % all_plans.size()]
	var plan_key: String = force_plan if force_plan != "" else pick
	GameLog.say("House: %s  seed: %s" % [plan_key, rng.seed])
	return HouseSpawner.spawn(plan_key, front_entrance_world, rng, parent)


## Build a downtown district and return its root Node2D (parented under `parent`, which stays at the
## origin): a 3 x 3 grid of blocks with a tower in each, streets between and round them and a ring
## of roofless shells beyond. The centre tower is the **house**, built from `force_plan` (any house
## or tower plan) or, "" for none, a tower plan drawn by the seed; the others draw tower plans only.
## Each tower is turned by the seed so its front door faces one of its block's streets, and the
## house's front door lands on `front_entrance_world`. `rng_seed` of 0 picks a fresh district; one
## seed reproduces the whole of it.
static func generate_district(
	rng_seed: int,
	force_plan: String,
	front_entrance_world: Vector2,
	parent: Node,
) -> Node2D:
	var district_seed := rng_seed if rng_seed != 0 else randi()
	GameLog.say("District: house %s  seed: %s" % [force_plan, district_seed])
	return DistrictSpawner.spawn(district_seed, force_plan, front_entrance_world, parent)


## The house of a generated `district`: the centre tower's node, on which `get_rooms`,
## `get_openings`, `get_doors` and `get_lobbies` read as for a lone house. Null for a null district.
static func house_of(district: Node2D) -> Node2D:
	if district == null:
		return null
	return district.get_meta("house", null)


## Every tower's rooms of a generated `district` as `{ key, type, rect }` in WORLD space: the
## house's keys plain, a neighbour's keyed `<block>:<key>` (block 0 to 8), so no two clash. Empty
## for a null district.
static func district_rooms(district: Node2D) -> Array:
	if district == null:
		return []
	return district.get_meta("rooms", [])


## Describe a hand-laid layout `root` the way a generated house describes itself, so `get_rooms`,
## `get_openings` and the nav builder read it unchanged. `rooms` are `{ key, type, rect }` in WORLD
## space; `doors` are `{ pos, width, door? }` in world space (a `door` entry says a door stands in
## it: the opening reports `door` true), and a door on one room's wall only is the front entrance.
## For the Testing domain's arenas and room layouts.
static func annotate_layout(root: Node2D, rooms: Array, doors: Array = []) -> void:
	root.set_meta("rooms", rooms)
	var openings: Array = []
	for door in doors:
		var keys := HouseSpawner.room_keys_on(rooms, door)
		openings.append({
			"pos": door["pos"],
			"width": door["width"],
			"front": keys.size() == 1,
			"exit": false,
			"rooms": keys,
			"outward": HouseSpawner.outward_on(rooms, door),
			"door": door.has("door"),
		})
	root.set_meta("openings", openings)


## The generated house's rooms as an Array of { key, type, rect } with `rect` in WORLD
## space. For callers (Main) that place entities into rooms; empty for a null house.
static func get_rooms(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("rooms", [])


## The generated house's doorways as an Array of { pos, width, front, exit, rooms, outward } in
## WORLD space (`rooms` = keys of the rooms the doorway joins: two for an interior door, one for the
## front entrance or an `exit`; `outward` = the way out of each of those rooms through it, in
## `rooms`' order: the unit normal of the wall it is on, pointing away from that room). Empty for a
## null house.
static func get_openings(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("openings", [])


## The generated house's wear as an Array of { room, pos, layer }: one entry per wear cluster,
## `room` its room's key, `pos` its centre in WORLD space and `layer` the node drawing that room's
## wear (one per room). Empty for a null house or a hand-laid layout. (A test read.)
static func get_wear(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("wear", [])


## The generated house's clutter as an Array of { room, key, node }: one entry per walk-over piece
## its rooms were strewn with, `key` its catalogue key and `node` the placed piece. Empty for a null
## house or a hand-laid layout. (A test read.)
static func get_clutter(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("clutter", [])


## The street ring round a generated house as an Array of { kind, rect, node }: `kind` `street` or
## `sidewalk`, `rect` the piece's WORLD rect and `node` the floor that draws it (none of them a
## sound surface). Empty for a null house or a hand-laid layout. (A test read.)
static func get_street(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("street", [])


## The street lamps along the front of a generated house as an Array of { pos, node }: `pos` a
## lamp's centre in WORLD space, `node` the placed piece (a solid, anchored metal post, carved into
## the nav map, its arm and head overhead). None stands within the clearance of a front or exit
## doorway nor in the strip straight out of one. Empty for a null house or a hand-laid layout. (A
## test read.)
static func get_streetlights(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("streetlights", [])


## The doors a generated house was built with as an Array of { node, opening, material, style }:
## `node` the `Door` (interface 24), `opening` the doorway's entry of `get_openings` it stands in,
## `material` and `style` its catalogue definition's. Empty for a null house, a hand-laid layout or
## a house built with `worldgen.doors` off.
static func get_doors(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("doors", [])


## The elevator lobbies a generated house laid as an Array of { room, rect, node, text }: `room` the
## lobby room's key, `rect` its WORLD rect, `node` the floor stencil laid in it (a `Sprite2D`) and
## `text` what it says. Empty for a null house, a hand-laid layout or a plan with no lobby. (A test
## read.)
static func get_lobbies(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("lobbies", [])


## The bounding box of `rooms`' rects (`{ rect, ... }` dicts, any one frame), a zero Rect2 for none.
static func bounds(rooms: Array) -> Rect2:
	var box := Rect2()
	for i in range(rooms.size()):
		box = rooms[i]["rect"] if i == 0 else box.merge(rooms[i]["rect"])
	return box


## The catalogue object definition for `key` (a plain dict for ObjectFactory.spawn), or {} if
## unknown. For callers outside World-Gen (the Testing domain) that place single catalogue pieces.
static func object_definition(key: String) -> Dictionary:
	return ObjectDefinitions.get_definition(key)


## The catalogue floor definition for `key` (a plain dict for FloorFactory.spawn), or {} if unknown.
static func floor_definition(key: String) -> Dictionary:
	return GeneralCatalog.FLOORS.get(key, {})


## The catalogue door definition of `material` in `style` (a plain dict for DoorFactory.spawn), or
## {} if unknown. For callers outside World-Gen (the Testing domain) that place single doors.
static func door_definition(material: String, style: String) -> Dictionary:
	return DoorCatalog.definition(material, style)


## The house wall style (the `style` dict for WallFactory.spawn), so other builders match the house.
static func wall_style() -> Dictionary:
	return GeneralCatalog.WALL
