extends RefCounted
## Art domain, the carrier's still meshes (`mesh_carrier.gd`, interface 27): the rows with no
## `mirror_update`, no turn and no rider, of bodies the player's view remembers. While such a body
## is off `ViewLayers.MOVING`, nothing but its own `visible` says whether its mesh shows, so a frame
## asks only that, of every row, from flat arrays: a district stands over a thousand of them, and
## the carrier's full look at each costs it several times as much. `changed()` gives the rows that
## need the full look; the carrier says `looked(row)` after it.

## What is remembered of a row that is looked at every frame whatever its body says: one marked
## moving, whose mark has to come off again.
const LOOK := 2

## The rows, and by the same place: the body, the mesh, and the body's `visible` the mesh was last
## shown by (0, 1, or `LOOK`).
var _rows: Array[Dictionary] = []
var _bodies: Array = []
var _meshes: Array = []
var _shown := PackedByteArray()


## How many rows it holds.
func size() -> int:
	return _rows.size()


## Hold `row` (`MeshKinds.row_of`).
func add(row: Dictionary) -> void:
	row["slot"] = _rows.size()
	_rows.append(row)
	_bodies.append(row["body"])
	_meshes.append(row["node"])
	_shown.append(0)
	looked(row)


## Let `row` go (a row it does not hold is left alone).
func remove(row: Dictionary) -> void:
	var at: int = row.get("slot", -1)
	if at < 0:
		return
	row.erase("slot")
	var last := _rows.size() - 1
	if at != last:
		_rows[at] = _rows[last]
		_rows[at]["slot"] = at
		_bodies[at] = _bodies[last]
		_meshes[at] = _meshes[last]
		_shown[at] = _shown[last]
	_rows.resize(last)
	_bodies.resize(last)
	_meshes.resize(last)
	_shown.resize(last)


## `row` was looked at: remember what it showed.
func looked(row: Dictionary) -> void:
	var at: int = row.get("slot", -1)
	if at >= 0:
		_shown[at] = LOOK if row["moving"] else int(row["shown"])


## The rows that need the carrier's full look this frame: the body or the mesh is gone, the body
## moves (`ViewLayers.MOVING`: the cone decides) or its `visible` is not what the mesh shows.
func changed() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in _rows.size():
		var body: Variant = _bodies[i]
		if (
			not is_instance_valid(body)
			or not is_instance_valid(_meshes[i])
			or body.visibility_layer & ViewLayers.MOVING
			or int(body.visible) != _shown[i]
		):
			out.append(_rows[i])
	return out
