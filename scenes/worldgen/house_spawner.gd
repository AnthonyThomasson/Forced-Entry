class_name HouseSpawner
## World Generation domain: builds a house from a HouseDefinitions floorplan: walls per room (via
## the Objects domain's WallFactory, in the GeneralCatalog.WALL style, with every doorway opening
## cut into each wall it lies on), furniture per room (via RoomFurnisher), its clutter and neon
## (RoomDresser) and each room's floor (via FloorFactory, the one its furnishing palette names);
## then, once every room stands, each room's wear (RoomDresser, through WearFactory), the street
## ring round the house (FloorFactory) and the street lamps along its front (ObjectFactory), clear
## of its doorways, and each doorway's door (HouseDoors). The house is positioned so its front
## entrance lands on a point. A plan may also carry `exit` openings (a back/side/garage door).

## Kept free of furniture on each side of a doorway opening (at least; a wide doorway's door reaches
## further, `_opening_clearances`).
const OPENING_CLEARANCE := 50.0
## Gap between wall faces and furniture.
const INTERIOR_MARGIN := 6.0
## The way out of a room through each of its walls (`WallFactory.openings_for`'s `side`): the wall's
## unit normal pointing away from the room.
const OUTWARD := {
	WallFactory.WallScript.Side.TOP: Vector2.UP,
	WallFactory.WallScript.Side.BOTTOM: Vector2.DOWN,
	WallFactory.WallScript.Side.LEFT: Vector2.LEFT,
	WallFactory.WallScript.Side.RIGHT: Vector2.RIGHT,
}


## The floorplan for `key` from the houses or, failing that, the towers; {} if neither has it.
static func plan_of(key: String) -> Dictionary:
	var plan := HouseDefinitions.get_plan(key)
	return plan if not plan.is_empty() else TowerDefinitions.get_plan(key)


## Build the named floorplan under `parent`, positioned so its front entrance lands on
## `front_entrance_world`. `rng` drives every random choice (the doors roll from streams of their
## own). A doorway with no door (`worldgen.doors` off, or the roll) is an open archway. `options`:
##   turn:   int  -- quarter turns clockwise on screen (0 to 3, default 0), applied after the mirror
##                   the way the mirror is: a south front faces west, north, east. The plan is
##                   validated before it turns (plan-local: the front on its south wall).
##   street: bool -- build the street ring and the street lamps (default true); a district builds
##                   its own streets.
## Returns the house root.
static func spawn(
	plan_key: String,
	front_entrance_world: Vector2,
	rng: RandomNumberGenerator,
	parent: Node,
	options: Dictionary = {},
) -> Node2D:
	var plan := plan_of(plan_key)
	if plan.is_empty():
		push_error("Unknown house plan: ", plan_key)
		return null

	var laid := _mirrored(plan, rng)
	var rooms: Array = laid["rooms"]
	var openings: Array = laid["openings"]

	if openings.filter(_is_front).size() != 1:
		push_error("House plan needs exactly one front entrance: ", plan_key)
		return null

	_validate(rooms, openings, plan_key)
	_turn(rooms, openings, int(options.get("turn", 0)))
	var front: Array = openings.filter(_is_front)

	var house := Node2D.new()
	house.name = "House"
	house.position = front_entrance_world - (front[0]["pos"] as Vector2)
	parent.add_child(house)

	var built := _build_rooms(plan, rooms, openings, house, rng)
	var world_openings := _openings_world(rooms, openings, house.position)
	house.set_meta("rooms", _rooms_world(rooms, house.position))
	house.set_meta("openings", world_openings)
	house.set_meta("doors", HouseDoors.build(plan, rooms, openings, house, rng.seed))
	house.set_meta("clutter", built["clutter"])
	house.set_meta("wear", built["wear"])
	house.set_meta("lobbies", built["lobbies"])
	var street: bool = options.get("street", true)
	var front_out: Vector2 = outward_on(rooms, front[0])[0]
	house.set_meta("street", _street(rooms, front_out, house, rng.seed) if street else [])
	house.set_meta(
		"streetlights",
		_streetlights(rooms, openings, front_out, house, rng.seed) if street else [],
	)
	return house


