class_name ObjectTwins
extends RefCounted
## Objects domain, the 3D twins of its bodies for the twin space (`TwinSpace`, interface 29, #194
## D3): a wall and a door lifted from their own 2D colliders to their meshes' real heights
## (`ObjectStructureMeshConfig`), a floor as a slab, a piece of furniture as one box per part of
## `PieceHeights` (a sofa's seat, arms and back; a round piece's full-footprint part a cylinder),
## in the frame of the 2D body, so a piece that turns or is shoved is followed by its transform.
## `register` adds the hooks Main wires into the space. Every one is a `StaticBody3D`: the space
## writes a twin again, with its body's transform, only when its body moves (a shoved piece, a
## swinging door), so a shut door or a resting piece costs the 3D step nothing. All sit on
## `PhysicsLayers.TWIN_WORLD`. A dent that reshapes a 2D collider does not reshape its twin: a wall
## or a piece keeps the outline it was built with.

const Piece = preload("res://scenes/objects/environment_object.gd")
const Wall = preload("res://scenes/objects/wall/wall.gd")
const Floor = preload("res://scenes/objects/floor/floor.gd")


## Add the hooks of every kind to `space` (a `TwinSpace`), and have it twin the floors.
static func register(space: TwinSpace) -> void:
	space.builders.append(Callable(ObjectTwins, &"build"))
	space.track_group(&"floors", Floor)


## The twin of `node` if it is a wall, a door, a floor or a solid piece of furniture, else null.
static func build(node: Node2D) -> Node3D:
	if node is Wall:
		return _structure(node, StaticBody3D.new(), ObjectStructureMeshConfig.wall_height)
	if node is Door:
		return _structure(node, StaticBody3D.new(), ObjectStructureMeshConfig.door_height)
	if node is Piece:
		return _piece(node as Piece)
	if node is Floor:
		return _floor(node)
	return null


## A twin `solid`ed on the world layer.
static func _world(body: CollisionObject3D) -> CollisionObject3D:
	body.collision_layer = PhysicsLayers.TWIN_WORLD
	body.collision_mask = 0
	return body


## `twin`, holding `body`'s own 2D colliders lifted to `height`.
static func _structure(body: Node2D, twin: CollisionObject3D, height: float) -> Node3D:
	TwinShapes.lift_body(body, twin, 0.0, height)
	return _world(twin)


## A solid piece's twin: a box per part (see `PieceHeights`), a static body the space moves with the
## piece (a kinematic body is always active in the 3D step, and a district holds hundreds of
## pieces).
static func _piece(piece: Piece) -> Node3D:
	if not piece.solid:
		return null
	var twin := StaticBody3D.new()
	var spec := FurnitureSpec.of(piece)
	for part: Dictionary in PieceHeights.parts(spec):
		var shape := _part(piece, spec, part)
		if shape != null:
			twin.add_child(shape)
	return _world(twin)


## One part of a piece as a collision shape in the piece's frame: its share of the footprint (in
## the painter's canonical frame, turned to the piece's facing), from the part's base to its top.
static func _part(piece: Piece, spec: FurnitureSpec, part: Dictionary) -> CollisionShape3D:
	var share: Rect2 = part["rect"]
	if part["top"] <= part["base"] or not share.has_area():
		return null
	var canon := Rect2(share.position * spec.size - spec.size * 0.5, share.size * spec.size)
	var turned := _turned(canon, spec.turns)
	if piece.shape_type == "circle" and share.is_equal_approx(PieceHeights.FULL):
		var disc := CircleShape2D.new()
		disc.radius = piece.size.x * 0.5
		return TwinShapes.lift(disc, Transform2D.IDENTITY, part["base"], part["top"])
	return TwinShapes.box(turned, Transform2D.IDENTITY, part["base"], part["top"])


## `rect` turned `turns` clockwise quarter turns about the origin: the same rectangle where the
## piece's facing puts it.
static func _turned(rect: Rect2, turns: int) -> Rect2:
	var a := rect.position.rotated(turns * PI * 0.5)
	var b := rect.end.rotated(turns * PI * 0.5)
	return Rect2(a.min(b), (a - b).abs())


## A floor's slab: its footprint from its corner, a `floor_thickness` thick slab whose top is the
## floor's drawn top (the road a kerb below the pavement).
static func _floor(node: Node2D) -> Node3D:
	var size: Vector2 = node.get("size")
	var top := ObjectStructureMeshConfig.floor_lift
	if MirrorProxy.art_of(node) == "street":
		top = -ObjectStreetMeshConfig.kerb if StreetGround.is_road(node) else 0.0
	var thick := ObjectStructureMeshConfig.floor_thickness
	var twin := StaticBody3D.new()
	var slab := Rect2(Vector2.ZERO, size)
	twin.add_child(TwinShapes.box(slab, Transform2D.IDENTITY, top - thick, top))
	return _world(twin)
