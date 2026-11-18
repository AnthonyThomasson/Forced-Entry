class_name CharacterTwin
extends AnimatableBody3D
## Character domain, the 3D twin of a character for the twin space (`TwinSpace`, interface 29,
## #194 D3): a kinematic upright cylinder on `PhysicsLayers.TWIN_CHARACTER`, its radius the body's
## circle and its height the real height of the posture it is in (`BodyHeights`: standing the
## stature, crouched the duck), so a ray at head height hits a standing body and passes over a
## ducked one. Its wall is straight up (a round meets the body square on at any height, as it does
## the 2D circle: a rounded top would turn a head shot's damage down by the slant it strikes). It
## follows the character's transform (the twin space moves it), its posture and whether the body is
## seated (the 2D circle disabled: no cylinder). A dead character's twin is off the layer (the 2D
## body's own layer is 0).

const Character = preload("res://scenes/character/character.gd")

## The character this is the twin of.
var _character: Character
## The cylinder and the holder it is in (resized as the posture changes) and the posture now.
var _shape := CylinderShape3D.new()
var _holder := CollisionShape3D.new()
var _posture: StringName = &""
## The body's own circle (a seated character disables it) and whether the cylinder is off for it.
var _circle: CollisionShape2D
var _seated := false


## Add the hook to `space` (a `TwinSpace`).
static func register(space: TwinSpace) -> void:
	space.builders.append(Callable(CharacterTwin, &"build"))


## The twin of `node` if it is a character, else null.
static func build(node: Node2D) -> Node3D:
	if not node is Character:
		return null
	var twin := CharacterTwin.new()
	twin._character = node as Character
	twin._circle = node.get_node_or_null(^"CollisionShape2D")
	twin.sync_to_physics = false
	twin.collision_layer = PhysicsLayers.TWIN_CHARACTER
	twin.collision_mask = 0
	twin._shape.radius = twin._character.radius * RenderConfig.unit
	twin._holder.shape = twin._shape
	twin.add_child(twin._holder)
	twin._set_posture(twin._character.movement.posture())
	return twin


## The twin space's per-frame hook: the cylinder follows the posture, and is off while seated.
func twin_update(_body: Node2D) -> void:
	var now: StringName = _character.movement.posture()
	if now != _posture:
		_set_posture(now)
	var seated := _circle != null and _circle.disabled
	if seated != _seated:
		_seated = seated
		_holder.disabled = seated


## Stand the cylinder to `posture`'s height, on the floor.
func _set_posture(posture: StringName) -> void:
	_posture = posture
	var height := BodyHeights.head_top(_character.movement.body_posture())
	_shape.height = maxf(height * RenderConfig.unit, 0.01)
	_holder.position = Vector3(0.0, _shape.height * 0.5, 0.0)
