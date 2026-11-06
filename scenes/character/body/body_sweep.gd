extends RefCounted
## The collide-and-slide a hand or a leg makes from the body centre toward where the pose or rig
## wants it. One conservative near-solid query after the pose is shared by both: when clear, no
## circle is cast. The character owns this helper, so its shapes, queries and exclusion lists are
## reused without sharing mutable query state between bodies.

## Physics layer a hand or leg meets: walls, solid furniture and living characters.
const MASK := PhysicsLayers.SOLID

## Test switch for the ungated reference path, and an observable that the gate is running.
var gate_enabled := true
## True when the last shared query found a solid in reach; always true on the ungated path.
var near_solid := true
## Number of hand and leg circle casts made by this body.
var casts := 0
## Number of shared near-solid queries made by this body.
var near_queries := 0
var _character: CharacterBody2D
var _exclude: Array[RID] = []
var _ray_exclude: Array[RID] = []
var _shapes := {}
var _params := PhysicsShapeQueryParameters2D.new()
var _ray := PhysicsRayQueryParameters2D.new()


## The body whose sweeps and queries this owns.
func _init(character: CharacterBody2D) -> void:
	_character = character
	_exclude = [character.get_rid()]
	_ray_exclude = [character.get_rid()]
	_params.collision_mask = MASK
	_ray.collision_mask = MASK


## Whether the shared query proved nothing solid is in reach, so no hand or leg need be swept.
func is_clear() -> bool:
	return gate_enabled and not near_solid


## Refresh the one conservative near-solid result shared by this frame's hands and legs. `radius`
## encloses every circle's whole sweep, including the circle itself.
func refresh(radius: float) -> void:
	if not gate_enabled:
		near_solid = true
		return
	near_queries += 1
	_query(_character.global_position, radius)
	near_solid = not _space().intersect_shape(_params, 1).is_empty()


## Where a circle of `radius` swept from `centre` (world) along `motion` comes to rest, as a local
## offset from `centre`: `motion` itself when the way is clear.
func circle(centre: Vector2, motion: Vector2, radius: float) -> Vector2:
	if motion.length_squared() < 0.0001:
		return motion
	casts += 1
	_query(centre, radius)
	_params.motion = motion
	var safe: float = _space().cast_motion(_params)[0]  # [safe, unsafe] fractions of the motion.
	if safe >= 1.0:
		return motion
	var rest := motion * safe
	_ray.from = centre
	_ray.to = centre + motion
	_ray.exclude = _exclude
	var hit := _space().intersect_ray(_ray)
	var normal: Vector2 = (hit.normal
			if not hit.is_empty() and hit.normal.length() > 0.001
			else -motion.normalized())
	var slide := (motion * (1.0 - safe)).slide(normal)
	_params.transform = Transform2D(0.0, centre + rest)
	_params.motion = slide
	return rest + slide * float(_space().cast_motion(_params)[0])


## How far a weapon's ray reaches before a wall or solid object; other characters do not count.
func solid_distance(from: Vector2, dir: Vector2, max_len: float) -> float:
	_ray.from = from
	_ray.to = from + dir * max_len
	var distance := INF
	for _attempt in 6:
		_ray.exclude = _ray_exclude
		var hit := _space().intersect_ray(_ray)
		if hit.is_empty():
			break
		if hit.collider is CharacterBody2D:
			_ray_exclude.append(hit.rid)
			continue
		distance = from.distance_to(hit.position)
		break
	_ray_exclude.resize(1)
	return distance


## The light, pushable piece touching a foot-sized circle at world point `at`, or null.
func pushable_at(at: Vector2) -> Node:
	_query(at, CharacterPushConfig.leg_radius + 1.5)
	for result in _space().intersect_shape(_params, 4):
		var body: Object = result.collider
		if body is CharacterBody2D:
			continue
		if body.has_method("apply_impulse") and body.has_method("get_mass"):
			return body
	return null


## Prepare the reused shape query for a circle at `centre`.
func _query(centre: Vector2, radius: float) -> void:
	if not _shapes.has(radius):
		var shape := CircleShape2D.new()
		shape.radius = radius
		_shapes[radius] = shape
	_params.shape = _shapes[radius]
	_params.exclude = _exclude
	_params.transform = Transform2D(0.0, centre)
	_params.motion = Vector2.ZERO


## The body's current physics space.
func _space() -> PhysicsDirectSpaceState2D:
	return _character.get_world_2d().direct_space_state
