extends RefCounted
## A test probe: sits in `PhysicsFxHook.sink`, writes down every burst of hit particles and blast
## the 2D Physics code tells the 3D render about, and passes every call on to the sink it replaced,
## so a window's own 3D picture still shows them. `attach` it before the shot, `detach` it after.
## The 2D burst is a plain dict (`HitParticles.spawn`'s), so a test asserts on what was made, not
## on a node that no longer exists.

## Every burst told since `attach`, oldest first.
var bursts: Array[Dictionary] = []
## Every grenade's blast told since `attach`, oldest first: `{ at, look }`, `look` the row of
## `PhysicsExplosionConfig.looks` it was made from.
var blasts: Array[Dictionary] = []
var _previous: Object


## Take the hook's place, remembering who held it.
func attach() -> RefCounted:
	_previous = PhysicsFxHook.sink
	PhysicsFxHook.sink = self
	return self


## Give the hook back to who held it.
func detach() -> void:
	if PhysicsFxHook.sink == self:
		PhysicsFxHook.sink = _previous
	_previous = null


## The bursts whose place is within `reach` px of `at`.
func bursts_near(at: Vector2, reach: float) -> Array[Dictionary]:
	var near: Array[Dictionary] = []
	for burst in bursts:
		if (burst["at"] as Vector2).distance_to(at) <= reach:
			near.append(burst)
	return near


func chip_flew(chip: Node2D, height: float) -> void:
	if is_instance_valid(_previous):
		_previous.chip_flew(chip, height)


func chip_landed(chip: Node2D) -> void:
	if is_instance_valid(_previous):
		_previous.chip_landed(chip)


func burst_made(burst: Dictionary) -> void:
	bursts.append(burst)
	if is_instance_valid(_previous):
		_previous.burst_made(burst)


func splat_made(splat: Node2D) -> void:
	if is_instance_valid(_previous):
		_previous.splat_made(splat)


func print_made(poly: PackedVector2Array, alpha: float) -> void:
	if is_instance_valid(_previous):
		_previous.print_made(poly, alpha)


func ribbon_begun(source: Dictionary) -> void:
	if is_instance_valid(_previous):
		_previous.ribbon_begun(source)


func ribbon_grew(source: Dictionary) -> void:
	if is_instance_valid(_previous):
		_previous.ribbon_grew(source)


func scorch_burned(rects: Array[Rect2], tones: Array[Color]) -> void:
	if is_instance_valid(_previous):
		_previous.scorch_burned(rects, tones)


func pool_made(pool: Node2D) -> void:
	if is_instance_valid(_previous):
		_previous.pool_made(pool)


func pool_changed(pool: Node2D) -> void:
	if is_instance_valid(_previous):
		_previous.pool_changed(pool)


func blast_made(at: Vector2, row: Dictionary) -> void:
	blasts.append({ "at": at, "look": row })
	if is_instance_valid(_previous):
		_previous.blast_made(at, row)
