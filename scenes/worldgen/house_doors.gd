class_name HouseDoors
## World Generation domain: the doors of a house being built (`docs/doors.md` DR2 to DR4). For each
## doorway of the plan it rolls whether it gets a door (`DoorRules`: always for the front and exit
## ones, by its more private room's type inside, or as the plan forces or forbids), which way it
## swings (into its more private room, an exterior door into the house; a tie seeded), which jamb it
## is hinged on (the one nearer that room's corner; a tie seeded), which of the plan's door set it
## is and how it starts (front and exit ones shut; an interior one shut, ajar or open by weight),
## then spawns it through `DoorFactory` (interface 2). Every doorway rolls from a stream of its own,
## `hash([run seed, "doors", its index in the plan])`, drawing the same number of values whatever it
## rolls, so the doors never shift a seed's furniture layout nor each other's.
##
## The swing arc (a quarter disc, the leaf's length, from the hinge across the doorway to the room)
## lies inside the doorway's clearance box (as wide as the doorway and as deep each side of the wall
## as the open leaf reaches, at least `HouseSpawner.OPENING_CLEARANCE`), which furniture, clutter
## and the neon tube keep out of.


## Roll and build the doors of the house of `plan` under `house` (a `Doors` node of it) for the
## doorways `openings` of its `rooms` (in the plan's frame, mirrored as the house is) and return
## them as `[{ node, opening, material, style }]`, `opening` being that doorway's entry of the
## house's `openings` metadata (the same doorways in world space), whose `door` it sets. None when
## `WorldGenDoorConfig.enabled` is off.
static func build(
	plan: Dictionary,
	rooms: Array,
	openings: Array,
	house: Node2D,
	run_seed: int,
) -> Array:
	if not WorldGenDoorConfig.enabled:
		return []
	var world_openings: Array = house.get_meta("openings")
	var holder := Node2D.new()
	holder.name = "Doors"
	house.add_child(holder)
	var built: Array = []
	for i in openings.size():
		var rolled := roll(plan, rooms, openings[i], hash([run_seed, "doors", i]))
		if rolled.is_empty():
			continue
		var definition: Dictionary = rolled["definition"]
		world_openings[i]["door"] = true
		built.append({
			"node": _spawn(rolled, openings[i], "Door %d" % (i + 1), holder, house.position),
			"opening": world_openings[i],
			"material": definition["material"],
			"style": definition["style"],
		})
	return built


## The door `opening` of `plan` gets, rolled from the stream seeded `stream_seed`: `{ definition,
## hinge, swing_into, angle }` (`hinge` in the plan's frame), or {} for none.
static func roll(
	plan: Dictionary,
	rooms: Array,
	opening: Dictionary,
	stream_seed: int,
) -> Dictionary:
	var draws := _draws(stream_seed)
	var keys := HouseSpawner.room_keys_on(rooms, opening)
	if not _has_door(opening, rooms, keys, draws["chance"]):
		return {}

	var exterior := keys.size() == 1
	var outward := HouseSpawner.outward_on(rooms, opening)
	var into := 0 if exterior else _swing_room(rooms, keys, draws["swing_tie"])
	var room_rect: Rect2 = _room_of(rooms, keys[into])["rect"]
	var set_keys := DoorRules.set_of(_kind(opening), plan.get("door_sets", {}))
	var angle := 0.0
	if not exterior:
		angle = _start_angle(draws["state"], draws["ajar"])
	return {
		"definition": DoorCatalog.by_key(set_keys[draws["pick"] % set_keys.size()]),
		"hinge": _hinge(
			opening,
			outward[into],
			room_rect,
			plan["wall_thickness"],
			draws["hinge_tie"],
		),
		"swing_into": -(outward[into] as Vector2),
		"angle": angle,
	}


