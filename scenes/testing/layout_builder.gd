extends RefCounted
## Testing domain: a hand-laid building — walled, floored rooms joined by doorways — made through
## the Objects factories (interface 2) in the house's own wall style. Returns a Node2D annotated
## through `WorldGen.annotate_layout`, so NavBuilder and WorldGen.get_rooms / get_openings work on
## it like on a house.


## Build the layout described by `world` (`{ rooms, doors, thickness }`, world-space) under `parent`
## and return its root. Each room gets its own walls with every door that lies on one of its edges
## cut in.
static func build(world: Dictionary, parent: Node) -> Node2D:
	var root := Node2D.new()
	root.name = "Layout"
	parent.add_child(root)
	var thickness := float(world.get("thickness", 12.0))
	var doors: Array = world.get("doors", [])
	var rooms: Array = []
	for room in world["rooms"]:
		var rect: Rect2 = room["rect"]
		var key := String(room["key"])
		var floor_def := WorldGen.floor_definition(String(room.get("floor", "oak_planks")))
		if not floor_def.is_empty():
			FloorFactory.spawn(rect, floor_def, key.capitalize() + " Floor", root)
		var walls := RoomWalls.new()
		walls.thickness = thickness
		walls.openings = WallFactory.openings_for(rect, doors)
		walls.style = WorldGen.wall_style()
		WallFactory.spawn(rect, walls, key.capitalize(), root)
		rooms.append({ "key": room["key"], "type": room.get("type", room["key"]), "rect": rect })
	WorldGen.annotate_layout(root, rooms, doors)
	for doorway in doors:
		if doorway.has("door"):
			_spawn_door(doorway, root)
	return root


## The door a doorway declares: `door` is `{ material, style, hinge, swing_into, angle?, name? }`
## (`TestSetup.layout`), built from the catalogue's definition of that material and style.
static func _spawn_door(doorway: Dictionary, parent: Node) -> void:
	var spec: Dictionary = doorway["door"]
	var definition := WorldGen.door_definition(String(spec["material"]), String(spec["style"]))
	var opening: Dictionary = spec.duplicate()
	opening["pos"] = doorway["pos"]
	DoorFactory.spawn(opening, definition, parent)
