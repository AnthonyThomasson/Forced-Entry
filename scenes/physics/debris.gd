extends Node2D
## Physics System: a small chip knocked off an object when it is hit. It leaves the hit at the hit's
## height and flies in the twin 3D space (`SmallFlight`, tuned by `PhysicsDebrisConfig`): a hop,
## a fall, bounces off the walls and pieces it meets, a skid to rest on the floor or on top of a
## piece (a desk, a counter) at that surface's real height. Styled by DebrisSpawner,
## Despawner-tracked while it flies; it draws nothing (the 3D render follows it, told by
## `PhysicsFxHook`). Once at rest the chip hands its place and height to the parent's `DebrisLayer`
## and frees itself.

## How many chips fly (a node each) in all: past `PhysicsMeshConfig.flying_room` a new one is not
## flown (the 3D render shows no more in the air either) but laid where it left the surface.
static var _flying := 0

## Chip fill color.
@export var color: Color = Color(0.6, 0.6, 0.6)
## Chip footprint in px.
@export var chip_size: Vector2 = Vector2(4, 4)
## Chip shape: "rect", "tri", or "circle".
@export var chip_shape: String = "rect"
## How far the chip travels as it is ejected (px): where it would land over level ground.
@export var eject_distance: float = 22.0

## Its flight (plan place, height, velocity), made by `start`.
var _flight: SmallFlight
## Its spin (rad/s) and the seconds it has flown.
var _spin := 0.0
var _age := 0.0
## The twin space it flies in (found once: a chip stays in its world), and whether it is counted in
## `_flying` and still to be checked for a start inside a solid.
var _space: PhysicsDirectSpaceState3D
var _counted := false
var _checked := false


func _physics_process(delta: float) -> void:
	_age += delta
	if _flight == null:
		return
	if not _checked:
		_check_start()
	_flight.step(_space, delta)
	global_position = _flight.at
	if _flight.rolling or _flight.resting:
		_spin = move_toward(_spin, 0.0, PhysicsDebrisConfig.spin_friction * delta)
	rotation += _spin * delta
	if _age >= PhysicsDebrisConfig.max_time and not _flight.resting:
		_flight.settle(_space)
	if _flight.resting:
		_rest()


func _exit_tree() -> void:
	if _counted:
		_counted = false
		_flying -= 1


## Kick the chip out along `eject_dir` (need not be normalized; a zero one tosses it right) from
## `height` px up (the hit's: negative for the floor): out of the surface by its own size, thrown up
## a hop and out so that over level ground it would land `eject_distance` away. It then flies by
## itself; the chip's place must already be set.
func start(eject_dir: Vector2, height := -1.0) -> void:
	var rng := WorldRng.of(self)
	_spin = TAU * rng.randf_range(-1.0, 1.0) * PhysicsDebrisConfig.spin_turns
	rotation = rng.randf_range(0.0, TAU)
	var unit := eject_dir.normalized() if eject_dir.length() > 0.001 else Vector2.RIGHT
	_flight = SmallFlight.new(PhysicsDebrisConfig.radius)
	_flight.gravity = PhysicsDebrisConfig.gravity
	_flight.floor_restitution = PhysicsDebrisConfig.bounce
	_flight.wall_restitution = PhysicsDebrisConfig.wall_bounce
	_flight.friction = PhysicsDebrisConfig.friction
	_flight.mask = PhysicsConfig.twin_mask
	var clear := PhysicsDebrisConfig.radius + SmallFlight.CLEAR_GAP
	var centre := _flight.floor_height() if height < 0.0 else height + clear
	_flight.place(global_position + unit * clear, centre)
	var hop := sqrt(2.0 * PhysicsDebrisConfig.gravity * PhysicsDebrisConfig.hop)
	var speed := SmallFlight.speed_for(
		eject_distance, hop, _flight.altitude(), PhysicsDebrisConfig.gravity
	)
	_flight.velocity = unit * speed
	_flight.rise = hop
	global_position = _flight.at
	_counted = true
	_flying += 1


## How high the chip is (px): its underside over the floor, or over the piece it lies on.
func altitude() -> float:
	return _flight.altitude() if _flight != null else 0.0


## The first frame: a chip started inside a solid, or past the flying room, lies where it is.
func _check_start() -> void:
	_checked = true
	_space = TwinSpace.space_of(self)
	if _flying > PhysicsMeshConfig.flying_room or _flight.embedded(_space):
		_flight.settle(_space)


## The chip has come to rest: the parent's `DebrisLayer` keeps it from here on, and this node goes.
func _rest() -> void:
	set_physics_process(false)
	PhysicsFxHook.chip_landed(self)
	var parent := get_parent()
	if parent != null:
		DebrisLayer.layer(parent).lay(
			{
				"at": global_position,
				"height": altitude(),
				"turn": global_rotation,
				"color": color,
				"size": chip_size,
				"shape": chip_shape,
			}
		)
	queue_free()
