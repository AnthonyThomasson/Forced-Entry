class_name Ragdoll extends RefCounted
## A generic 3D ragdoll (Physics domain): point masses joined by bones and joint limits, stepped as
## position-based dynamics. Space is the owner's local floor plane (x, y in px) plus z = height
## above the floor: gravity pulls toward z = 0 and the floor holds each point at its radius. Each
## move is swept in the twin 3D space (`TwinSpace`, interface 29) as a sphere at the point's real
## height (`height_scale`: the owner's z unit in real px): it is stopped by a wall or a piece of
## furniture or a vehicle only where that thing really stands at that height, slides along it, and
## comes to rest on a top that faces up (a body slumps over a sofa's back and lies on a desk). It
## knows nothing of what the body is: the owner adds points, bones, frames (an orientation read off
## three points) and limits (swing cones and anatomical hinges, set in a frame), seeds velocities,
## then calls step() each physics frame until it sleeps. Tuning: PhysicsRagdollConfig.

enum {
	SWING,
	HINGE,
}

## Fraction of a joint limit's violation corrected per constraint pass (softens jitter).
const LIMIT_STIFFNESS := 0.6
## Most a limit turns a bone per pass (rad): a far-out bone is brought back over several passes, so
## the correction never becomes a burst of speed.
const LIMIT_MAX_TURN := 0.3
## How far (px) a cast sphere's underside floats over the floor: over a floor slab's 0.1 px, so the
## sweeps never catch a slab's seam.
const FLOOR_GAP := 0.5
## A surface whose normal's height share is over this faces up: a point resting on it is held.
const FACES_UP := 0.7
## How far (px) a point's sphere is held off a surface it was pushed out of, and how many
## surfaces one point is pushed off in a step (a corner has two).
const SKIN := 0.05
const PUSH_PASSES := 3

## How many steps (one body, one physics frame, asleep ones not counted) ragdolls have run since
## the process began: a frame's rise is the bodies still falling (a perf probe's read).
static var steps_total := 0

## How many real px one unit of a point's z is (the owner's drawing may be taller than the body is):
## the casts read a point at `z * height_scale` over the floor.
var height_scale := 1.0
## True once the body has come to rest (or timed out); step() then does nothing.
var asleep := false
## Colliders (3D) the sweeps ignore (e.g. the owner's own twin).
var exclude: Array[RID] = []
## Point positions (local x/y px, z = height px).
var _pos := PackedVector3Array()
## Positions at the start of the sub-step.
var _prev := PackedVector3Array()
## Point velocities (px/s).
var _vel := PackedVector3Array()
## Point collision radii (px).
var _radius := PackedFloat32Array()
## Point inverse masses (heavier points move less).
var _inv_mass := PackedFloat32Array()
## [a, b, rest length, stiffness].
var _bones: Array = []
## [origin, up, right, sign]: forward = (up × right) · sign.
var _frames: Array = []
## Swing / hinge dicts (see add_swing / add_hinge).
var _limits: Array = []
## Retained per-substep speed arrays and wall-query storage.
var _scratch := StepScratch.new()
## Seconds every point has stayed under the sleep speed.
var _still := 0.0
## Seconds simulated.
var _time := 0.0


# --- Building ----------------------------------------------------------------------------


## Add a point at `at` (local px, z = height) with a collision `radius` and `mass`; returns its
## index.
func add_point(at: Vector3, radius: float, mass: float = 1.0) -> int:
	_pos.append(at)
	_prev.append(at)
	_vel.append(Vector3.ZERO)
	_scratch.fall.append(0.0)
	_scratch.free.append(0.0)
	_scratch.held.append(0)
	_scratch.was_held.append(0)
	_radius.append(radius)
	_inv_mass.append(1.0 / maxf(mass, 0.001))
	return _pos.size() - 1


## Join points `a` and `b` at their current distance. `stiffness` (0–1) is the share of any stretch
## corrected per pass.
func add_bone(a: int, b: int, stiffness: float = 1.0) -> void:
	_bones.append([a, b, _pos[a].distance_to(_pos[b]), stiffness])


## Bind `indices` into one rigid cluster (a bone between every pair).
func add_rigid(indices: Array) -> void:
	for i in indices.size():
		for j in range(i + 1, indices.size()):
			add_bone(indices[i], indices[j])


