extends UnitSuite
## The world of `SightRay`'s native suites (`tests/general/sight_ray_suite.gd`,
## `sight_ray_eye_suite.gd`; not a suite itself): pieces of a declared height standing far from the
## origin, each lifted into a twin space (`TwinSpace`, with a hook of the suite's own) that is as
## tall as the piece says.

## Where the pieces stand: far from the origin, so no other test's body is near.
const ORIGIN := Vector2(40_000.0, 40_000.0)
## A standing eye's height (1.64 m at 42.3 px a metre): a piece at or below it is looked over.
const SEE_OVER := 69.4

var _twins: TwinSpace


## A piece `size` big centred at `at` (relative to `ORIGIN`), `height` px tall: its twin is that
## tall.
func _piece(at: Vector2, size: Vector2, height: float) -> Piece:
	var piece: Piece = auto_free(Piece.new())
	piece.height = height
	_shape(piece, at, size)
	return piece


## A glass-panel piece: 96 tall, and its surface says it is `transparent` (the glass-panel door).
func _glass(at: Vector2, size: Vector2) -> Piece:
	var glass := _piece(at, size, 96.0)
	glass.transparent = true
	return glass


func _mute(at: Vector2, size: Vector2) -> Mute:
	var mute: Mute = auto_free(Mute.new())
	_shape(mute, at, size)
	return mute


func _shape(body: Node2D, at: Vector2, size: Vector2) -> void:
	body.position = ORIGIN + at
	body.set_meta(&"size", size)
	add_child(body)


## The physics space once the bodies added are in it (a body joins the broadphase at the next step).
func _space() -> PhysicsDirectSpaceState3D:
	if _twins == null:
		_twins = auto_free(TwinSpace.new())
		_twins.builders.append(_lift)
		add_child(_twins)
		_twins.watch(self)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return _twins.space()


## The twin of a piece: a static body as tall as the piece says, on the world layer.
func _lift(node: Node2D) -> Node3D:
	if not node.has_meta(&"height"):
		return null
	var twin := StaticBody3D.new()
	var size: Vector2 = node.get_meta(&"size")
	var height: float = node.get_meta(&"height")
	twin.add_child(TwinShapes.box(Rect2(-size / 2.0, size), Transform2D.IDENTITY, 0.0, height))
	twin.collision_layer = PhysicsLayers.TWIN_WORLD
	twin.collision_mask = 0
	return twin


## The 3D space of the twins.
func _space3() -> PhysicsDirectSpaceState3D:
	return await _space()


## The rid of the twin of `body` (once `_space` has run): what a cast leaves out.
func _rid(body: Node2D) -> RID:
	return (TwinSpace.twin_for(body) as CollisionObject3D).get_rid()


## The line from `from` to `to`, both relative to `ORIGIN`.
func _line(from: Vector2, to: Vector2) -> Array[Vector2]:
	return [ORIGIN + from, ORIGIN + to]


## A solid piece with a height: a plan handle (a `Node2D` of `TwinSpace.BODIES`) whose twin (the
## suite's hook) is that tall, and whose surface says `transparent` for a glass-panel door.
class Piece:
	extends Node2D

	var height := 96.0:
		set(value):
			height = value
			set_meta(&"height", value)
	var transparent := false
	## What a character has and a piece has not: with one, the body is a character.
	var movement: Node = null


	func _init() -> void:
		add_to_group(TwinSpace.BODIES)


	func get_surface() -> Dictionary:
		return { "transparent": true } if transparent else {}


## A solid handle with no twin: nothing says how tall it is.
class Mute:
	extends Node2D


	func _init() -> void:
		add_to_group(TwinSpace.BODIES)
