class_name DoorSlab
extends PieceBody
## Objects domain, a door knocked down (#194 doors3d, D18, `docs/doors.md` DR11): the free 3D body
## its leaf became when it came off its hinges, a `PieceBody` (the furniture machinery: Jolt,
## `push` at a real height, the tip test, the hull of its projected shape for a footprint, sleeping,
## the strike hand-over) shaped as the leaf, with the door's weight. It falls, tumbles and lies as
## physics decides: flat, leaning on a wall, propped on a bed. The 2D `Door` is its footprint,
## written from it each frame (`TwinSpace`): while the leaf's top is within
## `DoorFallConfig.step_over` (flat on the floor) the footprint is no collider and the slab ignores
## characters and vehicles, which walk and drive over it; higher, it is a solid footprint (a hull on
## the 2D layer, a hole in the nav bake) and a body that meets it shoves it. It stays on
## `TWIN_WORLD`: a line meets it where it lies, at its lying height, and it can be shoved like any
## light piece (`Knockback.push`).

const DoorFootprint = preload("res://scenes/objects/door/door_footprint.gd")
## What the slab collides with while it lies flat: the world (walls, pieces), the ground.
const FLAT_MASK := PhysicsLayers.TWIN_WORLD | PhysicsLayers.TWIN_GROUND

## The mask it has when it is not flat (a piece's), and whether it is flat now.
var _full_mask := 0
var _flat := false


## A slab for `door` (its `get_mass()` is the weight); the shape is added by the builder.
func _init(door: Node2D = null) -> void:
	super(door, door.call(&"get_mass") if door != null else 1.0)
	_full_mask = collision_mask


## The leaf comes off its hinges: it is thrown by the blow's `impulse` (plan space) at `height` px
## (a negative height: the leaf's centre), and wrenched over across its face toward `fall`, a unit
## vector on the plan: the way the tearing hinges lay it down (`DoorFallConfig.fall_nudge`).
func release(impulse: Vector2, height: float, fall: Vector2) -> void:
	sleeping = false
	if impulse.length_squared() > 0.0:
		push(impulse, Vector2.ZERO, height)
	push(fall * mass * DoorFallConfig.fall_nudge, Vector2.ZERO, _extent().y / RenderConfig.unit)
	twin_update(_piece)


## The footprint follows (the twin space calls this after it has written the 2D door): the hull of
## the projected leaf when it is tipped (`PieceBody`), then whether it is flat on the floor.
func twin_update(footprint: Node2D) -> void:
	super.twin_update(footprint)
	var top := _extent().y / RenderConfig.unit
	var flat := top <= DoorFallConfig.step_over
	DoorFootprint.lie_at(footprint as CollisionObject2D, top)
	if flat != _flat:
		_flat = flat
		collision_mask = FLAT_MASK if flat else _full_mask


## The footprint's collider is the hull of the tipped leaf's projection.
func _cut_footprint(footprint: Node2D, hull: PackedVector2Array) -> void:
	DoorFootprint.cut(footprint, hull)


## The leaf is upright again: its footprint is the leaf's.
func _restore_footprint(footprint: Node2D) -> void:
	DoorFootprint.restore(footprint)
