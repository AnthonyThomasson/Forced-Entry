class_name WallTwin
extends StaticBody3D
## Objects domain, the 3D body of a wall (`ObjectTwins`, interface 29, #194 walls3d): its truth for
## the 3D reads (the dent state itself stays in the 2D `Wall` until the 2D space is deleted, where
## the cut moves here) (a bullet's ray, a fragment, a lob, a sight line). A static body, built once
## from the wall's segments, a box (or the convex pieces of a dented outline) from the floor to the
## wall's top for each segment the wall owns, and a lintel over each doorway it owns. When a hit
## dents a segment (`Wall.segment_rebuilt`) the segment's shapes are cut again from the same dents
## as the 2D colliders, so the 3D wall and its 2D footprint keep one outline. The 2D colliders of
## the wall are the footprint the not-yet-3D readers (the avoid maps, the 2D bodies that collide
## with it) use until the 2D space is gone; the nav bake reads this body (`NavTwins`).

## The wall this is the body of.
var _wall: Node2D
## Segment index -> the `CollisionShape3D`s that stand for it now.
var _segment_shapes := {}


## Give this body the shapes of `wall`'s segments, and keep them following its dents.
func follow(wall: Node2D) -> void:
	_wall = wall
	var shapes: Dictionary = wall.call(&"segment_shapes")
	for index: int in shapes:
		_put(index, shapes[index])
	wall.connect(&"segment_rebuilt", _on_rebuilt)


## The shapes of segment `index` as the 2D wall has them now are lifted to 3D again.
func _on_rebuilt(index: int) -> void:
	if not is_instance_valid(_wall):
		return
	for old: Node in _segment_shapes.get(index, []):
		if is_instance_valid(old):
			remove_child(old)
			old.free()
	_put(index, (_wall.call(&"segment_shapes") as Dictionary).get(index, []))


## Lift each 2D collider of `holders` (a segment's) to the wall's height, in the wall's frame.
func _put(index: int, holders: Array) -> void:
	var made: Array[CollisionShape3D] = []
	for holder: CollisionShape2D in holders:
		if holder.disabled or holder.shape == null:
			continue
		var lifted := TwinShapes.lift(
			holder.shape, holder.transform, 0.0, ObjectStructureMeshConfig.wall_height
		)
		if lifted != null:
			add_child(lifted)
			made.append(lifted)
	_segment_shapes[index] = made
