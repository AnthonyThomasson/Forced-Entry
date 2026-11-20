class_name ObjectTwins
extends RefCounted
## Objects domain, the 3D twins of its bodies for the twin space (`TwinSpace`, interface 29, #194
## D3): a wall and a door lifted from their own 2D colliders to their meshes' real heights
## (`ObjectStructureMeshConfig`; a wall also carries a lintel over each doorway, from a door
## leaf's height to the wall's top), a floor as a slab, a piece of furniture as one box per part of
## `PieceHeights` (a sofa's seat, arms and back; a round piece's full-footprint part a cylinder),
## in the frame of the 2D body, so a piece that turns or is shoved is followed by its transform.
## `register` adds the hooks Main wires into the space. A free piece is a `PieceBody` that leads its
## 2D body, and so is a door: a standing one is an `AnimatableBody3D` its swing turns (`DoorBody`),
## a knocked-down one a free `DoorSlab` (D18); every other twin is a `StaticBody3D` the space writes
## again, with its body's transform, only when its body moves (a shoved piece), so a resting piece
## costs the 3D step nothing. All sit on `PhysicsLayers.TWIN_WORLD`. A dent reshapes a wall's twin
## (`WallTwin`) with its 2D collider; a piece or a door keeps the outline it was built with.

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
		var twin := WallTwin.new()
		twin.follow(node)
		_lintels(node as Wall, twin)
		return _world(twin)
	if node is Door:
		return _door(node as Door)
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


## A door's twin: the leaf as a box (its length, its thickness, a leaf's height). A standing door
## is led by a `DoorBody` (an `AnimatableBody3D` its swing turns, #194 doors3d); a knocked-down one
## by a free `DoorSlab` (D18), which a door asks the twin space for when it falls
## (`TwinSpace.retwin`).
static func _door(door: Door) -> Node3D:
	var size := door.leaf_size()
	var down := door.is_down()
	var twin: CollisionObject3D = DoorBody.new(door)
	var leaf := Rect2(-size * 0.5, size)
	var top := ObjectStructureMeshConfig.door_height
	if down:
		twin = DoorSlab.new(door)
		top -= DoorFallConfig.head_gap
		leaf = leaf.grow_individual(-DoorFallConfig.side_gap, 0.0, -DoorFallConfig.side_gap, 0.0)
	twin.add_child(TwinShapes.box(leaf, Transform2D.IDENTITY, 0.0, top))
	return twin


## Add to `twin` the lintel over each of `wall`'s doorways: a header the wall's thickness thick
## across the gap, from a door leaf's height to the wall's top, so a doorway is open only as high as
## its door (a lob that rises through one strikes it). In the wall's frame, as its segments are.
static func _lintels(wall: Wall, twin: CollisionObject3D) -> void:
	var thick := wall.wall_thickness
	for gap: Dictionary in wall.openings:
		if wall.opening_is_shared(gap):
			continue  # the wall that owns the stretch has the lintel
		var side: int = gap["side"]
		var across := float(gap["width"])
		var from := float(gap["offset"]) - across * 0.5
		var rect := Rect2()
		match side:
			Wall.Side.TOP:
				rect = Rect2(from, -thick * 0.5, across, thick)
			Wall.Side.BOTTOM:
				rect = Rect2(from, wall.size.y - thick * 0.5, across, thick)
			Wall.Side.LEFT:
				rect = Rect2(-thick * 0.5, from, thick, across)
			Wall.Side.RIGHT:
				rect = Rect2(wall.size.x - thick * 0.5, from, thick, across)
		if rect.has_area():
			twin.add_child(
				TwinShapes.box(
					rect,
					Transform2D.IDENTITY,
					ObjectStructureMeshConfig.door_height,
					ObjectStructureMeshConfig.wall_height,
				)
			)


## A solid piece's twin: a box per part (see `PieceHeights`). A piece that stands on the floor and
## is not anchored is a free `PieceBody` (a `RigidBody3D`, #194 furn3d, D13): the piece's truth,
## which the 2D body then follows. An anchored piece, and one that hangs off the floor (a mirror, a
## menu board), is a static body the space moves with the piece (a kinematic body is always active
## in the 3D step, and a district holds hundreds of pieces).
static func _piece(piece: Piece) -> Node3D:
	if not piece.solid:
		return null
	var spec := FurnitureSpec.of(piece)
	var free := not piece.anchored and PieceHeights.base_of_spec(spec) <= 0.0
	var twin: CollisionObject3D
	if free:
		twin = PieceBody.new(piece)
	else:
		twin = StaticBody3D.new()
	for part: Dictionary in PieceHeights.parts(spec):
		var shape := _part(piece, spec, part)
		if shape != null:
			twin.add_child(shape)
	if free:
		return twin
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
## floor's drawn top (the road a kerb below the pavement); a roofed floor (a room's) also a slab of
## the same thickness on the walls' top: the roof, a body of its own on the `TWIN_ROOF` layer
## (out of `TWIN_ALL`: what a ray from the sky looks for is under it), which a lob under it strikes.
static func _floor(node: Node2D) -> Node3D:
	var size: Vector2 = node.get("size")
	var top := ObjectStructureMeshConfig.floor_lift
	if MeshKinds.art_of(node) == "street":
		top = -ObjectStreetMeshConfig.kerb if StreetGround.is_road(node) else 0.0
	var thick := ObjectStructureMeshConfig.floor_thickness
	var twin := StaticBody3D.new()
	var slab := Rect2(Vector2.ZERO, size)
	twin.add_child(TwinShapes.box(slab, Transform2D.IDENTITY, top - thick, top))
	if node.get("roofed"):
		var roof := StaticBody3D.new()
		roof.collision_layer = PhysicsLayers.TWIN_ROOF
		roof.collision_mask = 0
		var walls := ObjectStructureMeshConfig.wall_height
		roof.add_child(TwinShapes.box(slab, Transform2D.IDENTITY, walls, walls + thick))
		twin.add_child(roof)
	return _world(twin)
