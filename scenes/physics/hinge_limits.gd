class_name HingeLimits extends RefCounted
## A ragdoll hinge's shape and limits (`Ragdoll.add_hinge`): the parent bone's rest direction and
## the side the child bends to, both in the frame's space, how far the child may bend off straight
## toward that side and how far it may twist out of the plane. The owner of the skeleton (the
## Character domain) fills every field.

## The parent bone's rest direction in the frame's space (normalized by the ragdoll).
var rest: Vector3 = Vector3.ZERO
## The bend side in the frame's space, square to `rest` (normalized by the ragdoll).
var bend: Vector3 = Vector3.ZERO
## The least bend off straight toward `bend`, radians.
var min_angle: float = 0.0
## The most bend off straight toward `bend`, radians.
var max_angle: float = 0.0
## The twist out of the bend plane it allows either way, radians.
var slack: float = 0.0
