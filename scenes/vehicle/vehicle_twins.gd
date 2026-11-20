class_name VehicleTwins
extends RefCounted
## Vehicles domain, the 3D body of a vehicle for the twin space (`TwinSpace`, interface 29, #194
## D3/D13): a `VehicleBody`, a free 3D body locked upright that leads its 2D body, with the
## vehicle's real shape: its whole outline from the ground to the top of its body
## (`VehicleMeshConfig.heights`' `belt`), and the cabin, its own footprint (the `roof` rectangle of
## the kind's `looks`), on from the belt to the roof, so a grenade rests on a roof, a bullet strikes
## the glass and a sight line is stopped by a roof, at the real heights. On
## `PhysicsLayers.TWIN_VEHICLE`. A dent does not reshape the body.


## Add the hook to `space` (a `TwinSpace`).
static func register(space: TwinSpace) -> void:
	space.builders.append(Callable(VehicleTwins, &"build"))


## The 3D body of `node` if it is a vehicle, else null.
static func build(node: Node2D) -> Node3D:
	if not node.is_in_group(&"vehicles"):
		return null
	var kind: Variant = node.get("kind")
	if not VehicleMeshConfig.heights.has(kind):
		return null  # a stand-in in the group, no vehicle
	var heights: Dictionary = VehicleMeshConfig.heights[kind]
	var body := VehicleBody.new(node)
	# the hull as a 2D convex shape's point cloud was made (its order is what Jolt builds from)
	var outline := Geometry2D.convex_hull(PackedVector2Array(node.call(&"outline")))
	var belt := float(heights["belt"])
	body.add_child(TwinShapes.lift_outline(outline, Transform2D.IDENTITY, 0.0, belt))
	var roof: Vector2 = VehicleConfig.looks[kind]["roof"]
	var half := float(VehicleConfig.looks[kind]["roof_half"])
	var cabin := Rect2(
		Vector2(minf(roof.x, roof.y), -half),
		Vector2(absf(roof.x - roof.y), half * 2.0),
	)
	body.add_child(TwinShapes.box(cabin, Transform2D.IDENTITY, belt, float(heights["roof"])))
	return body
