class_name NavPieces extends RefCounted
## Navigation domain: the solid pieces (RigidBody2D) under one house and the footprint each was
## last cut to, so a tick of `NavBuilder.furniture_holes` reads one transform a piece and cuts only
## those that moved, were dented (their colliders rebuilt: a child shape came or went) or were
## added; the tree is walked again only when a piece was added or has left. One tracker per house,
## made by the first ask and dropped when the house leaves the tree (`of`).

## The trackers made, house instance id -> `NavPieces`.
static var _trackers: Dictionary = {}

## The house, its instance id and the tree it stands in.
var _house: Node2D
var _house_id := 0
var _tree: SceneTree
## The pieces in the order a walk of the house's descendants finds them, each `Piece`.
var _pieces: Array = []
## Piece by its body's instance id.
var _by_id: Dictionary = {}
## Whether a piece was added or left since the pieces were listed.
var _relist := true


## The tracker of `house`, made on first use. `house` must stand in the tree.
static func of(house: Node2D) -> NavPieces:
	var id := house.get_instance_id()
	var kept: NavPieces = _trackers.get(id)
	if kept != null:
		return kept
	for old in _trackers.keys():
		if not is_instance_id_valid(old):
			(_trackers[old] as NavPieces).drop()
	var made := NavPieces.new()
	made._house = house
	made._house_id = id
	made._tree = house.get_tree()
	_trackers[id] = made
	made._tree.node_added.connect(made._on_node_added)
	house.tree_exited.connect(made.drop, CONNECT_ONE_SHOT)
	return made


## The footprint of every piece under the house, in the order a walk of its descendants finds them,
## then the doors' leaves standing clear of their doorways (`NavLeaves.hole`).
func holes() -> Array:
	if _relist:
		_list()
	var out: Array = []
	for piece: Piece in _pieces:
		var at := piece.body.global_transform
		if piece.dirty or at != piece.at:
			piece.at = at
			piece.hull = NavHoles.cut(piece.body)
			piece.dirty = false
		if not piece.hull.is_empty():
			out.append(piece.hull)
	NavHoles.add_leaves(out, _house)
	return out


## Forget the house: the connections go and the next ask makes a fresh tracker.
func drop() -> void:
	_trackers.erase(_house_id)
	if _tree != null and _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.disconnect(_on_node_added)
	for piece: Piece in _pieces:
		piece.release(_on_left)
	_pieces.clear()
	_by_id.clear()
	_relist = true


## The pieces under the house listed again, those already known kept as they are.
func _list() -> void:
	_relist = false
	NavHoles.walks += 1
	var known := _by_id
	_by_id = {}
	_pieces = []
	for node in _house.find_children("*", "RigidBody2D", true, false):
		var id := node.get_instance_id()
		var piece: Piece = known.get(id)
		if piece == null:
			piece = Piece.new(node)
			node.child_order_changed.connect(piece.dirtied)
			node.tree_exiting.connect(_on_left)
		_by_id[id] = piece
		_pieces.append(piece)


## A piece left the tree.
func _on_left() -> void:
	_relist = true


## A node entered the tree: a piece under the house is to be listed.
func _on_node_added(node: Node) -> void:
	if node is RigidBody2D and is_instance_valid(_house) and _house.is_ancestor_of(node):
		_relist = true


## A piece: its body, where it stood and the footprint cut then; `dirty` until it is cut, and again
## whenever its colliders change.
class Piece:
	var body: RigidBody2D
	var at := Transform2D()
	var hull := PackedVector2Array()
	var dirty := true

	func _init(piece_body: RigidBody2D) -> void:
		body = piece_body

	## A child of the body came, went or moved: its colliders may have been rebuilt.
	func dirtied() -> void:
		dirty = true

	## Leave the body's signals: `left` is the tracker's callback for it leaving the tree.
	func release(left: Callable) -> void:
		if not is_instance_valid(body):
			return
		if body.child_order_changed.is_connected(dirtied):
			body.child_order_changed.disconnect(dirtied)
		if body.tree_exiting.is_connected(left):
			body.tree_exiting.disconnect(left)
