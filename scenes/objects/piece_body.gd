class_name PieceBody
extends RigidBody3D
## Objects domain, the free 3D body of a piece of furniture (D13/D14,
## `docs/adr/0014-twin-staging-and-plan-space.md`): a `RigidBody3D` in the twin space (`TwinSpace`),
## shaped from the piece's real parts (`PieceHeights`: boxes, a cylinder for a round piece), its
## mass the catalogue's `weight`. It slides, spins and, struck or shoved high enough, **tips**:
## physics (Jolt) decides, from the piece's mass, its footprint and where the push lands. It is the
## piece's truth: the 2D body (`EnvironmentObject`) is its footprint twin, written from it each
## frame by the twin space (`TwinSpace`, interface 29), so the nav holes, the interaction finding
## and everything else that still reads 2D keep working; a tipped piece's footprint is the
## projection of its current shape (`twin_update`).
##
## Pushes land at their real 3D point (`push`: a bullet at its height, a blast at its burst's, a
## character's shove at the hip): a tall thin piece struck high tips, a low heavy one slides.
## Idle it is asleep (Jolt): a resting district costs nothing. It rests on the floor slabs and
## the other twins (`PhysicsLayers.TWIN_WORLD`), is stopped by vehicles and characters (a body it
## strikes is handed its momentum, as a sliding piece always handed it to a character), and is on
## `TWIN_WORLD` itself, so a bullet, a sight line or a lob reads where it now stands.

## How near (px) a body is to a moving piece for the piece to have struck it, how many it reads at
## once, and the speed (px/s) a piece must carry to strike anything.
const STRIKE_MARGIN := 1.5
const STRIKE_HITS := 8
const STRIKE_SPEED := 5.0
## How far (px) a hull's corner may be from the one the footprint is cut to before it is cut again.
const HULL_SLACK := 0.25
## Overlaps `settle_out` reads at once, and the shortest way out (px) it bothers to move.
const SETTLE_HITS := 8
const SETTLE_MIN := 0.01
## The share of `PieceBodyConfig.drag_floor` the spin (rad/s) must pass for the drag to turn it.
const SPIN_FLOOR_SHARE := 0.1
## How far (px) over its top a piece set down on another piece starts, so it falls the last of it.
const REST_GAP := 0.4
## Points round a cylinder's rim that stand for it in a tipped piece's hull.
const RIM_POINTS := 12

## The 2D piece this is the body of (a plan handle).
var _piece: Node2D
## Whether the 2D footprint is the tipped hull now, and the 3D pose it was cut for.
var _footprint_tipped := false
var _footprint_pose := Transform3D()
## The hull the footprint was last cut to (the footprint's frame), and whether the piece counts as
## tipped (`tipped`: with hysteresis).
var _hull := PackedVector2Array()
var _tipped := false
## The velocity the piece carried at the start of the last step, before a struck body stopped it,
## and the bodies it touched then (instance ids): a body is handed momentum once a touch.
var _carried := Vector2.ZERO
var _touching: Dictionary = {}
## The physics frames it has been awake and at rest (`PieceBodyConfig.rest_speed`), without a shove.
var _rest_for := 0


## A body for `of` (an `EnvironmentObject`, or a felled door: `DoorSlab`), of `weight` (the
## catalogue's; `of`'s own `weight` when it is not given): its mass, drag, friction and gravity set.
## The shapes are added by the builder (`ObjectTwins`).
func _init(of: Node2D = null, weight := -1.0) -> void:
	_piece = of
	collision_layer = PhysicsLayers.TWIN_WORLD
	collision_mask = (
		PhysicsLayers.TWIN_WORLD
		| PhysicsLayers.TWIN_VEHICLE
		| PhysicsLayers.TWIN_CHARACTER
		| PhysicsLayers.TWIN_GROUND
	)
	if weight < 0.0:
		weight = float(of.get("weight")) if of != null else 1.0
	mass = Knockback.mass_of(weight)
	linear_damp = PieceBodyConfig.linear_damp
	angular_damp = PieceBodyConfig.angular_damp
	gravity_scale = PieceBodyConfig.gravity * RenderConfig.unit / float(
		ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	)
	var grip := PhysicsMaterial.new()
	grip.friction = PieceBodyConfig.friction
	grip.bounce = PieceBodyConfig.bounce
	physics_material_override = grip
	can_sleep = true
	continuous_cd = PhysicsImpactConfig.body_continuous_cd


