extends RefCounted
## The showroom's staging helpers: what a set's builder spawns, and the list of it all so the stage
## can remove a set whole. Real pieces come through the published factories (interface 2): floors
## from `WorldGen.floor_definition` and the street catalogue, the house wall style, a catalogue
## piece's definition (anchored, so a shove does not scatter the exhibit). Showroom variants are
## `Sprites` (a showroom painter rendered by `PixelArt`).

const Sprites := preload("res://sandboxes/showroom/downtown_district/sprites.gd")
const FloorLabel := preload("res://sandboxes/showroom/downtown_district/floor_label.gd")
## The exhibit's plot (px): where an exhibit's content sits and how wide it is.
const PLOT_W := 300.0
const WALL_THICKNESS := 12.0

## Where the nodes a set spawns are added, and everything added so far.
var parent: Node
var spawned: Array[Node] = []


func _init(under: Node) -> void:
	parent = under


## Add `node` beside the stage and keep it for removal; returns it.
func add(node: Node) -> Node:
	parent.add_child(node)
	spawned.append(node)
	if node is Node2D:
		Sprites.settle(node)
	return node


## Free everything spawned. A frozen piece taken out of the tree with `remove_child` trips an engine
## error (`self_list.h`), so each node is freed in place and the stage builds the next set a frame
## later, when the last one is gone.
func clear() -> void:
	for node in spawned:
		if is_instance_valid(node):
			node.queue_free()
	spawned.clear()


## A real room floor of the catalogue key `key` over `rect`.
func ground(rect: Rect2, key: String) -> Node:
	var node := FloorFactory.spawn(rect, WorldGen.floor_definition(key), "Floor " + key, parent)
	spawned.append(node)
	return node


## A real street floor (`asphalt` or `sidewalk`, the street catalogue's) over `rect`; `edges` are
## its sides by the other kind (the curb or gutter), `lane` draws the lane dashes, `tile_from` is
## the point the slab grid starts from.
func street(rect: Rect2, kind: String, tile_from: Vector2, edges := [], lane := false) -> Node:
	var def: Dictionary = GeneralCatalog.STREET[kind].duplicate(true)
	def["marks"] = { "seed": hash([rect, kind]), "edges": edges, "lane": lane }
	def["tile_from"] = tile_from
	var node := FloorFactory.spawn(rect, def, kind.capitalize(), parent)
	spawned.append(node)
	return node


## A walled room over `rect` in the house wall style, its floor the catalogue's `floor_key` (none
## when empty), a doorway of `width` cut through each of `doorways` (world points on its walls).
func room(rect: Rect2, floor_key: String, doorways := [], width := 60.0) -> Node:
	if floor_key != "":
		ground(rect, floor_key)
	var walls := RoomWalls.new()
	walls.thickness = WALL_THICKNESS
	var doors: Array = []
	for at: Vector2 in doorways:
		doors.append({ "pos": at, "width": width })
	walls.openings = WallFactory.openings_for(rect, doors)
	walls.style = WorldGen.wall_style()
	var node := WallFactory.spawn(rect, walls, "Walls", parent)
	spawned.append(node)
	return node


## A real catalogue piece `key` at `pos`, anchored.
func piece(key: String, pos: Vector2, opts := {}) -> Node:
	var def := WorldGen.object_definition(key).duplicate(true)
	def["anchored"] = true
	var node := ObjectFactory.spawn(def, pos, parent, opts)
	spawned.append(node)
	return node


## A real catalogue piece `key` with its top-left corner at `corner` (a piece spawns by its centre).
func piece_at(key: String, corner: Vector2, opts := {}) -> Node:
	var size: Vector2 = WorldGen.object_definition(key)["size"]
	if opts.get("rotated", false):
		size = Vector2(size.y, size.x)
	return piece(key, corner + size * 0.5, opts)


## A real door of the catalogue (`material`, `style`) in the doorway at `pos`, hinged at `hinge`,
## swinging into the room that lies toward `into`.
func door(material: String, style: String, pos: Vector2, hinge: Vector2, into: Vector2) -> Node:
	var opening := { "pos": pos, "hinge": hinge, "swing_into": into, "angle": 0.0 }
	var node := DoorFactory.spawn(opening, WorldGen.door_definition(material, style), parent)
	spawned.append(node)
	return node


## A showroom sprite (`Sprites.make`) added to the set.
func sprite(painter: Script, size: Vector2, pos: Vector2, opts := {}, flags := {}) -> Node2D:
	return add(Sprites.make(painter, size, pos, opts, flags)) as Node2D


## A floor caption at `pos`.
func label(pos: Vector2, title: String, note: String) -> void:
	var node := FloorLabel.new()
	node.position = pos
	node.setup(title, note)
	add(node)
