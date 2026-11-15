class_name FadeUnit
extends RefCounted
## Art domain, one thing the wall fade fades as a whole (`wall_fade.gd`): a wall's segment, or a
## whole tall piece of furniture. It holds the instances it fades, the box they stand in (placed
## when it is made, and again each time a movable one moves), and how far it is faded now: the
## progress `faded` (0 whole, 1 faded) the fade steps, and the level last written to the instances
## (`WallFadeConfig.steps` is whole), so the instances are written only when that changes.

## The instances faded together and the node the box is placed by (the piece's mesh, or a wall's
## segment) with the box in that node's frame.
var parts: Array[GeometryInstance3D] = []
var anchor: Node3D
var local_box := AABB()
## The footprint and height, in the world's frame; `last` is the anchor's transform it was placed
## from (a movable piece is placed again when that changes).
var box := FadeBox.new()
var last := Transform3D()
## Whether the piece can move (furniture, a door): the grid polls it for a move. The cells it is
## filed in, as a rectangle of cell coordinates (`FadeGrid`).
var movable := false
var span := Rect2i()
## How faded it is now (0 whole, 1 faded), the level of that last written to its instances, and
## whether the fade has it on its list of those that are not whole.
var faded := 0.0
var level := 0
var listed := false
## The frame a focus last found it in the way, and the probe that last looked at it (a long piece
## is filed in many cells and is asked once for each focus).
var hit_frame := -1
var probe := -1


## A unit of `anchor`'s `parts`: `local_box` is the box of all of them in the anchor's frame.
static func make(
	anchor_node: Node3D, instances: Array[GeometryInstance3D], bounds: AABB, moves: bool
) -> FadeUnit:
	var unit := FadeUnit.new()
	unit.anchor = anchor_node
	unit.parts = instances
	unit.local_box = bounds
	unit.movable = moves
	unit.level = WallFadeConfig.steps
	unit.place()
	return unit


## Place the box from the anchor's transform now.
func place() -> void:
	last = anchor.global_transform
	box.set_box(last, local_box)


## Write the instances if the level its `faded` calls for is not the one last written; whether it
## wrote. A level is a step of `WallFadeConfig.steps`, the shader's own resolution.
func apply() -> bool:
	var steps := maxi(WallFadeConfig.steps, 1)
	var wanted := roundi(lerpf(1.0, WallFadeConfig.faded_amount, faded) * float(steps))
	if wanted == level:
		return false
	level = wanted
	var amount := float(wanted) / float(steps)
	for part in parts:
		if is_instance_valid(part):
			MeshNodes.fade(part, amount)
	return true
