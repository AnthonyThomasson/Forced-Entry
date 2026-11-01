class_name DistrictSpawner
## World Generation domain: builds a downtown district (`DistrictLayout` is its geometry): the
## street grid (DistrictStreets), a tower in every block, built as a house is (HouseSpawner: walls,
## doors, furniture, clutter, wear), and the ring of shells (DistrictShells). The centre tower is
## the house, placed so its front door lands on the entrance; the district hangs off one root Node2D
## that stays at the origin, so every position it reports is in world space.

const HOUSE_BLOCK := DistrictLayout.HOUSE_BLOCK


## Build the district of `district_seed` under `parent` and return its root. `force_plan` ("" for
## none) is the centre tower's plan, any house or tower plan. The root carries what was placed as
## metadata, read through WorldGen: `house`, `towers`
## (`{ block, plan, turn, node, rect, front, shadow, podium, awning, sign }`), `rooms`
## (`WorldGen.district_rooms`), `streets` and `shells`.
static func spawn(
	district_seed: int,
	force_plan: String,
	front_entrance_world: Vector2,
	parent: Node,
) -> Node2D:
	var layout := DistrictLayout.compute(district_seed, force_plan)
	var blocks: Array = layout["blocks"]
	var centre: Dictionary = blocks[HOUSE_BLOCK]
	var delta: Vector2 = front_entrance_world - ((centre["corner"] as Vector2) + centre["front"])
	var root := Node2D.new()
	root.name = "District"
	parent.add_child(root)
	root.set_meta("streets", DistrictStreets.build(layout, delta, root, district_seed))
	var towers := _towers(blocks, delta, root)
	_street_furniture(layout, delta, root, towers, district_seed)
	root.set_meta("towers", towers)
	root.set_meta("house", towers[HOUSE_BLOCK]["node"])
	root.set_meta("rooms", _rooms(towers))
	root.set_meta("shells", DistrictShells.build(layout["shells"], delta, root, district_seed))
	return root


## The street lamps and the sidewalk clutter of the district, kept clear of the doorways of every
## tower and of the crossings: set as `streetlights` and `clutter` on `root`.
static func _street_furniture(
	layout: Dictionary,
	delta: Vector2,
	root: Node2D,
	towers: Array,
	district_seed: int,
) -> void:
	var pavements: Array = []
	var bodies: Array[Rect2] = []
	var zones: Array = []
	for block: Dictionary in layout["blocks"]:
		pavements.append(
			Rect2((block["area"] as Rect2).position + delta, (block["area"] as Rect2).size)
			.grow(WorldGenDistrictConfig.sidewalk),
		)
	for tower: Dictionary in towers:
		zones.append_array(StreetLamps.door_zones(
			WorldGen.get_rooms(tower["node"]),
			WorldGen.get_openings(tower["node"]),
		))
		bodies.append((tower["rect"] as Rect2).grow(_body()))
	var keepouts: Array[Rect2] = []
	for landing: Rect2 in layout["landings"]:
		keepouts.append(Rect2(landing.position + delta, landing.size))
	var lamps := DistrictStreets.lamps(pavements, zones, keepouts, root, district_seed)
	root.set_meta("streetlights", lamps)
	var posts: Array[Rect2] = []
	for lamp: Dictionary in lamps:
		var size: Vector2 = (lamp["node"] as Node2D).get("size")
		posts.append(Rect2((lamp["pos"] as Vector2) - size * 0.5, size))
	var taken := { "zones": zones, "keepouts": keepouts, "bodies": bodies, "lamps": posts }
	root.set_meta("clutter", DistrictStreets.clutter(pavements, taken, root, district_seed))


## How far past a tower's rooms the street furniture keeps off it: the podium band and the margin.
static func _body() -> float:
	return WorldGenTowerConfig.podium_depth + WorldGenTowerConfig.tower_margin


## A tower in every block of `blocks`, shifted by `delta`, under `root`, dressed (TowerDressing):
## the entries `DistrictReads.get_towers` describes. Each is built from an RNG of its own
## (`tower_seed`), so a seed's towers never shift.
static func _towers(blocks: Array, delta: Vector2, root: Node2D) -> Array:
	var towers: Array = []
	for block: Dictionary in blocks:
		var rng := RandomNumberGenerator.new()
		rng.seed = block["tower_seed"]
		var door: Vector2 = (block["corner"] as Vector2) + block["front"] + delta
		var node := HouseSpawner.spawn(
			block["plan"],
			door,
			rng,
			root,
			{ "turn": block["turn"], "street": false },
		)
		node.name = "House" if block["block"] == HOUSE_BLOCK else "Tower%d" % block["block"]
		var tower := {
			"block": block["block"],
			"plan": block["plan"],
			"turn": block["turn"],
			"node": node,
			"rect": WorldGen.bounds(WorldGen.get_rooms(node)),
			"front": WorldGen.get_openings(node).filter(
				func(o: Dictionary) -> bool: return o["front"],
			)[0],
		}
		tower.merge(TowerDressing.dress(tower))
		towers.append(tower)
	return towers


## Every tower's rooms as `{ key, type, rect }`: the house's keys plain, a neighbour's keyed
## `<block>:<key>` so no two clash.
static func _rooms(towers: Array) -> Array:
	var rooms: Array = []
	for tower: Dictionary in towers:
		for room: Dictionary in WorldGen.get_rooms(tower["node"]):
			var keyed := room.duplicate()
			if tower["block"] != HOUSE_BLOCK:
				keyed["key"] = "%d:%s" % [tower["block"], room["key"]]
			rooms.append(keyed)
	return rooms
