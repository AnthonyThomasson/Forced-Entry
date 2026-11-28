class_name BloodWound
extends Node
## Physics System, blood: a wounded body's bleeding, composed by the character like Knockback /
## Deformable. Each hit throws a quick spray of splatters out of the wound (`record`) and adds to a
## budget of drips; then, while the budget lasts, one drop falls every
## BloodDripConfig.interval_min..max seconds from where the body's blood leaves it, landing as a
## BloodSplat (a moving body's drops land ahead of it and stretch with its speed). `stop` ends the
## dripping (the body died; its bleed-out pool takes over). Splatters are added to the body's parent
## and capped per body (BloodSplatConfig.max_splats_per_body, oldest freed first). Nothing happens
## while BloodConfig.enabled is off.

const BloodSplat = preload("res://scenes/physics/blood/blood_splat.gd")

## Whether a hit's spray merges its splats' outlines side by side on worker threads (each splat
## begun as it is thrown, all finished later in the frame by `BloodSplat.defer_finish`), else builds
## each whole as it is thrown: the same splats either way (for tests).
static var spray_side_by_side := true

## Drips still owed, and seconds until the next one.
var _drips := 0
var _wait := 0.0
## This body's splatters, oldest first, with constant-time eviction.
var _splats := SplatQueue.new()
## Set by `stop()` (death): no more splatters or drips.
var _stopped := false


func _ready() -> void:
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not BloodConfig.enabled:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_drip()
	_drips -= 1
	if _drips <= 0:
		set_physics_process(false)
	else:
		_wait = _next_wait()


## Take a hit: spray splatters from `hit.position` out the wound's exit side and owe more drips.
func record(hit: HitInfo) -> void:
	if not BloodConfig.enabled or _stopped:
		return
	var host := get_parent() as Node2D
	if host == null:
		return
	var out := hit.spray_direction()
	var thrown: Array[Node] = []  # the spray's splats begun, finished later in the frame
	var sprays := clampi(
		ceili(hit.damage / maxf(BloodSprayConfig.hit_splat_damage, 0.001)),
		1,
		BloodSprayConfig.hit_splat_max,
	)
	for i in sprays:
		_spray(hit, out, i, thrown)
	# A round that went right through also throws blood out the far side, along its flight.
	if hit.has_exit:
		var throw := _throw_of(_spray_size(), hit.direction, BloodSprayConfig.energy)
		var at := _landing(
			throw,
			hit,
			hit.exit_position,
			hit.exit_position,
			BloodSprayConfig.reach_max,
		)
		_add_splat(at, throw, thrown)
	BloodSplat.defer_finish(thrown)

	var owed := maxi(1, ceili(hit.damage * BloodDripConfig.drips_per_damage))
	if _drips == 0:
		_wait = _next_wait()
	_drips = mini(_drips + owed, BloodDripConfig.max_pending_drips)
	set_physics_process(true)


## The body died: no more drips.
func stop() -> void:
	_stopped = true
	_drips = 0
	set_physics_process(false)


## One drop leaves the body and lands: it keeps the body's walking velocity for
## `BloodDripConfig.fall_time`, so a walker's drops land ahead of it and splat stretched along its
## heading.
func _drip() -> void:
	var host := get_parent() as Node2D
	if host == null:
		return
	var origin: Vector2 = (host.blood_origin()
			if host.has_method("blood_origin")
			else host.global_position)
	var velocity := Vector2.ZERO
	var motion: Variant = host.get("movement")  # the host's walk, duck-typed
	if motion is Object and (motion as Object).get("velocity") is Vector2:
		velocity = (motion as Object).get("velocity")
	var land := origin + velocity * BloodDripConfig.fall_time + _jitter()
	var energy := clampf(
		velocity.length() / maxf(BloodDripConfig.full_energy_speed, 0.001),
		0.0,
		1.0,
	)
	var size := randf_range(BloodDripConfig.size_min, BloodDripConfig.size_max)
	_add_splat(land, _throw_of(size, velocity, energy))


## Seconds until the next drip falls, drawn from the configured interval.
func _next_wait() -> float:
	return randf_range(BloodDripConfig.interval_min, BloodDripConfig.interval_max)


## A random offset, up to `BloodDripConfig.jitter` px, that scatters where a drip lands.
func _jitter() -> Vector2:
	return Vector2.from_angle(randf() * TAU) * randf() * BloodDripConfig.jitter


