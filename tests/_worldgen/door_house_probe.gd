extends RefCounted
## Shared helpers for the doors-in-houses tests (not a test itself):
## `const Houses := preload("res://tests/_worldgen/door_house_probe.gd")`. The behaviour they assert
## is `docs/doors.md` DR2 to DR4 (issue #21): which doorways of a generated house get a door, which
## way it swings and how it starts. The tables here are the test's own copy of the spec's numbers
## and room-type tiers, so the rules are not read back from the code under test.

## Where a generated house goes, clear of the test arena.
const FAR_AWAY := Vector2(5000, 5000)
## Seeds tried per floorplan.
const SEEDS := 20
## The privacy rank of a room type, the more private room being the higher (docs/doors.md DR2):
## bathroom and netrunner den the most, then bedroom, office and ripperdoc, then the garage and the
## laundry, then kitchen, living spaces, studio and the vestibule, then the hallway.
const PRIVACY := {
	"bathroom": 4, "netrunner_den": 4,
	"bedroom": 3, "home_office": 3, "ripperdoc": 3,
	"garage": 2, "laundry_room": 2,
	"kitchen": 1, "kitchenette": 1, "living_room": 1, "kitchen_living": 1, "studio": 1,
	"security_vestibule": 1,
	"hallway": 0,
}
## A wall's thickness: the doorway's free width is the gap less this (a wall's end stands half a
## thickness into the gap on each side), and the hinge sits on that jamb.
const WALL_THICKNESS := 12.0
## The floorplans that are flats (and the loft): steel doors at the street. The others are houses:
## solid wood.
const FLATS := [
	"studio_flat", "one_bed_flat", "two_bed_flat", "office_loft", "railroad_flat", "micro_flat",
	"corner_flat",
]


## The generated house of `plan_key` from `house_seed`, under `t.world`.
static func generated(t: TestContext, plan_key: String, house_seed: int) -> Node2D:
	return WorldGen.generate(house_seed, plan_key, FAR_AWAY, t.world)


## The room dict (`{ key, type, rect }`) of `key` in `rooms`.
static func room(rooms: Array, key: String) -> Dictionary:
	for r: Dictionary in rooms:
		if r["key"] == key:
			return r
	return {}


## The types of the rooms an opening joins, in its `rooms` order.
static func types_of(rooms: Array, opening: Dictionary) -> Array:
	return (opening["rooms"] as Array).map(
		func(key: String) -> String: return room(rooms, key)["type"],
	)


## Which opening of a floorplan this is: "front", "exit:<room>" or "<room>|<room>" (the two keys
## sorted), so a plan's authored opening and a generated one can be told apart in either mirror
## state.
static func label(opening: Dictionary) -> String:
	var keys: Array = (opening["rooms"] as Array).duplicate()
	keys.sort()
	if opening.get("front", false):
		return "front"
	if opening.get("exit", false):
		return "exit:%s" % keys[0]
	return "%s|%s" % [keys[0], keys[1]]


## The authored openings of `plan_key` by `label`, each as the plan has it (`pos`, `width`, and
## `door` / `door_set` where the plan says so).
static func plan_openings(plan_key: String) -> Dictionary:
	var plan := HouseDefinitions.get_plan(plan_key)
	var out := {}
	for opening: Dictionary in plan["openings"]:
		var keys: Array = []
		for r: Dictionary in plan["rooms"]:
			if (r["rect"] as Rect2).grow(1.0).has_point(opening["pos"]):
				keys.append(r["key"])
		var described := opening.duplicate()
		described["rooms"] = keys
		out[label(described)] = opening
	return out


## The `{ node, opening, material, style }` entry of `WorldGen.get_doors(house)` standing in
## `opening` (null for none).
static func door_in(of_house: Node2D, opening: Dictionary) -> Variant:
	for entry: Dictionary in WorldGen.get_doors(of_house):
		if entry["opening"] == opening:
			return entry
	return null


## A signature of everything solid, clutter and neon a house placed (position and size relative to
## the house, sorted), to tell one layout from another.
static func furnishing(of_house: Node2D) -> Array:
	var out: Array = []
	for node in of_house.find_children("*", "RigidBody2D", true, false):
		if not "size" in node:
			continue
		var at: Vector2 = node.global_position - of_house.global_position
		var size: Vector2 = node.size
		out.append("%d,%d %dx%d" % [roundi(at.x), roundi(at.y), roundi(size.x), roundi(size.y)])
	out.sort()
	return out


## Whether `house` was built mirrored: the plan's front doorway sits at its authored x only
## unmirrored.
static func mirrored(plan_key: String, of_house: Node2D) -> bool:
	var plan := HouseDefinitions.get_plan(plan_key)
	var authored_x := 0.0
	for opening: Dictionary in plan["openings"]:
		if opening.get("front", false):
			authored_x = (opening["pos"] as Vector2).x
	for opening: Dictionary in WorldGen.get_openings(of_house):
		if opening["front"]:
			return not is_equal_approx(
				(opening["pos"] as Vector2).x - of_house.global_position.x,
				authored_x,
			)
	return false


## The footprints (world `Rect2`s) of every solid piece of furniture, every clutter piece and every
## neon tube `of_house` placed: what has to stay out of a door's swing.
static func footprints(of_house: Node2D) -> Array:
	var nodes: Array = []
	for node in of_house.find_children("*", "RigidBody2D", true, false):
		if "size" in node and "solid" in node and node.solid:
			nodes.append(node)
	for piece: Dictionary in WorldGen.get_clutter(of_house):
		nodes.append(piece["node"])
	nodes.append_array(neon_tubes(of_house))
	var out: Array = []
	for node: Node2D in nodes:
		var size: Vector2 = node.size
		out.append(Rect2(node.global_position - size * 0.5, size))
	return out


## The neon tubes `of_house` placed.
static func neon_tubes(of_house: Node2D) -> Array:
	return of_house.find_children("Neon Tube*", "", true, false)


## Whether `rect` reaches into the quarter disc of `radius` about `pivot` that lies on the `along`
## and `into` sides of it (unit axes), by more than a pixel.
static func in_arc(
	rect: Rect2,
	pivot: Vector2,
	along: Vector2,
	into: Vector2,
	radius: float,
) -> bool:
	var u := _span(rect, pivot, along)
	var v := _span(rect, pivot, into)
	if u.y <= 0.0 or v.y <= 0.0:
		return false
	return Vector2(maxf(u.x, 0.0), maxf(v.x, 0.0)).length() < radius - 1.0


## The interval (low, high) `rect` covers along the unit axis `axis` measured from `origin`.
static func _span(rect: Rect2, origin: Vector2, axis: Vector2) -> Vector2:
	var a := (rect.position - origin).dot(axis)
	var b := (rect.end - origin).dot(axis)
	return Vector2(minf(a, b), maxf(a, b))