## The 2D piece this is the body of.
func piece() -> Node2D:
	return _piece


## Called by the twin space as it takes the piece over: the plan handle becomes the footprint, a
## node only the twin space moves.
func take_over(footprint: Node2D) -> void:
	_centre_on_origin()
	var rest: Variant = footprint.get(&"rest") if footprint != null else null
	var lift: float = (rest as PieceRest).lift if rest is PieceRest else 0.0
	if lift > 0.0:
		# set down on another piece's top (`ObjectFactory.spawn_on`): it starts there, a hair over
		# it, and settles asleep
		global_position.y = lift * RenderConfig.unit + REST_GAP
		force_update_transform()
		sleeping = false
		return
	sleeping = true  # a district at rest costs Jolt nothing


## The centre of mass goes under the piece's origin, at the height its shapes give it (their
## volume-weighted middle): a shove at a plan point is given relative to the origin, which stands at
## the footprint's centre, so a push at the middle of a side only slides the piece, as a 2D body's
## did, whatever the shapes' lopsidedness (a chair's back) would have turned it.
func _centre_on_origin() -> void:
	var weight := 0.0
	var moment := 0.0
	for child in get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		var volume := 0.0
		if holder.shape is BoxShape3D:
			var size := (holder.shape as BoxShape3D).size
			volume = size.x * size.y * size.z
		elif holder.shape is CylinderShape3D:
			var cylinder := holder.shape as CylinderShape3D
			volume = PI * cylinder.radius * cylinder.radius * cylinder.height
		else:
			volume = 1.0
		weight += volume
		moment += volume * holder.position.y
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, moment / weight if weight > 0.0 else 0.0, 0.0)
	if _is_hollow():
		_as_solid()


## Whether the piece is built of thin parts round empty compartments (an emptied shelf, a shop's
## fridge, the cyberware shelf: `PieceHeights.hollow`), not a mass.
func _is_hollow() -> bool:
	var look: Variant = _piece.get(&"look") if _piece != null else null
	return (
		look is Object
		and (look as Object).get(&"art") in ["shelf", "shop", "clinic"]
		and PieceHeights.hollow(FurnitureSpec.of(_piece))
	)


## A hollow piece moves as the solid box of its extent: its centre of mass at the box's middle and
## its inertia the box's, as the engine would have for the piece built solid (the thin parts' own
## would have a shelf yaw, lean and tip unlike a real one: its things on the boards weigh what the
## boards do not).
func _as_solid() -> void:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for child in get_children():
		var holder := child as CollisionShape3D
		if holder == null or not holder.shape is BoxShape3D:
			continue
		var half := (holder.shape as BoxShape3D).size * 0.5
		low = low.min(holder.position - half)
		high = high.max(holder.position + half)
	if low.x > high.x:
		return
	var size := high - low
	center_of_mass = Vector3(0.0, (low.y + high.y) * 0.5, 0.0)
	inertia = (
		mass / 12.0
		* Vector3(
			size.y * size.y + size.z * size.z,
			size.x * size.x + size.z * size.z,
			size.x * size.x + size.y * size.y,
		)
	)


## Move the piece clear of what it overlaps (a wall or another piece it was placed against),
## straight out along the way that is shortest, as the 2D engine moved a rigid body that spawned
## overlapping. The physics engine's own correction is far too slow at this scale (a fraction of a
## px a step).
func settle_out() -> void:
	var query := PhysicsTestMotionParameters3D.new()
	query.from = global_transform
	query.motion = Vector3.ZERO
	query.recovery_as_collision = true
	query.max_collisions = SETTLE_HITS
	var result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(get_rid(), query, result):
		return
	var out := result.get_travel()
	out.y = 0.0
	if out.length() > SETTLE_MIN:
		global_position += out
		force_update_transform()


