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
## What a leaf knocked down ajar is sent out with (`release`): the way out (plan), the wall line's
## coordinate along it, the physics frames it has been carried, and what it is given when let go:
## the shoves it is given (each `[impulse, height]`: the blow's, then any that arrive during the
## carry) and the way it falls, and the physics frames it has left to shove a character it falls on.
var _out := Vector2.ZERO
var _line := 0.0
var _carried_for := 0
var _throws: Array = []
var _fall := Vector2.ZERO
var _bowl_left := 0


## A slab for `door` (its `get_mass()` is the weight); the shape is added by the builder.
func _init(door: Node2D = null) -> void:
	super(door, door.call(&"get_mass") if door != null else 1.0)
	_full_mask = collision_mask
	set_physics_process(false)
	sleeping_state_changed.connect(_on_sleeping_changed)


## While a leaf is carried: it is let go once it stands clear of its frame, has met a piece (it
## then falls on it, as on a bed: D18) or has been carried for `DoorFallConfig.carry_frames`.
## Once let go, while it falls: it shoves the characters it touches (`_bowl`).
func _physics_process(delta: float) -> void:
	if _out == Vector2.ZERO:
		_bowl(delta)
		return
	_carried_for += 1
	_shove_characters(_out, delta)
	var way := PlanSpace.lift(_out * DoorFallConfig.carry_speed)
	if linear_velocity.dot(way.normalized()) < DoorFallConfig.carry_speed * RenderConfig.unit * 0.5:
		linear_velocity = way  # stopped by a character, who has been shoved: on it goes
	if (
		_rear() >= _line + DoorFallConfig.frame_out
		or _carried_for >= DoorFallConfig.carry_frames
		or _met_a_piece()
	):
		_let_go()


## The leaf comes off its hinges: it is thrown by the blow's `impulse` (plan space) at `height` px
## (a negative height: the leaf's centre), and wrenched over toward `fall`, a unit vector on the
## plan: the way the tearing hinges lay it down (`DoorFallConfig.fall_nudge`). A leaf felled ajar
## (`out` is the unit plan vector away from the blow, zero for a shut leaf) first stands across its
## doorway's wall line, where its ends would catch a jamb whichever way it tipped: it is sent out
## along `out` (`DoorFallConfig.carry_speed`; the physics carries it edge-on through the gap and
## meets what is in its way: a piece stops it and lets it go, a character is shoved on, and it is
## sent out again when they have stopped it) until its rearmost point stands
## `DoorFallConfig.frame_out` past the wall line `line` (its hinge's coordinate along `out`), and
## then it is let go: the blow's throw, the wrench and the turn toward `fall` are given.
func release(
	impulse: Vector2, height: float, fall: Vector2, out := Vector2.ZERO, line := 0.0
) -> void:
	sleeping = false
	_throws = [[impulse, height]]
	_fall = fall
	if out == Vector2.ZERO:
		_let_go()
		return
	_out = out
	_line = line
	_carried_for = 0
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	linear_velocity = PlanSpace.lift(out * DoorFallConfig.carry_speed)
	set_physics_process(true)
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
		if not flat:
			set_physics_process(true)  # stood up on something: watched for a character under it


## A shove while the leaf is carried out of its frame (a blast's, that follows the blow that
## felled it) is kept for when it is let go: it does not turn or stop the carry.
func push(impulse: Vector2, at: Vector2 = Vector2.ZERO, height: float = -1.0) -> void:
	if _out == Vector2.ZERO:
		super(impulse, at, height)
	else:
		_throws.append([impulse, height])


## A leaf being carried out of its frame hands its momentum to no one once, as a sliding piece does:
## it shoves the characters it meets every frame instead (`_shove_characters`).
func _hand_over() -> void:
	if _out == Vector2.ZERO:
		super()


## The footprint is the hull of the tipped leaf's projection.
func _cut_footprint(door: Node2D, outline: PackedVector2Array) -> void:
	door.get(&"footprint").hull = outline


## The leaf is upright again: its footprint is the leaf's.
func _restore_footprint(door: Node2D) -> void:
	door.get(&"footprint").hull = PackedVector2Array()