## An orientation read off three points each step: y = `origin` → `up`, x = toward `right` (made
## square to y), z = forward, signed so it points along `forward_hint` now. Returns its id.
func add_frame(origin: int, up: int, right: int, forward_hint: Vector3) -> int:
	_frames.append([origin, up, right, 1.0])
	var f := _frames.size() - 1
	if frame_basis(f).z.dot(forward_hint) < 0.0:
		_frames[f][3] = -1.0
	return f


## Keep `child` within a cone around `rest` from `joint` — `rest` a unit direction along the frame's
## y axis (up or down) — at most `limits` `right` / `left` / `front` / `back` radians off it toward
## the frame's +x / −x / +z / −z, blended by direction in between.
func add_swing(frame: int, joint: int, child: int, rest: Vector3, limits: Dictionary) -> void:
	_limits.append({
		"kind": SWING, "frame": frame, "joint": joint, "child": child, "rest": rest.normalized(),
		"right": maxf(limits["right"], 0.01), "left": maxf(limits["left"], 0.01),
		"front": maxf(limits["front"], 0.01), "back": maxf(limits["back"], 0.01),
	})


## An anatomical hinge at `joint` between the parent bone (`parent` → `joint`) and the child bone
## (`joint` → `child`), shaped by `limits`. Its bend side is the frame-space `limits.bend` (square
## to the frame-space `limits.rest`) carried by the shortest turn taking `rest` onto the live parent
## bone, so the hinge keeps a sensible plane in any limb pose. The child's bend off straight is held
## to [`min_angle`, `max_angle`] toward that side, and its twist out of the plane to ±`slack`
## (radians).
func add_hinge(frame: int, parent: int, joint: int, child: int, limits: HingeLimits) -> void:
	_limits.append({
		"kind": HINGE, "frame": frame, "parent": parent, "joint": joint, "child": child,
		"rest": limits.rest.normalized(), "bend": limits.bend.normalized(),
		"min": limits.min_angle, "max": limits.max_angle, "slack": limits.slack,
	})


## Add `v` (px/s) to point `i`'s velocity.
func push(i: int, v: Vector3) -> void:
	_vel[i] += v


# --- Reading -----------------------------------------------------------------------------


## Point `i`'s position (local x/y px, z = height px).
func point(i: int) -> Vector3:
	return _pos[i]


## How many points the body has.
func point_count() -> int:
	return _pos.size()


## Frame `f`'s live orientation: x right, y up, z forward (orthonormal).
func frame_basis(f: int) -> Basis:
	var fr: Array = _frames[f]
	var o := _pos[fr[0]]
	var up := (_pos[fr[1]] - o).normalized()
	var right := _pos[fr[2]] - o
	right = (right - up * right.dot(up)).normalized()
	return Basis(right, up, up.cross(right) * float(fr[3]))


# --- Stepping ----------------------------------------------------------------------------


## Wake a body that had gone to sleep and start its sleep clocks afresh, so a push is simulated and
## the body does not go straight back to sleep through `PhysicsRagdollConfig.max_time` (an explosion
## throws a fallen body).
func wake() -> void:
	asleep = false
	_time = 0.0
	_still = 0.0


## Advance the body by `delta`. `space` (the twin 3D space; null: nothing to strike) + `origin`
## (the owner's world position, plan) place the local points in the world for the sweeps.
func step(delta: float, space: PhysicsDirectSpaceState3D, origin: Vector2) -> void:
	if asleep or delta <= 0.0:
		return
	steps_total += 1
	if not _scratch.primed:
		_scratch.primed = true
		_pull_out_of_walls(space, origin)
	var n := maxi(1, PhysicsRagdollConfig.substeps)
	for _s in n:
		_substep(delta / n, space, origin)
	_time += delta
	var fastest := 0.0
	for v in _vel:
		fastest = maxf(fastest, v.length())
	_still = _still + delta if fastest < PhysicsRagdollConfig.sleep_speed else 0.0
	if _still >= PhysicsRagdollConfig.sleep_time or _time >= PhysicsRagdollConfig.max_time:
		asleep = true
		_vel.fill(Vector3.ZERO)


