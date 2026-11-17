class_name StreetGround
extends RefCounted
## Objects domain, how far below the pavement a spot of the street lies in the 3D render
## (`domain-objects/meshes.md`): the road is a slab `ObjectStreetMeshConfig.kerb` px lower than the
## pavement and the floors, so a thing that lies on the ground (a splat of blood, a chip, a scorch)
## has to be put that much lower there. `StreetMesh` shows each road floor (a `Floor` of art
## `street` whose `art_opts.kind` is not `sidewalk`) over its whole `size` from its corner; this
## reads those same rects, duck-typed, and answers for any spot: `offset_at`. Main builds one and
## hands `offset_at` to the effects that lie on the ground (Physics' `PhysicsMeshes.install`), which
## so need import nothing of the street. The rects are put in a coarse grid, so a lookup is a few
## rect tests however many roads there are.

## Side (px) of a cell of the grid.
const CELL := 128.0

## Every cell of the grid (`Vector2i`) and the road rects that reach it.
var _grid := {}
## How many road rects were found.
var _roads := 0


## Read the road floors under `root` (the match's world): the rects come from the floors group, as
## `WorldMirror` finds them. Call it again after floors were added.
func refresh(root: Node) -> void:
	_grid.clear()
	_roads = 0
	for node: Node in root.get_tree().get_nodes_in_group(&"floors"):
		if root.is_ancestor_of(node) and is_road(node):
			_add(Rect2((node as Node2D).global_position, node.get("size")))


## How many road rects are known.
func roads() -> int:
	return _roads


## The height (px, 0 on the pavement, `-kerb` on the road) of the ground at world `at`.
func offset_at(at: Vector2) -> float:
	var rects: Variant = _grid.get(Vector2i((at / CELL).floor()))
	if rects == null:
		return 0.0
	for rect: Rect2 in rects:
		if rect.has_point(at):
			return -ObjectStreetMeshConfig.kerb
	return 0.0


## Whether `node` is a road: a floor of art `street` that is not the sidewalk.
static func is_road(node: Node) -> bool:
	if not node is Node2D or MirrorProxy.art_of(node) != "street":
		return false
	var opts: Variant = node.get("art_opts")
	return node.get("size") is Vector2 and not (
		opts is Dictionary and String((opts as Dictionary).get("kind", "asphalt")) == "sidewalk"
	)


## Put `rect` in every cell it reaches.
func _add(rect: Rect2) -> void:
	_roads += 1
	var first := Vector2i((rect.position / CELL).floor())
	var last := Vector2i((rect.end / CELL).floor())
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			var cell := Vector2i(x, y)
			if not _grid.has(cell):
				_grid[cell] = []
			_grid[cell].append(rect)
