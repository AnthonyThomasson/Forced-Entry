extends RefCounted
## Art domain, the carrier's still meshes (`mesh_carrier.gd`, interface 27): the rows with no
## `mirror_update`, no turn and no rider, of bodies the player's view remembers. While such a body
## is off `ViewLayers.MOVING`, nothing but its own `visible` says whether its mesh shows, so none is
## looked at each frame: a district stands over a thousand of them, and even asking each costs. A
## row is woken by a signal instead: the body's `visibility_changed`, its view layer changed
## (`ViewLayers.CHANGED`) and the mesh leaving the tree (freed, with its twin or alone, or moved to
## another). `changed()` gives the woken rows for the carrier's full look; the carrier says
## `looked(row)` after it, and a row that needs a look every frame (its body on `MOVING`, its mesh
## marked moving or out of the tree) stays woken.

## The rows held, by their key (`row["still"]`), with what their signals are connected to.
var _rows: Dictionary = {}
## The keys of the rows to look at next.
var _woken: Dictionary = {}
var _next := 0


## How many rows it holds.
func size() -> int:
	return _rows.size()


## Hold `row` (`MeshKinds.row_of`), just shown by the rules.
func add(row: Dictionary) -> void:
	var body := row["body"] as Node2D
	var mesh := row["node"] as Node3D
	_next += 1
	row["still"] = _next
	row["wake"] = _wake.bind(_next)
	_rows[_next] = row
	if not body.has_user_signal(ViewLayers.CHANGED):
		body.add_user_signal(ViewLayers.CHANGED)
	body.connect(ViewLayers.CHANGED, row["wake"])
	body.visibility_changed.connect(row["wake"])
	mesh.tree_exiting.connect(row["wake"])
	looked(row)


## Let `row` go (a row it does not hold is left alone).
func remove(row: Dictionary) -> void:
	var key: int = row.get("still", 0)
	if key == 0:
		return
	var wake: Callable = row["wake"]
	var body: Variant = row["body"]  # untyped: may be freed
	if is_instance_valid(body):
		(body as Node2D).disconnect(ViewLayers.CHANGED, wake)
		(body as Node2D).visibility_changed.disconnect(wake)
	var mesh: Variant = row["node"]
	if is_instance_valid(mesh):
		(mesh as Node).tree_exiting.disconnect(wake)
	_rows.erase(key)
	_woken.erase(key)
	row.erase("still")
	row.erase("wake")


## `row` was looked at: keep it woken if it needs the next frame's look too.
func looked(row: Dictionary) -> void:
	var key: int = row.get("still", 0)
	if key == 0:
		return
	var body := row["body"] as Node2D
	if (
		row["moving"]
		or body.visibility_layer & ViewLayers.MOVING
		or not (row["node"] as Node).is_inside_tree()
	):
		_woken[key] = true


## The rows that need the carrier's full look now, each one asleep again until it is woken or
## `looked` keeps it awake.
func changed() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _woken.is_empty():
		return out
	for key: int in _woken:
		out.append(_rows[key])
	_woken.clear()
	return out


## The row of `key` is looked at next, if it is still held.
func _wake(key: int) -> void:
	if _rows.has(key):
		_woken[key] = true
