class_name DoorBody
extends AnimatableBody3D
## Objects domain, the 3D leader of a standing house door (interface 24 and 29,
## `docs/adr/0014-twin-staging-and-plan-space.md`): an `AnimatableBody3D` in the twin space
## (`TwinSpace`), shaped as the leaf (its length, its thickness,
## `ObjectStructureMeshConfig.door_height` tall, built from the real leaf), locked upright and
## turned about the hinge by the door's swing (`Door` computes the pose: the swing, the burst and a
## walker's push all end in `drive`). The 2D `Door` is its follower: the leader is moved first, and
## the 2D body written from the leader's pose in the same step, so a reader of either space finds
## the leaf where the other has it. It is on `PhysicsLayers.TWIN_WORLD`, so a bullet, a sight line,
## a fragment or a lob reads the leaf where it stands now. When the door is knocked down this body
## is replaced by a free one (`DoorSlab`, `TwinSpace.retwin`).

## The 2D door this is the leader of.
var _door: Node2D


## A leader for `of` (a `Door`); the shape is added by the builder (`ObjectTwins`).
func _init(of: Node2D = null) -> void:
	_door = of
	collision_layer = PhysicsLayers.TWIN_WORLD
	collision_mask = 0
	# a pose is set directly (the swing has checked what stands in the way): a ray cast after it
	# meets the leaf at its new pose, not where a kinematic move would have it by the next step
	sync_to_physics = false


## Called by the twin space as it takes the door over: the 2D door is the follower from now on,
## moved only by this body (`drive`); the twin space does not poll it.
func take_over(follower: Node2D) -> void:
	_door = follower


## Turn the leaf to `pose` (a 2D transform of the leaf's middle, its x axis along the leaf, hinge to
## latch): this body moves, upright, and the 2D door is written from where it stands.
func drive(pose: Transform2D) -> void:
	global_transform = PlanSpace.lift_transform(pose)
	force_update_transform()
	_door.global_transform = TwinSpace.plan_transform(global_transform, pose.get_rotation())
