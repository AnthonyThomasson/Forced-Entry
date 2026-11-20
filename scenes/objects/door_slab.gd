class_name DoorSlab
extends PieceBody
## Objects domain, a door knocked down (#194 doors3d, D18, `docs/doors.md` DR11): the free 3D body
## its leaf became when it came off its hinges, a `PieceBody` (the furniture machinery: Jolt,
## `push` at a real height, the tip test, the hull of its projected shape for a footprint, sleeping,
## the strike hand-over) shaped as the leaf, with the door's weight. It falls, tumbles and lies as
## physics decides: flat, leaning on a wall, propped on a bed. The 2D `Door` is its footprint,
## written from it each frame (`TwinSpace`): while the leaf's top is within
## `DoorFallConfig.step_over` (flat on the floor) the footprint is no obstacle and the slab is on
## `TWIN_WALKOVER`: characters and vehicles walk and drive over it (no shove: their masks leave the
## layer out), while a line, a lob or what falls on it meets it where it lies, at its lying height;
## higher, it is a solid footprint (a hull, a hole in the nav bake) on `TWIN_WORLD`, which a body
## that meets it shoves. It can be shoved like any light piece (`Knockback.push`).

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
	(footprint.get(&"footprint") as RefCounted).call(&"lie_at", top)
	if flat != _flat:
		_flat = flat
		collision_mask = FLAT_MASK if flat else _full_mask
		collision_layer = PhysicsLayers.TWIN_WALKOVER if flat else PhysicsLayers.TWIN_WORLD


## The footprint is the hull of the tipped leaf's projection.
func _cut_footprint(door: Node2D, outline: PackedVector2Array) -> void:
	door.get(&"footprint").hull = outline


## The leaf is upright again: its footprint is the leaf's.
func _restore_footprint(door: Node2D) -> void:
	door.get(&"footprint").hull = PackedVector2Array()