## Every value a doorway's roll draws, from the stream seeded `stream_seed`, always the same ones in
## the same order whatever the doorway turns out to be: `chance` and the two ties in [0, 1), `pick`
## (an index into the door set), the start `state` and, for an ajar door, its `ajar` angle.
static func _draws(stream_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = stream_seed
	return {
		"chance": rng.randf(),
		"swing_tie": rng.randf(),
		"hinge_tie": rng.randf(),
		"pick": rng.randi(),
		"state": WeightedPick.key(rng, DoorRules.START_WEIGHTS),
		"ajar": rng.randf_range(DoorRules.AJAR_DEGREES.x, DoorRules.AJAR_DEGREES.y),
	}


## The angle (degrees from shut) an interior door starts at in `state` (`shut`, `ajar` at `ajar`
## degrees, or `open`).
static func _start_angle(state: String, ajar: float) -> float:
	if state == "ajar":
		return ajar
	return DoorConfig.open_angle if state == "open" else 0.0


## Build the door of `rolled` (`roll`'s result) in `opening` (the plan's frame, the house at `at` in
## the world) under `holder`, named `door_name`.
static func _spawn(
	rolled: Dictionary,
	opening: Dictionary,
	door_name: String,
	holder: Node2D,
	at: Vector2,
) -> Door:
	return DoorFactory.spawn(
		{
			"name": door_name,
			"pos": at + (opening["pos"] as Vector2),
			"hinge": at + (rolled["hinge"] as Vector2),
			"swing_into": rolled["swing_into"],
			"angle": rolled["angle"],
		},
		rolled["definition"],
		holder,
	)


## Whether the doorway gets a door: the plan's `door` flag if it has one, else always for a front or
## exit doorway, else by `chance_roll` (a draw in [0, 1)) against the chance of its rooms' types.
static func _has_door(
	opening: Dictionary,
	rooms: Array,
	keys: Array,
	chance_roll: float,
) -> bool:
	if opening.has("door"):
		return opening["door"]
	if keys.size() == 1:
		return true
	var types: Array = keys.map(func(key: String) -> String: return _room_of(rooms, key)["type"])
	return chance_roll < DoorRules.chance(types[0], types[1])


## The index (in `keys`) of the room an interior door swings into: the more private one, `tie` (a
## draw in [0, 1)) deciding when both are as private.
static func _swing_room(rooms: Array, keys: Array, tie: float) -> int:
	var first := DoorRules.rank(_room_of(rooms, keys[0])["type"])
	var second := DoorRules.rank(_room_of(rooms, keys[1])["type"])
	if first == second:
		return 0 if tie < DoorRules.TIE_FIRST else 1
	return 0 if first > second else 1


## The hinge of the door in `opening` swinging into the room `rect`, `outward` the way out of that
## room through the doorway: on the jamb, `thickness / 2` in from the gap's edge (where the walls'
## ends stand), nearer the room's corner along the wall; `tie` (a draw in [0, 1)) decides the jamb
## when the doorway is in the middle of the wall.
static func _hinge(
	opening: Dictionary,
	outward: Vector2,
	rect: Rect2,
	thickness: float,
	tie: float,
) -> Vector2:
	var p: Vector2 = opening["pos"]
	var along := Vector2.RIGHT if outward.y != 0.0 else Vector2.DOWN
	var at := p.dot(along)
	var to_low := at - rect.position.dot(along)
	var to_high := rect.end.dot(along) - at
	var side := -1.0 if to_low < to_high else 1.0
	if absf(to_low - to_high) < 1.0:
		side = -1.0 if tie < DoorRules.TIE_FIRST else 1.0
	return p + along * side * (float(opening["width"]) * 0.5 - thickness * 0.5)


## The door set `opening` draws from: the one it names, else `front`, `exit` or `interior`.
static func _kind(opening: Dictionary) -> String:
	if opening.has("door_set"):
		return opening["door_set"]
	if opening.get("front", false):
		return "front"
	return "exit" if opening.get("exit", false) else "interior"


## The room of `rooms` keyed `key`.
static func _room_of(rooms: Array, key: String) -> Dictionary:
	for room: Dictionary in rooms:
		if room["key"] == key:
			return room
	return {}