## One sub-step: predict, project the constraints and floor, sweep the solids, then derive
## velocities and apply floor bounce/friction and joint friction.
func _substep(h: float, space: PhysicsDirectSpaceState3D, origin: Vector2) -> void:
	_predict(h, _scratch.fall, _scratch.free)
	_solve_constraints()
	_sweep_solids(space, origin)
	_derive_velocities(h, _scratch.fall, _scratch.free)
	_joint_friction(h)


## Move every point on under gravity and air drag over `h` s, noting its vertical speed in `fall`
## and its speed in `free`.
func _predict(h: float, fall: PackedFloat32Array, free: PackedFloat32Array) -> void:
	var gravity := Vector3(0.0, 0.0, -PhysicsRagdollConfig.gravity)
	var drag := exp(-PhysicsRagdollConfig.air_drag * h)
	for i in _pos.size():
		_vel[i] = (_vel[i] + gravity * h) * drag
		_prev[i] = _pos[i]
		_pos[i] += _vel[i] * h
		fall[i] = _vel[i].z
		free[i] = _vel[i].length()


## `PhysicsRagdollConfig.iterations` passes of the bones, the limits and the floor.
func _solve_constraints() -> void:
	for _k in maxi(1, PhysicsRagdollConfig.iterations):
		for bone in _bones:
			_solve_bone(bone)
		for limit in _limits:
			if limit["kind"] == SWING:
				_solve_swing(limit)
			else:
				_solve_hinge(limit)
		_solve_floor()


## Each point's velocity from its move over `h` s, held to what it came in with (`free`), with the
## floor's bounce (from its vertical speed before, `fall`) and friction.
func _derive_velocities(h: float, fall: PackedFloat32Array, free: PackedFloat32Array) -> void:
	var friction := PhysicsRagdollConfig.floor_friction * h
	var gain := PhysicsRagdollConfig.max_push * h
	for i in _pos.size():
		# The constraints may pass momentum along the body but never pump it up: a point leaves them
		# no faster than it came in, plus a push no harder than `PhysicsRagdollConfig.max_push`.
		var v := ((_pos[i] - _prev[i]) / h).limit_length(
			minf(free[i] + gain, PhysicsRagdollConfig.max_speed),
		)
		var on_floor := _pos[i].z <= _radius[i] + 0.01
		if on_floor or _scratch.held[i] != 0:
			var came_down := (
				_prev[i].z > _radius[i] + 0.01 if on_floor else _scratch.was_held[i] == 0
			)
			if came_down and fall[i] < 0.0:
				v.z = -fall[i] * PhysicsRagdollConfig.floor_bounce
			var flat := Vector2(v.x, v.y).move_toward(Vector2.ZERO, friction)
			v.x = flat.x
			v.y = flat.y
		_vel[i] = v


## Pull each limited child's velocity toward its joint's over `h` s, so limbs swing heavy.
func _joint_friction(h: float) -> void:
	var hold := 1.0 - exp(-PhysicsRagdollConfig.joint_friction * h)
	for limit in _limits:
		var j: int = limit["joint"]
		var c: int = limit["child"]
		_vel[c] = _vel[c].lerp(_vel[j], hold)


## Restore a bone's length, split by inverse mass.
func _solve_bone(bone: Array) -> void:
	var a: int = bone[0]
	var b: int = bone[1]
	var d := _pos[b] - _pos[a]
	var length := d.length()
	var total := _inv_mass[a] + _inv_mass[b]
	if length < 0.0001 or total <= 0.0:
		return
	var fix := d * ((length - float(bone[2])) / length * float(bone[3]) / total)
	_pos[a] += fix * _inv_mass[a]
	_pos[b] -= fix * _inv_mass[b]


## Hold a swing limit's child inside its cone.
func _solve_swing(l: Dictionary) -> void:
	var j: int = l["joint"]
	var c: int = l["child"]
	var d := _pos[c] - _pos[j]
	var length := d.length()
	if length < 0.0001:
		return
	var b := frame_basis(l["frame"])
	var w := d / length
	var fixed := _swing_limit(l, Vector3(w.dot(b.x), w.dot(b.y), w.dot(b.z)))
	if fixed == Vector3.ZERO:
		return
	_turn_child(j, c, w, b * fixed, length)