## The footprint `spawn` would give plan `plan_key` for an rng seeded `rng_seed`, turned `turn`
## quarter turns, without building it: `{ size, front }`, the size of the rooms' bounds and where
## the front door stands in them (from their top-left corner). A district sizes its blocks from
## these.
static func footprint(plan_key: String, rng_seed: int, turn: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var laid := _mirrored(plan_of(plan_key), rng)
	var rooms: Array = laid["rooms"]
	var openings: Array = laid["openings"]
	_turn(rooms, openings, turn)
	var front: Dictionary = openings.filter(_is_front)[0]
	var bounds := WorldGen.bounds(rooms)
	return { "size": bounds.size, "front": (front["pos"] as Vector2) - bounds.position }


## A copy of `plan`'s rooms and openings, mirrored left to right when `rng`'s next draw says (half
## the time): `{ rooms, openings }`. The one place that draw is made, so `spawn` and `footprint`
## stay in step.
static func _mirrored(plan: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var rooms: Array = plan["rooms"].duplicate(true)
	var openings: Array = plan["openings"].duplicate(true)
	if rng.randf() < 0.5:
		_mirror_x(rooms, openings)
	return { "rooms": rooms, "openings": openings }


## Every room of `plan` built under `house` (`_build_room`), then their wear: `{ clutter, wear,
## lobbies }`, the clutter as `[{ room, key, node }]`, the wear as `[{ room, pos, layer }]` and the
## elevator lobbies' stencils as `[{ room, rect, node, text }]`.
static func _build_rooms(
	plan: Dictionary,
	rooms: Array,
	openings: Array,
	house: Node2D,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var blocked := _opening_clearances(rooms, openings, plan["wall_thickness"])
	var placed := { "clutter": [], "lobbies": [] }
	## Per room, for the wear pass: `[site, floor definition]`.
	var dressing: Array = []
	for room in rooms:
		var site := _site(room, plan["wall_thickness"], blocked, rng.seed)
		dressing.append([site, _build_room(site, openings, rng, house, placed)])
	# Wear after every room stands, so a mark on a shared wall draws over both rooms' caps.
	return {
		"clutter": placed["clutter"],
		"wear": _wear(dressing, openings, house),
		"lobbies": placed["lobbies"],
	}


## A room of the plan as RoomFurnisher and RoomDresser read it (its furniture node not built yet).
static func _site(
	room: Dictionary,
	wall_thickness: float,
	blocked: Array,
	run_seed: int,
) -> RoomSite:
	var site := RoomSite.new()
	site.room = room
	site.wall_thickness = wall_thickness
	site.blocked = blocked
	site.run_seed = run_seed
	return site


## Build `site`'s room under `house`: its walls (every doorway of `openings` on them cut in), its
## furniture (RoomFurnisher, drawing from `rng`) and clutter (RoomDresser, appended to
## `placed["clutter"]` as `{ room, key, node }`) under a node of its own, then its floor, the one
## its furnishing palette names. A room whose recipe is `bare` (the elevator lobby) is given no
## clutter or neon; if the recipe has `text`, that is laid on its floor as a stencil (appended to
## `placed["lobbies"]`). Returns the floor's definition ({} for none).
static func _build_room(
	site: RoomSite,
	openings: Array,
	rng: RandomNumberGenerator,
	house: Node2D,
	placed: Dictionary,
) -> Dictionary:
	var rect: Rect2 = site.room["rect"]
	var room_name := (site.room["key"] as String).capitalize()
	var walls := RoomWalls.new()
	walls.thickness = site.wall_thickness
	walls.openings = WallFactory.openings_for(rect, openings)
	walls.style = GeneralCatalog.WALL
	WallFactory.spawn(rect, walls, room_name, house)

	site.furniture = Node2D.new()
	site.furniture.name = room_name + " Furniture"
	house.add_child(site.furniture)
	var interior := rect.grow(-(site.wall_thickness * 0.5 + INTERIOR_MARGIN))
	var palette := RoomFurnisher.furnish(site, interior, rng)
	var recipe := ArrangementDefinitions.get_recipe(site.room["type"])
	if not recipe.get("bare", false):
		for piece: Dictionary in RoomDresser.strew(
			site,
			recipe.get("clutter", GeneralCatalog.CLUTTER),
		):
			placed["clutter"].append({
				"room": site.room["key"],
				"key": piece["key"],
				"node": piece["node"],
			})
	# The floor runs to the wall centerlines, so the walls cover the seams between rooms.
	var floor_def: Dictionary = GeneralCatalog.FLOORS.get(palette.get("floor", ""), {})
	if not floor_def.is_empty():
		FloorFactory.spawn(rect, floor_def, room_name + " Floor", house)
	if recipe.has("text"):
		placed["lobbies"].append(_lay_stencil(site, recipe["text"], room_name, house))
	return floor_def


## Lay `text` as a floor stencil over `site`'s room, between the faces of its walls, under `house`:
## `{ room, rect, node, text }`, `rect` the room's in WORLD space.
static func _lay_stencil(
	site: RoomSite,
	text: String,
	room_name: String,
	house: Node2D,
) -> Dictionary:
	var rect: Rect2 = site.room["rect"]
	var node := DecalFactory.stencil(
		rect.grow(-site.wall_thickness * 0.5),
		{ "text": text, "style": "hazard" },
		room_name + " Stencil",
		house,
	)
	return {
		"room": site.room["key"],
		"rect": Rect2(house.position + rect.position, rect.size),
		"node": node,
		"text": text,
	}


## Each room's wear (`dressing`: `[site, floor definition]` per room, its walls cut short of
## `openings`) laid under `house`, as `[{ room, pos, layer }]` (`pos` in world space).
static func _wear(dressing: Array, openings: Array, house: Node2D) -> Array:
	var wear_world: Array = []
	for entry: Array in dressing:
		var site: RoomSite = entry[0]
		for cluster: Dictionary in RoomDresser.wear(site, entry[1], openings, house):
			wear_world.append({
				"room": site.room["key"],
				"pos": house.position + (cluster["pos"] as Vector2),
				"layer": cluster["layer"],
			})
	return wear_world


## Room rects in WORLD space (`origin` the house's position, after mirroring), for callers that
## spawn entities into rooms: `[{ key, type, rect }]`, exposed via WorldGen.get_rooms(house).
static func _rooms_world(rooms: Array, origin: Vector2) -> Array:
	var rooms_world: Array = []
	for room in rooms:
		var rect: Rect2 = room["rect"]
		rooms_world.append({
			"key": room["key"], "type": room["type"],
			"rect": Rect2(origin + rect.position, rect.size),
		})
	return rooms_world


## The street lamps along the front sidewalk, spawned under `house` (a `Street Lamps` node) by
## StreetLamps: the row centred on the front, each post `streetlight_curb` px in from the curb with
## its arm out over the road, on the side the front door faces (`front_out`, whichever way the house
## is turned). A lamp any part of which would stand by a front or exit doorway (the door rule) is
## dropped. Its own RNG, seeded from `run_seed`, so the furniture layout never shifts. Returns them
## as `[{ pos, node }]` (`pos` in world space).
static func _streetlights(
	rooms: Array,
	openings: Array,
	front_out: Vector2,
	house: Node2D,
	run_seed: int,
) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, "streetlights"])
	var holder := Node2D.new()
	holder.name = "Street Lamps"
	house.add_child(holder)
	var walk := WorldGen.bounds(rooms).grow(WorldGenStreetConfig.sidewalk)
	return StreetLamps.place(
		holder,
		StreetLamps.run_along(walk, front_out),
		StreetLamps.door_zones(rooms, openings),
		rng,
	)


## The street ring round the house: a sidewalk hugging the outline of its rooms and asphalt beyond
## it, four strips of each (the top and bottom ones spanning the corners), laid through FloorFactory
## under `house` from GeneralCatalog.STREET, each with its marks (seeded from `run_seed`; the lane
## down the road in front, the one on the side `front_out` the front door faces). Returns them as
## `[{ kind, rect, node }]` (`rect` in world space).
static func _street(rooms: Array, front_out: Vector2, house: Node2D, run_seed: int) -> Array:
	var bounds := WorldGen.bounds(rooms)
	var walk := bounds.grow(WorldGenStreetConfig.sidewalk)
	var outer := bounds.grow(WorldGenStreetConfig.reach)
	var pieces := _street_pieces(bounds, front_out)
	var out: Array = []
	for i in pieces.size():
		var piece: Array = pieces[i]
		var kind: String = piece[0]
		var street_key := "sidewalk" if kind == "sidewalk" else "asphalt"
		var definition: Dictionary = GeneralCatalog.STREET[street_key].duplicate(true)
		definition["marks"] = {
			"seed": hash([run_seed, "street", i]),
			"edges": piece[2],
			"lane": piece[3],
		}
		definition["tile_from"] = walk.position if kind == "sidewalk" else outer.position
		var node := FloorFactory.spawn(
			piece[1],
			definition,
			"%s %d" % [kind.capitalize(), i % 4 + 1],
			house,
		)
		out.append({
			"kind": kind,
			"rect": Rect2(house.position + (piece[1] as Rect2).position, (piece[1] as Rect2).size),
			"node": node,
		})
	return out


## The street ring's pieces round `bounds` (the rooms'), `[kind, rect, the edges its curb
## (sidewalk) or gutter (road) runs along, lane]`: the four sidewalks, then the four roads, the lane
## on the road on the `front_out` side.
static func _street_pieces(bounds: Rect2, front_out: Vector2) -> Array:
	var side := WorldGenStreetConfig.sidewalk
	var walk := bounds.grow(side)
	var outer := bounds.grow(WorldGenStreetConfig.reach)
	var road := WorldGenStreetConfig.reach - side
	var roads: Array = [
		[Rect2(outer.position.x, outer.position.y, outer.size.x, road), Vector2.UP],
		[Rect2(outer.position.x, walk.end.y, outer.size.x, road), Vector2.DOWN],
		[Rect2(outer.position.x, walk.position.y, road, walk.size.y), Vector2.LEFT],
		[Rect2(walk.end.x, walk.position.y, road, walk.size.y), Vector2.RIGHT],
	]
	var pieces: Array = [
		[
			"sidewalk",
			Rect2(walk.position.x, walk.position.y, walk.size.x, side),
			[Vector2.UP, Vector2.LEFT, Vector2.RIGHT],
			false,
		],
		[
			"sidewalk",
			Rect2(walk.position.x, bounds.end.y, walk.size.x, side),
			[Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT],
			false,
		],
		["sidewalk", Rect2(walk.position.x, bounds.position.y, side, bounds.size.y),
			[Vector2.LEFT], false],
		["sidewalk", Rect2(bounds.end.x, bounds.position.y, side, bounds.size.y),
			[Vector2.RIGHT], false],
	]
	for road_piece: Array in roads:
		# A road's gutter runs along the edge by the sidewalk: the side opposite the way it lies.
		pieces.append(["street", road_piece[0], [-road_piece[1]], road_piece[1] == front_out])
	return pieces


## Every doorway as `{ pos, width, front, exit, rooms, outward, door }` in WORLD space; `rooms` are
## the keys of the rooms whose wall it cuts (one for the front entrance or an exit, two for an
## interior door), `outward` the way out of each of them through it (`outward_on`, in `rooms`'
## order) and `door` whether a door stands in it (false here: `HouseDoors.build` sets it).
static func _openings_world(rooms: Array, openings: Array, origin: Vector2) -> Array:
	var result: Array = []
	for opening in openings:
		result.append({
			"pos": origin + (opening["pos"] as Vector2), "width": opening["width"],
			"front": opening.get("front", false), "exit": opening.get("exit", false),
			"rooms": room_keys_on(rooms, opening),
			"outward": outward_on(rooms, opening), "door": false,
		})
	return result


## The keys of the rooms whose wall `opening` (`{ pos, width }`) lies on.
static func room_keys_on(rooms: Array, opening: Dictionary) -> Array:
	var keys: Array = []
	for room in rooms:
		if not WallFactory.openings_for(room["rect"], [opening]).is_empty():
			keys.append(room["key"])
	return keys


## The way out of each room whose wall `opening` (`{ pos, width }`) lies on, in `room_keys_on`'s
## order: the unit normal of that wall pointing away from the room (`OUTWARD`).
static func outward_on(rooms: Array, opening: Dictionary) -> Array:
	var out: Array = []
	for room in rooms:
		var cut := WallFactory.openings_for(room["rect"], [opening])
		if not cut.is_empty():
			out.append(OUTWARD[cut[0]["side"]])
	return out


## Author-error checks (warnings only): overlapping rooms, an opening not on the wall(s) it should
## be on, and anything LayoutRules finds illogical (a bathroom front door, a pass-through bathroom,
## a room nothing reaches).
static func _validate(rooms: Array, openings: Array, plan_key: String) -> void:
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			_warn_overlap(rooms[i], rooms[j], plan_key)

	for opening in openings:
		_warn_misplaced(rooms, opening, plan_key)

	for problem: String in LayoutRules.check(rooms, _openings_world(rooms, openings, Vector2.ZERO)):
		push_warning("House %s: %s" % [plan_key, problem])


## Warn when rooms `a` and `b` of plan `plan_key` overlap.
static func _warn_overlap(a: Dictionary, b: Dictionary, plan_key: String) -> void:
	if (a["rect"] as Rect2).grow(-1.0).intersects((b["rect"] as Rect2).grow(-1.0)):
		push_warning("House %s: rooms %s and %s overlap" % [plan_key, a["key"], b["key"]])


## Warn when `opening` of plan `plan_key` is not on the walls it should be on: a front entrance or
## an exit on exactly one room's wall, an interior opening on a wall two rooms share.
static func _warn_misplaced(rooms: Array, opening: Dictionary, plan_key: String) -> void:
	var touching := rooms.filter(func(room: Dictionary) -> bool:
		return not WallFactory.openings_for(room["rect"], [opening]).is_empty()).size()
	if opening.get("front", false) or opening.get("exit", false):
		if touching != 1:
			push_warning("House %s: %s at %s is not on exactly one room wall" % [
				plan_key,
				"front entrance" if opening.get("front", false) else "exit",
				opening["pos"],
			])
	elif touching != 2:
		push_warning("House %s: interior opening at %s is not on a shared wall"
				% [plan_key, opening["pos"]])


## Whether `opening` is the plan's front entrance.
static func _is_front(opening: Dictionary) -> bool:
	return opening.get("front", false)


## Turn the floorplan `quarter_turns` quarter turns clockwise on screen (a point (x, y) goes to
## (-y, x), so a south front faces west), in place, then slide it so its bounds start at the origin.
static func _turn(rooms: Array, openings: Array, quarter_turns: int) -> void:
	var turns := posmod(quarter_turns, 4)
	if turns == 0:
		return
	for _i in turns:
		for room in rooms:
			var r: Rect2 = room["rect"]
			room["rect"] = Rect2(-r.end.y, r.position.x, r.size.y, r.size.x)
		for opening in openings:
			var p: Vector2 = opening["pos"]
			opening["pos"] = Vector2(-p.y, p.x)
	var corner := WorldGen.bounds(rooms).position
	for room in rooms:
		var r: Rect2 = room["rect"]
		room["rect"] = Rect2(r.position - corner, r.size)
	for opening in openings:
		opening["pos"] = (opening["pos"] as Vector2) - corner


## Flip the floorplan left-to-right for extra layout variety.
static func _mirror_x(rooms: Array, openings: Array) -> void:
	var width := 0.0
	for room in rooms:
		width = maxf(width, (room["rect"] as Rect2).end.x)
	for room in rooms:
		var r: Rect2 = room["rect"]
		room["rect"] = Rect2(width - r.end.x, r.position.y, r.size.x, r.size.y)
	for opening in openings:
		var p: Vector2 = opening["pos"]
		opening["pos"] = Vector2(width - p.x, p.y)


## A box straddling each doorway opening that furniture must stay out of: as wide as the doorway
## and, each side of its wall, `OPENING_CLEARANCE` deep or as far as its open door reaches if that
## is further. The leaf fills the gap between the two walls' ends (the doorway less the wall's
## thickness, less a pixel of slack) and turns about a pivot 3 px off its hinge into the room, so
## its far end stands `width - wall_thickness + 2` px from the wall line (50 px at a 60 px
## doorway, 59 at a 69 px one).
static func _opening_clearances(rooms: Array, openings: Array, wall_thickness: float) -> Array:
	var blocked: Array = []
	for opening in openings:
		var p: Vector2 = opening["pos"]
		var width: float = opening["width"]
		var depth := maxf(OPENING_CLEARANCE, width - wall_thickness + 2.0)
		var on_horizontal_wall := outward_on(rooms, opening).any(
			func(out: Vector2) -> bool: return out.y != 0.0,
		)
		if on_horizontal_wall:
			blocked.append(
				Rect2(p.x - width * 0.5, p.y - depth, width, depth * 2.0),
			)
		else:
			blocked.append(
				Rect2(p.x - depth, p.y - width * 0.5, depth * 2.0, width),
			)
	return blocked
