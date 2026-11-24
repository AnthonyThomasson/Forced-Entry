extends RefCounted
## The collide-and-slide a hand or a leg makes from the body centre toward where the pose or rig
## wants it, in the 3D twin space (`TwinSpace`) at the height the hand or the foot really is
## (`BodyHeights.contact`: a foot at the ankle, a knee, a fist), so a hand swings over a low table
## and a foot is stopped by a sofa's seat. One conservative near-solid query after the pose is
## shared by both: when clear, no sphere is cast. The character owns this helper, so its shapes,
## queries and exclusion lists are reused without sharing mutable query state between bodies. A
## character built with no twin space finds nothing solid.

## Physics layers a hand or leg meets: walls, solid furniture, vehicles and living characters.
const MASK := PhysicsLayers.TWIN_ALL
## What a weapon's barrel is held against: walls, furniture and vehicles, not people.
const BARREL_MASK := PhysicsLayers.TWIN_SURFACES
## How far up (px) the near-solid gate starts: clear of a floor slab's top.
const GATE_FEET := 1.0

## Test switch for the ungated reference path, and an observable that the gate is running.
var gate_enabled := true
## True when the last shared query found a solid in reach; always true on the ungated path.
var near_solid := true
## Number of hand and leg sphere casts made by this body.
var casts := 0
## Number of shared near-solid queries made by this body.
var near_queries := 0
var _character: Node2D
var _shapes := {}
var _params := PhysicsShapeQueryParameters3D.new()
var _ray := PhysicsRayQueryParameters3D.new()
## The twin space of `_space_frame` (a body stays in one world, so one physics frame asks the engine
## once however many casts it makes), and the body's twin the exclusion lists were built for with
## those lists (what `_params` and `_ray` hold, set only when the twin changes; null until first
## built, an empty one for a body with no twin).
var _space_cache: PhysicsDirectSpaceState3D
var _space_frame := -1
var _twin: Node3D
var _excluded: Variant = null
## The sphere shape last asked for and its radius (px), the common repeat of a hand's or a foot's
## casts.
var _last_radius := -1.0
var _last_shape: SphereShape3D
## The mask `_ray` holds.
var _ray_mask := MASK


## The body whose sweeps and queries this owns.
func _init(character: Node2D) -> void:
	_character = character
	_params.collision_mask = MASK
	_ray.collision_mask = MASK


## Whether the shared query proved nothing solid is in reach, so no hand or leg need be swept.
func is_clear() -> bool:
	return gate_enabled and not near_solid


## Refresh the one conservative near-solid result shared by this frame's hands and legs. `radius`
## encloses every circle's whole sweep, including the circle itself: a cylinder that radius round
## the body's centre and as tall as a standing body.
func refresh(radius: float) -> void:
	if not gate_enabled:
		near_solid = true
		return
	near_queries += 1
	var space := _space()
	if space == null:
		near_solid = false
		return
	_exclude()
	var key := Vector2(radius, -1.0)
	if not _shapes.has(key):
		var gate := CylinderShape3D.new()
		gate.radius = radius * RenderConfig.unit
		gate.height = (BodyHeights.head_top(BodyHeights.STAND) - GATE_FEET) * RenderConfig.unit
		_shapes[key] = gate
	_params.shape = _shapes[key]
	_params.transform = Transform3D(
		Basis(),
		PlanSpace.lift(_character.global_position, GATE_FEET)
		+ Vector3.UP * (_shapes[key] as CylinderShape3D).height * 0.5,
	)
	_params.motion = Vector3.ZERO
	near_solid = not space.intersect_shape(_params, 1).is_empty()


