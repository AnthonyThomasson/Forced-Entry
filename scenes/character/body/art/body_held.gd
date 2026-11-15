class_name BodyHeld
extends RefCounted
## Character body, the held item on the 3D body (`body_mesh.gd`; #193 phase 2): the one node that
## shows what the character holds, by the mesh the held item's art gives (`item.art.held_mesh()`,
## Items: sized and coloured from the item's config row, shared by kind and look). It follows the
## item's identity and weapon style (the node's mesh is swapped only when one changed), is hidden
## for an item with no mesh (fists, an empty hand, a key) and for a dead body, and is placed at the
## weapon hand's joint pointing where the 2D art draws the weapon, pitched up as the weapon is
## raised off a wall. It writes nothing itself: `BodyMesh` samples it with the joints and places it
## only when one of them moved.

## The node showing the item (a figure for the pixel post, no shadow: too small to be worth one).
var node: MeshInstance3D
## The hand that holds the item (`Item.weapon_hand`).
var hand := 0
## Set when the item (or its style) just changed: the body places the node again, then clears it.
var swapped := false
## The held item (an instance id, 0 for none) and its weapon style.
var _id := 0
var _style := &""


func _init() -> void:
	node = MeshNodes.instance(null, Color.WHITE, false)
	MeshNodes.figure(node)
	node.visible = false


## What the character of `body` holds now (nothing once `dead`), as a sample: the flat direction the
## item points along (x, y) and how far it is pitched up (z, radians). The node shows the item's
## mesh, swapped when the item or its style changed.
func sample(body: Node2D, dead: bool) -> Vector3:
	var item: Item = null if dead else body.inventory.current_item()
	var id := item.get_instance_id() if item != null else 0
	var style: StringName = item.art.style if item != null else &""
	if id != _id or style != _style:
		_id = id
		_style = style
		var mesh: Mesh = item.art.held_mesh() if item != null else null
		node.mesh = mesh
		node.visible = mesh != null
		hand = item.weapon_hand() if item != null else 0
		swapped = true
	if not node.visible:
		return Vector3.ZERO
	var aim: Vector2 = item.art.held_aim(body)
	return Vector3(aim.x, aim.y, item.art.held_lift(body))


## The node at `at` (the weapon hand's joint, 3D px), its muzzle along `aim` (a `sample`) and
## pitched up by its lift.
func place(aim: Vector3, at: Vector3) -> void:
	if not node.visible:
		return
	var along := Vector3(aim.x, 0.0, aim.y)
	var forward := along * cos(aim.z) + Vector3.UP * sin(aim.z)
	var up := Vector3.UP * cos(aim.z) - along * sin(aim.z)
	node.transform = Transform3D(Basis(up.cross(forward), up, forward), at * RenderConfig.unit)