## Shove the piece: `impulse` (plan space, as `apply_impulse`'s) at the point `at` px from the
## piece's origin (world orientation; zero is the piece's middle), `height` px above the floor. A
## negative height is the piece's centre of mass, so a shove given no height only turns it about up;
## a height outside the piece (a blast's burst over its top) is the nearest point of it. A tall
## piece shoved above its centre leans and tips; low it slides.
func push(impulse: Vector2, at: Vector2 = Vector2.ZERO, height: float = -1.0) -> void:
	_rest_for = 0
	var lift := impulse * RenderConfig.unit
	var offset := Vector3(at.x, 0.0, at.y) * RenderConfig.unit
	var centre := global_transform.basis * center_of_mass  # from the origin, in the world's axes
	if height < 0.0:
		# through the centre of mass: a push given no point there is central, turning it about up
		# only; given a point on the floor plane, at its height
		offset = centre if at == Vector2.ZERO else Vector3(offset.x, centre.y, offset.z)
	else:
		var extent := _extent()
		if at == Vector2.ZERO:
			# a push given no point goes through the middle, at that height: aimed at an origin
			# that is not the middle (a door's foot) it would only spin a piece on the floor
			offset = Vector3(centre.x, 0.0, centre.z)
		offset.y = clampf(height * RenderConfig.unit, extent.x, extent.y) - global_position.y
	apply_impulse(Vector3(lift.x, 0.0, lift.y), offset)


## The lowest and the highest point (3D units, above the world's floor) of the piece's shapes as
## they stand now.
func _extent() -> Vector2:
	var low := INF
	var high := -INF
	for child in get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		for corner in _corners(holder.shape):
			var y := (global_transform * (holder.transform * corner)).y
			low = minf(low, y)
			high = maxf(high, y)
	return Vector2(low, high) if low <= high else Vector2(global_position.y, global_position.y)


## How high (px) the piece's centre of mass is above the floor now, in the world: the origin's
## height and the centre of mass's offset from it (the body's `center_of_mass` is an offset from its
## origin, turned with it, so a piece on its side or lifted has its centre where its pose puts it).
func centre_height() -> float:
	return (global_transform * center_of_mass).y / RenderConfig.unit


## The piece's velocity in plan space (px/s) and its turn about up (rad/s, a 2D body's sign:
## clockwise on the y-down plan is positive), as the physics server has them now, shoves given this
## frame included (the node's own `linear_velocity` is the last step's): what a pusher caps its
## shove by.
func plan_velocity() -> Vector2:
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	return PlanSpace.plan_of(state.linear_velocity if state != null else linear_velocity)


## How fast it turns about up (rad/s, a 2D body's sign), as the engine has it now.
func plan_spin() -> float:
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	return -(state.angular_velocity.y if state != null else angular_velocity.y)


## How much one unit of impulse turns the piece about up (the inverse of its moment of inertia about
## up, from its shape as the engine has it): 0 for a body not in the world yet.
func inverse_yaw_inertia() -> float:
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	return state.inverse_inertia_tensor.y.y if state != null else 0.0


## Whether the piece has tipped (D14): its up axis leans more than `PieceBodyConfig.tipped_degrees`
## from the world's, and it stays tipped until it leans less than `PieceBodyConfig.upright_degrees`.
## A tipped piece is lying on a side or leaning on something; it is no longer a thing to sit on.
## Stateful (the hysteresis): between the two leans the answer is the one it last gave, so a piece
## parked at rest (and `EnvironmentObject.is_tipped` on it) reads the state it was last asked in.
func tipped() -> bool:
	var up := global_transform.basis.y.normalized().y
	if up < cos(deg_to_rad(PieceBodyConfig.tipped_degrees)):
		_tipped = true
	elif up > cos(deg_to_rad(PieceBodyConfig.upright_degrees)):
		_tipped = false
	return _tipped


