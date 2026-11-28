class_name NavPieces extends RefCounted
## Navigation domain: the pieces (the plan handles of `TwinSpace.PIECES`) under one house and the
## footprint each was last cut to, so a tick of `NavBuilder.furniture_holes` reads one transform a
## piece and cuts only those whose twin moved or were twinned or added; the tree is walked again
## only when a piece was added or has left. One tracker per house, made by the first ask and dropped
## when the house leaves the tree (`of`).

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


## The pieces under `house` (`TwinSpace.PIECES`), in the order a walk of its descendants finds them
## (tree order). Read from the group, not a walk of every node under the house.
static func under(house: Node2D) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if not house.is_inside_tree():
		for node in house.find_children("*", "Node2D", true, false):
			if node.is_in_group(TwinSpace.PIECES):
				out.append(node)
		return out
	for node in house.get_tree().get_nodes_in_group(TwinSpace.PIECES):
		if house.is_ancestor_of(node):
			out.append(node as Node2D)
	out.sort_custom(func(a: Node, b: Node) -> bool: return b.is_greater_than(a))
	return out


## The footprint of every piece under the house, in the order a walk of its descendants finds them,
## then the doors' leaves standing clear of their doorways (`NavLeaves.hole`).
func holes() -> Array:
	var read := reader()
	while not read.step(1 << 30, 1 << 30):
		pass
	return read.walked()


## A reading of the footprints in steps (`Reader.step`) with a cursor of its own, so another
## caller's `holes` during a tick's steps leaves them alone. The pieces are listed again when one
## was added or has left.
func reader() -> Reader:
	if _relist:
		_list()
	return Reader.new(self, _pieces)


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
	for node in under(_house):
		var id := node.get_instance_id()
		var piece: Piece = known.get(id)
		if piece == null:
			piece = Piece.new(node)
			node.tree_exiting.connect(_on_left)
		_by_id[id] = piece
		_pieces.append(piece)
	for id in known:
		if not _by_id.has(id):
			(known[id] as Piece).release(_on_left)  # left the house without being freed


## A piece left the tree.
func _on_left() -> void:
	_relist = true


## A node entered the tree: a piece under the house is to be listed.
func _on_node_added(node: Node) -> void:
	if (node.is_in_group(TwinSpace.PIECES)
			and is_instance_valid(_house)
			and _house.is_ancestor_of(node)):
		_relist = true


## A piece: its body, what its footprint depended on when it was cut (`NavTwins.stamp_of`) and the
## footprint cut then; `dirty` until it is cut.
class Piece:
	var body: Node2D
	var stamp: Variant = null
	var hull := PackedVector2Array()
	var dirty := true

	func _init(piece_body: Node2D) -> void:
		body = piece_body

	## Leave the body's signals: `left` is the tracker's callback for it leaving the tree.
	func release(left: Callable) -> void:
		if not is_instance_valid(body):
			return
		if body.tree_exiting.is_connected(left):
			body.tree_exiting.disconnect(left)


## One reading of the footprints, a few pieces a step: the pieces as they were listed when it began
## (`NavPieces.reader`), how far it has got and what it holds.
class Reader:
	var _owner: NavPieces
	var _pieces: Array
	var _at := 0
	var _walked: Array = []

	func _init(owner: NavPieces, pieces: Array) -> void:
		_owner = owner
		_pieces = pieces

	## Read the next pieces, up to `scan` of them and up to `cuts` footprints cut afresh, whichever
	## comes first; true once every piece is read and the doors' leaves added, the footprints being
	## `walked`.
	func step(scan: int, cuts: int) -> bool:
		var cut := 0
		var stop := mini(_at + scan, _pieces.size())
		while _at < stop and cut < cuts:
			var piece: Piece = _pieces[_at]
			_at += 1
			if not is_instance_valid(piece.body):
				continue  # freed meanwhile: the next listing drops it
			var stamp: Variant = NavTwins.stamp_of(piece.body)
			if piece.dirty or stamp != piece.stamp:
				piece.stamp = stamp
				piece.hull = NavHoles.cut(piece.body)
				piece.dirty = false
				cut += 1
			if not piece.hull.is_empty():
				_walked.append(piece.hull.duplicate())  # a caller's edit stays its own
		if _at < _pieces.size():
			return false
		NavLeaves.append_holes(_walked, _owner._house)
		return true

	## The footprints read so far (all of them once `step` has returned true).
	func walked() -> Array:
		return _walked
