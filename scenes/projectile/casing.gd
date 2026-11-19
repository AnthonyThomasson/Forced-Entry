extends Node2D
## Projectile System: a spent shell tossed out when a gun fires. It leaves the gun at the muzzle's
## height and flies in the twin 3D space (`SmallFlight`, tuned by `CasingConfig`): a hop, a fall,
## bounces off the walls and pieces it meets and a skid to rest on the floor or on top of a piece (a
## desk, a counter) at that surface's real height. Colliderless as a 2D node, Despawner-tracked. The
## 3D `ShotLayer` shows it, reading `altitude()` and `is_resting()`.

## Brass fill color.
@export var color: Color = Color(0.85, 0.7, 0.3)

## Its flight (plan place, height, velocity), made by `start`.
var _flight: SmallFlight
## Its spin (rad/s) and the seconds it has flown.
var _spin := 0.0
var _age := 0.0


func _ready() -> void:
	ViewLayers.set_moving(self, true)


func _physics_process(delta: float) -> void:
	if _flight == null or _flight.resting:
		return
	_age += delta
	_flight.step(TwinSpace.space_of(self), delta)
	global_position = _flight.at
	if _flight.rolling:
		_spin = move_toward(_spin, 0.0, CasingConfig.spin_friction * delta)
	rotation += _spin * delta
	if _flight.resting or _age >= CasingConfig.max_time:
		_flight.resting = true
		_spin = 0.0
		ViewLayers.set_moving(self, false)
		set_physics_process(false)


## Kick the casing out along `eject_dir` (need not be normalized) from `height` px up, hopped up and
## thrown out so that over level ground it would land `CasingConfig.eject_distance` away, turning a
## whole turn either way as it goes. It then flies by itself; its place must already be set.
func start(eject_dir: Vector2, height: float) -> void:
	var unit := eject_dir.normalized() if eject_dir.length() > 0.001 else Vector2.RIGHT
	_spin = CasingConfig.spin * (1.0 if WorldRng.of(self).randf() > 0.5 else -1.0)
	_flight = SmallFlight.new(CasingConfig.radius)
	_flight.gravity = CasingConfig.gravity
	_flight.floor_restitution = CasingConfig.bounce
	_flight.wall_restitution = CasingConfig.wall_bounce
	_flight.friction = CasingConfig.friction
	_flight.mask = PhysicsConfig.twin_mask
	_flight.place(global_position, height)
	var hop := sqrt(2.0 * CasingConfig.gravity * CasingConfig.hop)
	var speed := SmallFlight.speed_for(
		CasingConfig.eject_distance, hop, _flight.altitude(), CasingConfig.gravity
	)
	_flight.velocity = unit * speed
	_flight.rise = hop


## How high the casing is (px): its underside over the floor, or over the piece it lies on.
func altitude() -> float:
	return _flight.altitude() if _flight != null else 0.0


## Whether the casing lies still.
func is_resting() -> bool:
	return _flight != null and _flight.resting
