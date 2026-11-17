extends RefCounted
## The data reads the 3D lighting tests share (`tests/lighting/light_3d_*_test.gd`): the pieces of a
## world, what light each declares (`get_lights()`, read duck-typed) and the floors. Not a test.
##
## On a piece that gives light (Objects): `get_lights() -> Array`, one plain dict per light
## (`offset`, `colour`, `energy`, `radius`, `shape`, `rhythm`, `room_light`: true when it lights
## its room, so the room needs no fixture, `height`: `overhead` or `low`, `street`, `lift`).


## Every node of Godot class `type` under `root`.
static func under(root: Node, type: String) -> Array:
	return root.find_children("*", type, true, false)


# --- Pieces and their lights ----------------------------------------------------------------------


## The pieces (RigidBody2D objects with a `look`: their `art` and `art_opts`) under `root`.
static func pieces(root: Node) -> Array:
	return under(root, "RigidBody2D").filter(func(n: Node) -> bool: return "look" in n)


## The lights `piece` (a piece from `pieces`) declares: its `get_lights()`.
static func declared(piece: Node) -> Array:
	return piece.get_lights()


# --- Floors and what reaches them -----------------------------------------------------------------


## The floors (Objects' Floor nodes: a room's, the arena's or a piece of the street) under `root`.
static func floors(root: Node) -> Array:
	return under(root, "Node2D").filter(
		func(n: Node) -> bool: return "floor_material" in n and "size" in n,
	)


## The world rect `ground` covers.
static func floor_rect(ground: Node2D) -> Rect2:
	return Rect2(ground.global_position, ground.get("size"))
