extends Node2D
## Test probe (not a test): the fields of a table piece the 3D table mesh reads (`size`, `color`,
## `look.art_opts`), without building a piece (`tests/objects/table_mesh_suite.gd`).

var size := Vector2(120, 70)
var color := Color(0.55, 0.35, 0.2)
var look := Look.new()


## The piece's look data: the painter's options.
class Look:
	var art_opts: Dictionary = {}
