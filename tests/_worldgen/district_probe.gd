extends RefCounted
## Shared reads of the district tests (not a test itself):
## `const District := preload("res://tests/_worldgen/district_probe.gd")`. The numbers are the
## spec's own (the ticket's 3 x 3 grid with the house in the centre block), not the code's.

## Where a district's house front door is put by the tests that do not care.
const ENTRANCE := Vector2(6000, 6000)
## The grid is `GRID` blocks on a side; the house is block `HOUSE_BLOCK`, the centre one.
const GRID := 3
const HOUSE_BLOCK := 4


## Whether some piece of `pieces` (street pieces: `{ kind, rect, ... }`) of `kind` (any if "")
## holds `p`, each piece's rect grown by `slack` px.
static func covered(pieces: Array, p: Vector2, kind := "", slack := 0.0) -> bool:
	return pieces.any(
		func(piece: Dictionary) -> bool:
			return (
				(kind == "" or piece["kind"] == kind)
				and (piece["rect"] as Rect2).grow(slack).has_point(p)
			),
	)


## The piece of `pieces` holding `p`, or {}.
static func piece_at(pieces: Array, p: Vector2) -> Dictionary:
	for piece: Dictionary in pieces:
		if (piece["rect"] as Rect2).has_point(p):
			return piece
	return {}


## What a district's tree is, node by node, for comparing two builds of one seed: one line per
## Node2D below `root` (not `root` itself: two roots under one parent cannot share a name) (depth
## first), its path of names (a node the engine named itself, `@Node2D@7`, by its class), its place,
## turn and scale. Furniture, lamps, clutter, awnings, signs, podiums and shell decor are all nodes
## of the tree, so they are all in it.
static func digest(root: Node) -> PackedStringArray:
	var lines := PackedStringArray()
	for child in root.get_children():
		_digest_of(child, "", lines)
	return lines


## The lines of `node` and what is under it, `path` the names above it.
static func _digest_of(node: Node, path: String, lines: PackedStringArray) -> void:
	var named := String(node.name)
	var here := "%s/%s" % [path, node.get_class() if named.begins_with("@") else named]
	if node is Node2D:
		var item := node as Node2D
		var place := item.global_position.snappedf(0.01)
		lines.append("%s|%s|%.4f|%s" % [here, place, item.rotation, item.scale])
	for child in node.get_children():
		_digest_of(child, here, lines)


## The first line where digests `a` and `b` differ, or "" when they are the same.
static func first_difference(a: PackedStringArray, b: PackedStringArray) -> String:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return "line %d: %s  vs  %s" % [i, a[i], b[i]]
	if a.size() != b.size():
		return "%d lines against %d" % [a.size(), b.size()]
	return ""