## Where a swing limit `l` holds a child lying along `local` (unit, in the frame's space): the
## nearest direction on its cone's rim, or ZERO when it lies inside the cone.
func _swing_limit(l: Dictionary, local: Vector3) -> Vector3:
	var rest: Vector3 = l["rest"]
	var cos_t := clampf(local.dot(rest), -1.0, 1.0)
	var swing := local - rest * cos_t
	if swing.length_squared() < 0.00000001:
		if cos_t > 0.0:
			return Vector3.ZERO  # On the rest axis: inside any cone.
		swing = Vector3(0.0, 0.0, 1.0)  # Straight opposite: bring it round the front.
	swing = swing.normalized()
	var max_t := _cone_reach(l, swing)
	if acos(cos_t) <= max_t:
		return Vector3.ZERO
	return rest * cos(max_t) + swing * sin(max_t)


## A swing limit `l`'s reach (radians) toward unit `swing`, blended between its reach toward the
## frame axes either side.
func _cone_reach(l: Dictionary, swing: Vector3) -> float:
	var lx: float = l["right"] if swing.x > 0.0 else l["left"]
	var lz: float = l["front"] if swing.z > 0.0 else l["back"]
	return lerpf(lz, lx, atan2(absf(swing.x), absf(swing.z)) / (PI * 0.5))


## Hold a hinge's child bone to its bend range and plane.
func _solve_hinge(l: Dictionary) -> void:
	var p: int = l["parent"]
	var j: int = l["joint"]
	var c: int = l["child"]
	var upper := _pos[j] - _pos[p]
	var d := _pos[c] - _pos[j]
	var length := d.length()
	if upper.length_squared() < 0.00000001 or length < 0.0001:
		return
	var u := upper.normalized()
	var n := _hinge_bend(l, u)
	if n == Vector3.ZERO:
		return
	var w := d / length
	var fixed := _hinge_fix(l, u, n, w)
	if fixed == Vector3.ZERO:
		return
	_turn_child(j, c, w, fixed, length)


## Hinge `l`'s bend side carried along with the parent bone `u` (unit; a half turn flips it
## outright), square to it and unit, or ZERO where it lies along the bone.
func _hinge_bend(l: Dictionary, u: Vector3) -> Vector3:
	var b := frame_basis(l["frame"])
	var rest: Vector3 = b * (l["rest"] as Vector3)
	var bend: Vector3 = b * (l["bend"] as Vector3)
	var n: Vector3 = -bend if rest.dot(u) < -0.999 else Quaternion(rest, u) * bend
	n = n - u * n.dot(u)
	if n.length_squared() < 0.00000001:
		return Vector3.ZERO
	return n.normalized()


## Where hinge `l` holds a child lying along `w` off parent bone `u`, bending toward `n` (all unit):
## its bend clamped to [min, max] and its twist out of the plane to ±slack, or ZERO when both are
## within them.
func _hinge_fix(l: Dictionary, u: Vector3, n: Vector3, w: Vector3) -> Vector3:
	var side := u.cross(n)
	var cos_t := clampf(w.dot(u), -1.0, 1.0)
	var theta := acos(cos_t)
	var perp := w - u * cos_t
	var phi := atan2(perp.dot(side), perp.dot(n)) if perp.length_squared() > 0.00000001 else 0.0
	var theta_ok := clampf(theta, l["min"], l["max"])
	var phi_ok := clampf(phi, -float(l["slack"]), float(l["slack"]))
	if is_equal_approx(theta_ok, theta) and is_equal_approx(phi_ok, phi):
		return Vector3.ZERO
	return u * cos(theta_ok) + (n * cos(phi_ok) + side * sin(phi_ok)) * sin(theta_ok)


## Move `child` (and `joint`, by inverse mass) part way from lying along `from` toward lying along
## `dir` at `length` from the joint (both unit), turning it at most LIMIT_MAX_TURN.
func _turn_child(j: int, c: int, from: Vector3, dir: Vector3, length: float) -> void:
	var total := _inv_mass[j] + _inv_mass[c]
	if total <= 0.0:
		return
	var turn := from.angle_to(dir)
	if turn > LIMIT_MAX_TURN:
		dir = from.slerp(dir, LIMIT_MAX_TURN / turn)
	var fix := (_pos[j] + dir * length - _pos[c]) * LIMIT_STIFFNESS
	_pos[c] += fix * (_inv_mass[c] / total)
	_pos[j] -= fix * (_inv_mass[j] / total)