## Where a foot-sized sphere of `radius` swept from `centre` (world, plan) `height` px up along plan
## `motion` comes to rest, as a local offset from `centre`: `motion` itself when the way is clear.
func circle(centre: Vector2, motion: Vector2, radius: float, height: float) -> Vector2:
	if motion.length_squared() < 0.0001:
		return motion
	var space := _space()
	if space == null:
		return motion
	casts += 1
	_sphere(centre, radius, height)
	_params.motion = Vector3(motion.x, 0.0, motion.y) * RenderConfig.unit
	var safe: float = space.cast_motion(_params)[0]  # [safe, unsafe] fractions of the motion.
	if safe >= 1.0:
		return motion
	var rest := motion * safe
	_ray.from = PlanSpace.lift(centre, height)
	_ray.to = PlanSpace.lift(centre + motion, height)
	_set_ray_mask(MASK)
	var hit := space.intersect_ray(_ray)
	var normal := -motion.normalized()
	if not hit.is_empty():
		var flat := Vector2(hit["normal"].x, hit["normal"].z)
		if flat.length() > 0.001:
			normal = flat.normalized()
	var slide := (motion * (1.0 - safe)).slide(normal)
	_params.transform = Transform3D(Basis(), PlanSpace.lift(centre + rest, height))
	_params.motion = Vector3(slide.x, 0.0, slide.y) * RenderConfig.unit
	return rest + slide * float(space.cast_motion(_params)[0])


## How far a weapon's ray reaches before a wall or solid object, flown level `height` px up; other
## characters do not count.
func solid_distance(from: Vector2, dir: Vector2, max_len: float, height: float) -> float:
	var space := _space()
	if space == null:
		return INF
	_exclude()
	_ray.from = PlanSpace.lift(from, height)
	_ray.to = PlanSpace.lift(from + dir * max_len, height)
	_set_ray_mask(BARREL_MASK)
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return INF
	return from.distance_to(PlanSpace.plan_of(hit["position"]))


## The light, pushable piece touching a foot-sized sphere at world plan point `at`, `height` px up,
## or null.
func pushable_at(at: Vector2, height: float) -> Node:
	var space := _space()
	if space == null:
		return null
	_sphere(at, CharacterPushConfig.leg_radius + 1.5, height)
	for result in space.intersect_shape(_params, 4):
		var body := TwinSpace.owner_of(result["collider"])
		if body == null or body.is_in_group(&"characters"):
			continue
		if body.has_method("apply_impulse") and body.has_method("get_mass"):
			return body
	return null


## Prepare the reused shape query for a sphere of `radius` at plan point `centre`, `height` up.
func _sphere(centre: Vector2, radius: float, height: float) -> void:
	if radius != _last_radius:
		var key := Vector2(radius, 0.0)
		if not _shapes.has(key):
			var shape := SphereShape3D.new()
			shape.radius = radius * RenderConfig.unit
			_shapes[key] = shape
		_last_shape = _shapes[key]
		_last_radius = radius
	_params.shape = _last_shape
	_exclude()
	_params.transform = Transform3D(Basis(), PlanSpace.lift(centre, height))
	_params.motion = Vector3.ZERO


## Make the reused ray meet `mask`, written only when it changes.
func _set_ray_mask(mask: int) -> void:
	if _ray_mask != mask:
		_ray_mask = mask
		_ray.collision_mask = mask


## Leave the body's own twin out of both reused queries, which a sweep passes through: the lists are
## rebuilt and written only when the twin is another one than last time.
func _exclude() -> void:
	var twin := TwinSpace.twin_for(_character)
	if _excluded != null and twin == _twin:
		return
	_twin = twin
	var list: Array[RID] = []
	if twin != null:
		list.append((twin as CollisionObject3D).get_rid())
	_excluded = list
	_params.exclude = list
	_ray.exclude = list


## The twin space the body is in, asked of the engine once a physics frame. Only a space the twin
## space answered is kept: the viewport's own world, which `TwinSpace.space_of` falls back to before
## the twin space is registered, is asked again next time.
func _space() -> PhysicsDirectSpaceState3D:
	var frame := Engine.get_physics_frames()
	if frame == _space_frame and _space_cache != null and _character.is_inside_tree():
		return _space_cache
	_space_cache = null
	if not _character.is_inside_tree():
		return null
	var twins := TwinSpace.space_in(_character.get_viewport().find_world_2d())
	if twins == null:
		return TwinSpace.space_of(_character)
	_space_cache = twins
	_space_frame = frame
	return twins