## A piece that was handed to the twin space now moves: its footprint follows (the twin space calls
## this after it has written the 2D body from this one): while tipped, one convex polygon, the hull
## of every shape's corners projected onto the floor in the 2D body's frame; upright again, the
## piece's own collider as its dents have left it.
func twin_update(footprint: Node2D) -> void:
	_hand_over()
	var now := tipped()
	if not now and not _footprint_tipped:
		return
	if now:
		if _footprint_tipped and global_transform.is_equal_approx(_footprint_pose):
			return
		_footprint_pose = global_transform
		_footprint_tipped = true
		_set_hull(footprint)
	else:
		_footprint_tipped = false
		_hull = PackedVector2Array()
		_restore_footprint(footprint)


## The engine does not sleep a body that touches a character (a kinematic body, moved every frame):
## a piece resting on one stays awake for ever, creeping on it and pushing it. A kind of piece that
## can fall on a character (`DoorSlab`) calls this each frame. One awake and at rest
## (`PieceBodyConfig.rest_speed`, `rest_spin`) for `PieceBodyConfig.rest_frames` frames, with
## no shove given it, that touches a character is **held** by it: each character it touches is told
## (`CharacterTwin.hold`) and stands still while idle (not moved, so not waking what touches it),
## and the engine then puts the piece to sleep where it lies by itself. It is not put to sleep here.
## The twin wakes it when it leaves; a character that moves into it shoves it as any piece is.
func hold_on_a_character() -> void:
	if (
		plan_velocity().length() > PieceBodyConfig.rest_speed
		or absf(plan_spin()) > PieceBodyConfig.rest_spin
		or sleeping
	):
		_rest_for = 0
		return
	_rest_for += 1
	if _rest_for < PieceBodyConfig.rest_frames:
		return
	# touching none: look again in half as long
	_rest_for = int(PieceBodyConfig.rest_frames * 0.5)
	for who: Node2D in _characters_touching():
		var twin := TwinSpace.walker_of(who)
		if twin != null and twin.has_method(&"hold"):
			twin.call(&"hold", self)


## The 2D bodies of the living characters this piece's shapes touch now, in a fixed order (by
## where they stand).
func _characters_touching() -> Array:
	var found: Array = []
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = PhysicsLayers.TWIN_CHARACTER
	query.margin = STRIKE_MARGIN
	var space := get_world_3d().direct_space_state
	for child in get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		query.shape = holder.shape
		query.transform = global_transform * holder.transform
		for hit: Dictionary in space.intersect_shape(query, STRIKE_HITS):
			var other := TwinSpace.owner_of(hit["collider"])
			if other != null and other != _piece and not found.has(other):
				found.append(other)
	found.sort_custom(_nearer_the_origin)
	return found


## Drag on the floor plane and about up only, so a shoved piece comes to rest
## (`PhysicsImpactConfig.body_linear_damp`, `body_angular_damp`), while its fall and its tipping are
## left to gravity and the contact (`linear_damp`, `angular_damp`).
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	var linear := state.linear_velocity
	if absf(linear.x) + absf(linear.z) > PieceBodyConfig.drag_floor:
		var slide := exp(-PhysicsImpactConfig.body_linear_damp * dt)
		state.linear_velocity = Vector3(linear.x * slide, linear.y, linear.z * slide)
	var angular := state.angular_velocity
	if absf(angular.y) > PieceBodyConfig.drag_floor * SPIN_FLOOR_SHARE:
		angular.y *= exp(-PhysicsImpactConfig.body_angular_damp * dt)
		state.angular_velocity = angular