## The carry ends: the leaf is free to turn, stops where it is, and is thrown by the blow (and by
## any shove that came during the carry, each at its own height), wrenched and turned toward its
## fall (`DoorFallConfig.lean_spin`); then, while it falls, it shoves a character in its way.
func _let_go() -> void:
	axis_lock_angular_x = false
	axis_lock_angular_z = false
	if _out != Vector2.ZERO:
		linear_velocity = Vector3.ZERO
		var toward := PlanSpace.lift(_fall).normalized()
		angular_velocity = Vector3.UP.cross(toward).normalized() * DoorFallConfig.lean_spin
	var carried_out := _out
	_out = Vector2.ZERO
	for throw: Array in _throws:
		var impulse: Vector2 = throw[0]
		var back := impulse.dot(carried_out)
		if back < 0.0:
			impulse -= carried_out * back  # no shove sends the leaf back into the frame it left
		if impulse.length_squared() > 0.0:
			push(impulse, Vector2.ZERO, throw[1])
	_throws = []
	push(_fall * mass * DoorFallConfig.fall_nudge, Vector2.ZERO, _extent().y / RenderConfig.unit)
	_bowl_left = DoorFallConfig.bowl_frames
	set_physics_process(true)
	twin_update(_piece)


## A leaf that wakes is watched again: one at rest on a character is put to sleep there.
func _on_sleeping_changed() -> void:
	if not sleeping:
		set_physics_process(true)


## A leaf is no wall to a character: they are kinematic, which a leaf can neither push nor tip
## over, so one carried out of its frame against a character stood in the doorway held by them, and
## one let go flush against one stood upright on them for ever, held awake, pushing them. So while
## it is carried it shoves what it meets along its way out (`_shove_characters`), and while it
## falls (`DoorFallConfig.bowl_frames` after it is let go, or until it lies flat or at rest) it
## shoves each character it touches along its face's normal, away from it
## (`DoorFallConfig.bowl_accel`): they are bowled out of its way and it goes down. One a wall holds
## in place holds it, and the leaf then rests on them (`PieceBody`).
func _bowl(delta: float) -> void:
	if _flat or sleeping:
		set_physics_process(false)
		return
	# awake and standing on its own: the twin space tells no one a body that does not move, so a
	# leaf at rest on a character is watched here, and held by it (the engine then sleeps it)
	hold_on_a_character()
	_bowl_left -= 1
	if _bowl_left <= 0:
		return
	_keep_turning()
	_shove_characters(_face_normal(), delta)


## Shove every living character the leaf touches along `way` (a unit plan vector; away from the
## leaf's middle across it when they stand on its other side) for one physics step.
func _shove_characters(way: Vector2, delta: float) -> void:
	var middle := PlanSpace.plan_of(global_transform * center_of_mass)
	for other: Node2D in _characters_touching():
		var side := 1.0 if way.dot(other.global_position - middle) >= 0.0 else -1.0
		var impulse := way * side * float(other.call(&"get_mass")) * DoorFallConfig.bowl_accel
		other.call(&"apply_impulse", impulse * delta)


## A leaf let go that is held up (by a character it leans on) has its turn taken from it and would
## rock back upright: until it has passed `DoorFallConfig.commit_degrees` it is turned on toward its
## fall at `DoorFallConfig.lean_spin` again.
func _keep_turning() -> void:
	if global_transform.basis.y.normalized().y < cos(deg_to_rad(DoorFallConfig.commit_degrees)):
		return
	var toward := PlanSpace.lift(_fall).normalized()
	var turn := Vector3.UP.cross(toward).normalized()
	if angular_velocity.dot(turn) < DoorFallConfig.lean_spin:
		angular_velocity += turn * (DoorFallConfig.lean_spin - angular_velocity.dot(turn))


## The unit plan vector across the leaf's face as it stands now (its thin axis, flattened on the
## plan): the way a character it falls on is shoved. The way it falls when it lies too flat to say.
func _face_normal() -> Vector2:
	for child in get_children():
		var holder := child as CollisionShape3D
		var box := holder.shape as BoxShape3D if holder != null else null
		if box == null:
			continue
		var turned := global_transform.basis * holder.transform.basis
		var plan := PlanSpace.plan_of(turned.x if box.size.x < box.size.z else turned.z)
		return plan.normalized() if plan.length() > 0.05 else _fall
	return _fall


## How far (px) along the carry the leaf's rearmost point stands now.
func _rear() -> float:
	var rear := INF
	for child in get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		for corner in _corners(holder.shape):
			var at := PlanSpace.plan_of(global_transform * (holder.transform * corner))
			rear = minf(rear, at.dot(_out))
	return rear


## Whether the leaf touches a piece of furniture (a free body of the twin space, not a wall).
func _met_a_piece() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = PhysicsLayers.TWIN_WORLD
	query.margin = STRIKE_MARGIN
	var space := get_world_3d().direct_space_state
	for child in get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		query.shape = holder.shape
		query.transform = global_transform * holder.transform
		for found: Dictionary in space.intersect_shape(query, STRIKE_HITS):
			if found["collider"] is PieceBody and found["collider"] != self:
				return true
	return false
