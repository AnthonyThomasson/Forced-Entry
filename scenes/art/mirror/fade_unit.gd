class_name FadeUnit
extends RefCounted
## Art domain, one thing the wall fade fades as a whole (`wall_fade.gd`): a wall's segment, or a
## whole tall piece of furniture. It holds the instances it fades, the box they stand in (placed
## when it is made, and again each time a movable one moves), and how far it is faded now: the
## progress `faded` (0 whole, 1 faded) the fade steps, and the level last written to the instances
## (`WallFadeConfig.steps` is whole), so the instances are written only when that changes.

## How far faded a unit is when its shadow goes (and returns).
const SHADOW_OFF_AT := 0.5

## The instances faded together and the node the box is placed by (the piece's mesh, or a wall's
## segment) with the box in that node's frame.
var parts: Array[GeometryInstance3D] = []
## What each part's `cast_shadow` was when the unit was made, and whether the parts cast none now
## (a unit more than half faded casts no shadow: a stippled one darkens the character behind it).
var casts: Array[GeometryInstance3D.ShadowCastingSetting] = []
var shadowless := false
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
## What it hangs on or what hangs on it (a wall segment's pieces, a stain's wall).
var hang := FadeHang.new()


## A unit of `anchor`'s `parts`: `local_box` is the box of all of them in the anchor's frame.
static func make(
	anchor_node: Node3D, instances: Array[GeometryInstance3D], bounds: AABB, moves: bool
) -> FadeUnit:
	var unit := FadeUnit.new()
	unit.anchor = anchor_node
	unit.parts = instances
	for part in instances:
		unit.casts.append(part.cast_shadow)
	unit.local_box = bounds
	unit.movable = moves
	unit.level = WallFadeConfig.steps
	unit.place()
	return unit


## Place the box from the anchor's transform now.
func place() -> void:
	last = anchor.global_transform
	box.set_box(last, local_box)


## Write the instances if the level its `faded` calls for is not the one last written, and switch
## their shadows off or back when `faded` passes a half; whether it wrote. A level is a step of
## `WallFadeConfig.steps`, the shader's own resolution.
func apply() -> bool:
	var wrote := _cast_shadows(faded <= SHADOW_OFF_AT)
	var steps := maxi(WallFadeConfig.steps, 1)
	var wanted := roundi(lerpf(1.0, WallFadeConfig.faded_amount, faded) * float(steps))
	if wanted == level:
		return wrote
	level = wanted
	var amount := float(wanted) / float(steps)
	for part in parts:
		if is_instance_valid(part):
			MeshNodes.fade(part, amount)
	return true


## Give the parts their own shadow setting back (`casting`) or none; whether it wrote (only when
## that changed).
func _cast_shadows(casting: bool) -> bool:
	if casting != shadowless:
		return false
	shadowless = not casting
	for i in parts.size():
		if is_instance_valid(parts[i]):
			parts[i].cast_shadow = (
				casts[i] if casting else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
	return true