## Hand the momentum of a moving piece to the bodies it strikes that are not themselves moved by the
## solver (a character: kinematic; a vehicle is a free 3D body, the engine solves the two), scaled
## down so a cascade loses energy. Jolt's contact events are not read: they are collected on worker
## threads and arrive in a different count and order run to run, so what is struck is found by a
## shape query of the piece's own shapes in the twin space, in a fixed order (by where the struck
## body stands), and a body is handed the momentum once a touch, the piece's velocity being what it
## carried before the step that met the body.
func _hand_over() -> void:
	var carried := _carried
	_carried = plan_velocity()
	if carried.length() < STRIKE_SPEED and _touching.is_empty():
		return
	var struck: Array = []
	var touching := {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = PhysicsLayers.TWIN_CHARACTER
	query.margin = STRIKE_MARGIN
	var space := get_world_3d().direct_space_state
	for child in get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		query.shape = holder.shape
		query.transform = global_transform * holder.transform
		for found: Dictionary in space.intersect_shape(query, STRIKE_HITS):
			var other := TwinSpace.owner_of(found["collider"])
			if other == null or other == _piece or not other.has_method(&"apply_impulse"):
				continue
			if TwinSpace.twin_for(other) is PieceBody or touching.has(other.get_instance_id()):
				continue
			touching[other.get_instance_id()] = true
			struck.append(other)
	struck.sort_custom(_nearer_the_origin)
	var transfer := carried * mass * PhysicsImpactConfig.transfer_scale
	for other: Node2D in struck:
		if not _touching.has(other.get_instance_id()) and transfer.length_squared() > 0.0:
			other.call(&"apply_impulse", transfer)
	_touching = touching


## Struck bodies in a fixed order: by where they stand (their instance ids differ run to run).
static func _nearer_the_origin(a: Node2D, b: Node2D) -> bool:
	if a.global_position.x != b.global_position.x:
		return a.global_position.x < b.global_position.x
	return a.global_position.y < b.global_position.y


## Replace `footprint`'s colliders by the hull of this body's shapes seen from above.
func _set_hull(footprint: Node2D) -> void:
	var world := PackedVector2Array()
	for child in get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		for corner in _corners(holder.shape):
			world.append(PlanSpace.plan_of(global_transform * (holder.transform * corner)))
	var local := PackedVector2Array()
	var back := (footprint as Node2D).global_transform.affine_inverse()
	for point in world:
		local.append(back * point)
	var hull := Geometry2D.convex_hull(local)
	if hull.size() > 1:
		hull.remove_at(hull.size() - 1)
	if hull.size() < 3 or _same_hull(hull):
		return
	_hull = hull
	_cut_footprint(footprint, hull)


## The footprint is now `hull` (its frame): a piece (`EnvironmentObject`) takes it as
## `set_tipped_footprint`; a body of another kind has its own way (`DoorSlab`).
func _cut_footprint(footprint: Node2D, hull: PackedVector2Array) -> void:
	if footprint.has_method(&"set_tipped_footprint"):
		footprint.call(&"set_tipped_footprint", hull)


## The piece is upright again: the footprint is its own (`restore_footprint`).
func _restore_footprint(footprint: Node2D) -> void:
	if footprint.has_method(&"restore_footprint"):
		footprint.call(&"restore_footprint")


## Whether `hull` is the one the footprint is cut to already (a piece that only slides or turns
## about up keeps its hull in its own frame): the collider, and the nav hole cut from it, are then
## left as they are.
func _same_hull(hull: PackedVector2Array) -> bool:
	if hull.size() != _hull.size():
		return false
	for i in hull.size():
		if hull[i].distance_to(_hull[i]) > HULL_SLACK:
			return false
	return true


## The corner points of `shape` in its own frame (a cylinder as a ring of points).
static func _corners(shape: Shape3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if shape is BoxShape3D:
		var half := (shape as BoxShape3D).size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					out.append(Vector3(half.x * sx, half.y * sy, half.z * sz))
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		for i in RIM_POINTS:
			var turn := TAU * i / float(RIM_POINTS)
			var rim := Vector3(cos(turn), 0.0, sin(turn)) * cylinder.radius
			out.append(rim + Vector3.UP * cylinder.height * 0.5)
			out.append(rim - Vector3.UP * cylinder.height * 0.5)
	elif shape is ConvexPolygonShape3D:
		out = (shape as ConvexPolygonShape3D).points
	return out
