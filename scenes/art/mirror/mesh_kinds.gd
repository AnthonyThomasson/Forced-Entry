class_name MeshKinds
extends RefCounted
## Art domain, the kinds of body a mesh is built for and the key a builder is registered under (the
## mesh hook of `MeshCarrier.builders`, interface 27): `kind_of` sorts a body by the group or
## property its owning domain gives it (read duck-typed, so Art imports nothing from the domains
## that own them), `furniture_key` and `floor_key` name a finer key for one art id, `art_of` reads
## it. `row_of` makes the row the carrier keeps for a mesh.

## The kinds a body is sorted into (`kind_of`): the hook of `MeshCarrier.builders` is keyed by them.
const WALL := &"wall"
const DOOR := &"door"
const CHARACTER := &"character"
const VEHICLE := &"vehicle"
const FURNITURE := &"furniture"
const FLOOR := &"floor"


## The kind of `body`: a floor, character, vehicle, door or wall by what it says it is (the group or
## the property the owning domain gives it), else a piece of furniture.
static func kind_of(body: Node) -> StringName:
	if body.is_in_group(&"floors"):
		return FLOOR
	if body.is_in_group(&"characters"):
		return CHARACTER
	if body.is_in_group(&"vehicles"):
		return VEHICLE
	if body.is_in_group(&"doors"):
		return DOOR
	if body.get("wall_thickness") != null:
		return WALL
	return FURNITURE


## The hook key of the furniture painted by `art` (an `ObjectArt` id): a builder under it wins over
## the `FURNITURE` kind's, for a piece of that art alone.
static func furniture_key(art: String) -> StringName:
	return StringName("%s:%s" % [FURNITURE, art])


## The hook key of the floor painted by `art`: a builder under it wins over `FLOOR`'s.
static func floor_key(art: String) -> StringName:
	return StringName("%s:%s" % [FLOOR, art])


## The art id of `node`, read duck-typed: a piece's `look.art`, a floor's `art`; "" for a node that
## names none.
static func art_of(node: Node) -> String:
	var look: Variant = node.get("look")
	if look is Object and (look as Object).get("art") is String:
		return (look as Object).get("art")
	var own: Variant = node.get("art")
	return own if own is String else ""


## The row of a mesh a domain's builder made for `body` (`MeshCarrier.builders`): `node` the mesh,
## `body` the 2D body it shows, `shapes` the body's own collision shapes (while all are disabled the
## mesh hides: `shapes_all_off`), `update` the mesh's `mirror_update(body)` when it has one (else an
## invalid `Callable`), `shown` whether it shows now.
static func row_of(body: Node2D, node: Node3D) -> Dictionary:
	var shapes: Array[Node] = []
	for child in body.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			shapes.append(child)
	return {
		"node": node, "body": body, "id": body.get_instance_id(), "shown": true,
		"moving": false, "shapes": shapes,
		"update": Callable(node, &"mirror_update") if node.has_method(&"mirror_update")
		else Callable(),
	}


## Whether `row` is the mesh of a body that has collision shapes and every one is disabled (a
## character seated in a vehicle): such a mesh has no shape of its own to be disabled. A body with
## no shape is not.
static func shapes_all_off(row: Dictionary) -> bool:
	var any := false
	for shape: Variant in row.get("shapes", []):
		if not is_instance_valid(shape) or (shape as Node).is_queued_for_deletion():
			continue
		any = true
		if (shape as Node).get("disabled") != true:
			return false
	return any
