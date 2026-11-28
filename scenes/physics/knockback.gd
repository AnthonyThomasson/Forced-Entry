class_name Knockback extends Node
## Physics System: the shove component of a shoveable body, a child of the body that holds its mass
## and shoves it. Its `apply_impulse(v, at_world, height)` is how the owner's `take_hit` shoves the
## body. The "pushable" contract is `apply_impulse(v, at)` / `get_mass()` on the body, but a piece
## whose truth is a free 3D body (`TwinSpace.leader_of`, interface 29: furniture) is
## shoved through that body, at the point's real height, so a push goes through `Knockback.push`,
## which every pusher of the contract (interface 5) calls: it answers to the 3D body when there is
## one and to the body's own `apply_impulse` otherwise. The engine integrates motion, collisions,
## pivoting and settling in 3D; this component only feeds it impulses (a free piece hands momentum
## to a character it slides into in 3D, `PieceBody`). All tuning is PhysicsImpactConfig.

## Sentinel for `apply_impulse`'s optional contact point (a central shove when omitted).
const _NO_POINT := Vector2(INF, INF)

## The body's mass. Set by the owner from its catalog definition.
var mass: float = 10.0
## The shoved body (parent).
var _body: Node2D


func _ready() -> void:
	_body = get_parent() as Node2D


## The mass a body of catalogue `weight` has: floored so featherweight decor still reacts.
static func mass_of(weight: float) -> float:
	return maxf(weight, 0.5)


## Apply a shove. With no contact point it is a central impulse; given a world contact point
## it is applied off-center so the body spins/pivots (a bullet or punch landing off-center), and
## `height` px above the floor (-1: the body's centre) so a free 3D body leans or slides by where it
## was struck.
func apply_impulse(impulse: Vector2, at_world: Vector2 = _NO_POINT, height: float = -1.0) -> void:
	var at := Vector2.ZERO if at_world == _NO_POINT else at_world - _body.global_position
	push(_body, impulse, at, height)


## Shove `body` by `impulse` (plan space) at `at` px from its origin (world orientation; zero is the
## origin) `height` px above the floor (-1: no height known, the body's centre): the one way every
## pusher of the contract (interface 5) shoves one. A piece led by a free 3D body is shoved through
## it, in 3D; anything else through its own `apply_impulse(impulse, at)`.
static func push(
	body: Object,
	impulse: Vector2,
	at: Vector2 = Vector2.ZERO,
	height: float = -1.0,
) -> void:
	var lead := TwinSpace.leader_of(body)
	if lead != null:
		lead.call(&"push", impulse, at, height)
	else:
		body.call(&"apply_impulse", impulse, at)