## Splatter `i` of a hit's spray, flung about `out`: the first lands at the wound, the rest as far
## out as `BloodSprayConfig.reach_min..reach_max`.
func _spray(hit: HitInfo, out: Vector2, i: int, thrown: Array[Node]) -> void:
	var dir := out.rotated(randf_range(-BloodSprayConfig.spread, BloodSprayConfig.spread))
	var reach := (randf_range(BloodSprayConfig.reach_min, BloodSprayConfig.reach_max)
			if i > 0
			else 0.0)
	var throw := _throw_of(_spray_size(), dir, BloodSprayConfig.energy if i > 0 else 0.4)
	var at := _landing(throw, hit, hit.position, hit.position + dir * reach, reach)
	_add_splat(at, throw, thrown)


## A spray splatter's core radius: a drip's, scaled.
func _spray_size() -> float:
	return (randf_range(BloodDripConfig.size_min, BloodDripConfig.size_max)
			* BloodSprayConfig.hit_splat_size)


## The throw of a splatter of core radius `size` flung toward `direction` with `energy`, from this
## body (its own twin is ignored by the splat's wall clipping).
func _throw_of(size: float, direction: Vector2, energy: float) -> BloodThrow:
	var host := get_parent() as Node2D
	var throw := BloodThrow.new()
	throw.size = size
	throw.direction = direction
	throw.energy = energy
	var twin := TwinSpace.twin_for(host) as CollisionObject3D
	throw.exclude = [twin.get_rid()] if twin != null else []
	return throw


## Where blood thrown as `throw` from plan point `from` lands, when it would come down at `at`
## `flight` px out: it leaves at the hit's real height and is traced through the twin 3D space
## (`BloodLanding`) down to where it lands; on a wall or a piece's top the throw records the surface
## and the answer is the point on it, else `at`, the floor's. (A hit has one height: the exit blood
## leaves at it too.)
func _landing(
	throw: BloodThrow,
	hit: HitInfo,
	from: Vector2,
	at: Vector2,
	flight: float,
) -> Vector2:
	throw.surface = BloodLanding.trace(
		TwinSpace.space_of(self), from, throw.direction, hit.height, flight
	)
	return throw.surface.get("at", at)


## Place a splatter thrown as `throw` at world `at` and keep it within this body's cap. Given
## `thrown`, a spray's splat is only begun and added to it, for the caller to finish (see
## `spray_side_by_side`).
func _add_splat(at: Vector2, throw: BloodThrow, thrown: Variant = null) -> void:
	var host := get_parent() as Node2D
	var begun := thrown != null and spray_side_by_side
	if throw.surface.is_empty():
		var reach := throw.size * (1.0 + BloodSplatConfig.stretch * throw.energy)
		at = BloodLanding.clear_of_solids(
			TwinSpace.space_of(self), at, reach * (1.0 + BloodSplatConfig.wobble)
		)
	var splat := BloodSpawner.splat(host.get_parent(), at, throw, not begun)
	if begun:
		(thrown as Array).append(splat)
	_splats.append(splat)
	while (_splats.size() > BloodSplatConfig.max_splats_per_body
			or (_splats.size() > 0 and not is_instance_valid(_splats.oldest()))):
		# Untyped: the loop also pops an already-freed splat (something else freed it), and
		# assigning a freed instance to a typed `Node` is an engine error.
		var oldest = _splats.pop()
		if is_instance_valid(oldest):
			oldest.queue_free()


## A splat FIFO with an advancing head instead of a front-pop; consumed slots are compacted only
## occasionally.
class SplatQueue extends RefCounted:
	## Live splats and the consumed prefix. Untyped so an externally freed instance can be removed.
	var _splats: Array = []
	## First live slot.
	var _oldest := 0


	## Add a splat as newest.
	func append(splat: Node) -> void:
		_splats.append(splat)


	## Number of live entries, including any externally freed splat awaiting removal.
	func size() -> int:
		return _splats.size() - _oldest


	## The oldest entry without removing it.
	func oldest() -> Variant:
		return _splats[_oldest]


	## Remove and return the oldest entry.
	func pop() -> Variant:
		var splat = _splats[_oldest]
		_splats[_oldest] = null
		_oldest += 1
		_compact()
		return splat


	## Live entries, oldest first.
	func items() -> Array:
		return _splats.slice(_oldest)


	## Fold away a substantial consumed prefix.
	func _compact() -> void:
		if _oldest < 64 or _oldest * 2 < _splats.size():
			return
		_splats = _splats.slice(_oldest)
		_oldest = 0
