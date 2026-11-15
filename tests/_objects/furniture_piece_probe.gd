extends Node2D
## Test probe (not a test): the fields of a furniture piece the 3D furniture meshes read (`size`,
## `color`, `look.art_opts` and `look.facing`), without building a piece
## (`tests/objects/furniture_mesh_suite.gd`).

var size := Vector2(100, 60)
var color := Color(0.55, 0.35, 0.2)
var look := Look.new()


## The piece's look data: the painter's options and the way it faces.
class Look:
	var art_opts: Dictionary = {}
	var facing := Vector2.DOWN