## No point sinks below the floor.
func _solve_floor() -> void:
	for i in _pos.size():
		if _pos[i].z < _radius[i]:
			var p := _pos[i]
			p.z = _radius[i]
			_pos[i] = p


## Sweep each point's move this sub-step in the twin space: stop where it first touches a wall, a
## piece or a vehicle at its real height, then slide the rest along the surface. A point that ends
## resting on a surface facing up is held by it (`_scratch.held`).
func _sweep_solids(space: PhysicsDirectSpaceState3D, origin: Vector2) -> void:
	_scratch.was_held = _scratch.held.duplicate()
	_scratch.held.fill(0)
	if space == null or (_scratch.sweep_gate and _solids_clear(space, origin)):
		return
	for i in _pos.size():
		_scratch.point_sweeps += 1
		var reached := _sweep(space, origin, i, _prev[i], _pos[i])
		if reached != _pos[i]:
			_pos[i] = reached


## Whether nothing can touch any point's sphere anywhere from its substep start to its constrained
## end. One reused box covers all those starts, ends and radii; any overlap keeps the exact
## per-point sweeps. The first-step origin-to-point pull-out is deliberately not gated by this
## bound.
func _solids_clear(space: PhysicsDirectSpaceState3D, origin: Vector2) -> bool:
	if _pos.is_empty():
		return true
	var box := AABB(_cast_point(_prev[0], origin, 0), Vector3.ZERO)
	for i in _pos.size():
		var spread := Vector3.ONE * _radius[i] * RenderConfig.unit
		for p: Vector3 in [_prev[i], _pos[i]]:
			var at := _cast_point(p, origin, i)
			box = box.expand(at - spread).expand(at + spread)
	box = box.grow(SKIN + 0.01)
	var params := _scratch.query(_radius[0], exclude)
	_scratch.bounds.size = box.size
	params.shape = _scratch.bounds
	params.transform = Transform3D(Basis(), box.get_center())
	params.motion = Vector3.ZERO
	_scratch.broadphase_queries += 1
	return space.intersect_shape(params, 1).is_empty()


## Before the first step: draw any point that starts inside a solid back toward the owner's own
## free column (the origin, at the point's own height).
func _pull_out_of_walls(space: PhysicsDirectSpaceState3D, origin: Vector2) -> void:
	for i in _pos.size():
		if space != null:
			_pos[i] = _sweep(space, origin, i, Vector3(0.0, 0.0, _pos[i].z), _pos[i])
		_prev[i] = _pos[i]


## The 3D point of the cast sphere for point `i` of the solver at `p` (local x, y, height): its
## plan point lifted to its real height, no lower than a sphere resting a hair over the floor (a
## floor slab stands 0.1 px up).
func _cast_point(p: Vector3, origin: Vector2, i: int) -> Vector3:
	var low := _radius[i] + FLOOR_GAP
	return PlanSpace.lift(origin + Vector2(p.x, p.y), maxf(p.z * height_scale, low))


## A cast-space vector (plan x, real height, plan y) as a solver one (x, y, z).
func _solver_vector(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, v.y / maxf(height_scale, 0.0001)) / RenderConfig.unit


## Where a sphere for point `i` moving from `from` to `to` (solver space) comes to rest: at its
## first contact with a solid, slid along the surface for the rest of the move, then moved clear of
## anything it is left inside (`_push_out`). A surface facing up it ends on holds the point
## (`_scratch.held`).
func _sweep(space: PhysicsDirectSpaceState3D, origin: Vector2, i: int, from: Vector3,
		to: Vector3) -> Vector3:
	if (to - from).length_squared() < 0.0001:
		return to
	var start := _cast_point(from, origin, i)
	var move := _cast_point(to, origin, i) - start
	var params := _scratch.query(_radius[i], exclude)
	params.transform = Transform3D(Basis(), start)
	params.motion = move
	var res := space.cast_motion(params)
	if res.is_empty() or res[0] >= 1.0:
		return _push_out(space, origin, i, to)
	var normal := _contact_normal(space, i, start + move * res[1], -move.normalized())
	if normal.y > FACES_UP:
		_scratch.held[i] = 1
	var left := move * (1.0 - res[0])
	var slide := left.slide(normal) if left.dot(normal) < 0.0 else left
	var share := _clear_share(space, i, start + move * res[0], slide)
	var rest := from + (to - from) * res[0] + _solver_vector(slide) * share
	return _push_out(space, origin, i, rest)


## How much of `motion` (cast space) point `i`'s sphere can make from cast point `at` before it
## meets a solid.
func _clear_share(space: PhysicsDirectSpaceState3D, i: int, at: Vector3, motion: Vector3) -> float:
	var params := _scratch.query(_radius[i], exclude)
	params.transform = Transform3D(Basis(), at)
	params.motion = motion
	var res := space.cast_motion(params)
	return res[0] if not res.is_empty() else 1.0


## The normal of the surface point `i`'s sphere (a `SKIN` wider) meets at cast point `centre`, or
## `fallback` when it meets none.
func _contact_normal(space: PhysicsDirectSpaceState3D, i: int, centre: Vector3,
		fallback: Vector3) -> Vector3:
	var probe := _scratch.query(_radius[i], exclude, SKIN)
	probe.transform = Transform3D(Basis(), centre)
	probe.motion = Vector3.ZERO
	var info := space.get_rest_info(probe)
	return info["normal"] if info.has("normal") and info["normal"] != Vector3.ZERO else fallback


## `at` (solver space) moved out of anything its sphere is inside or within `SKIN` of, along the
## surface's normal: a cast ignores a surface its sphere already touches, so a point the constraints
## or an earlier slide left against one would otherwise sink into it. A point left on a surface
## facing up is held by it (`_scratch.held`).
func _push_out(space: PhysicsDirectSpaceState3D, origin: Vector2, i: int, at: Vector3) -> Vector3:
	var params := _scratch.query(_radius[i], exclude, SKIN)
	for _k in PUSH_PASSES:
		var centre := _cast_point(at, origin, i)
		params.transform = Transform3D(Basis(), centre)
		params.motion = Vector3.ZERO
		var info := space.get_rest_info(params)
		if info.is_empty():
			break
		var normal: Vector3 = info["normal"]
		var across := (centre - (info["point"] as Vector3)).dot(normal)
		var depth := (_radius[i] + SKIN) * RenderConfig.unit - across
		if depth <= 0.0 or normal == Vector3.ZERO:
			break
		at += _solver_vector(normal * depth)
		if normal.y > FACES_UP:
			_scratch.held[i] = 1
	return at


## Storage reused by every substep: the two speed arrays and the broadphase/point-sweep queries.
class StepScratch extends RefCounted:
	## Vertical speed before the floor and speed before the constraints, overwritten by `_predict`.
	var fall := PackedFloat32Array()
	var free := PackedFloat32Array()
	## The one mutable solids query object and sphere shapes by point radius.
	var params: PhysicsShapeQueryParameters3D
	var shapes := {}
	## Box covering every point's start, end and radius for the current substep.
	var bounds := BoxShape3D.new()
	## Whether each point came to rest on a surface facing up in this sub-step's sweep, and in the
	## one before (a top holds a point like the floor: friction, and a bounce only on the landing).
	var held := PackedByteArray()
	var was_held := PackedByteArray()
	## False until the first step pulls starting points out of solids.
	var primed := false
	## Test seam for the reference path, and counts proving which path the solver took.
	var sweep_gate := true
	var broadphase_queries := 0
	var point_sweeps := 0


	## The reused solids query, set to a sphere of `radius` and ignoring `exclude`.
	func query(radius: float, exclude: Array[RID], skin := 0.0) -> PhysicsShapeQueryParameters3D:
		if params == null:
			params = PhysicsShapeQueryParameters3D.new()
			params.collision_mask = PhysicsConfig.twin_mask
			params.exclude = exclude
		var key := Vector2(radius, skin)
		if not shapes.has(key):
			var sphere := SphereShape3D.new()
			sphere.radius = (radius + skin) * RenderConfig.unit
			shapes[key] = sphere
		params.shape = shapes[key]
		return params
