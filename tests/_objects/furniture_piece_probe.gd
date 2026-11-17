extends Node2D
## Test probe (not a test): the fields of a furniture piece the 3D furniture meshes read (`size`,
## `color` and the piece's own `look`: `art_opts`, `facing`, `overhang`), without building a piece
## (`tests/objects/furniture_mesh_suite.gd`).

const ObjectLook := preload("res://scenes/objects/object_look.gd")

var size := Vector2(100, 60)
var color := Color(0.55, 0.35, 0.2)
var look := ObjectLook.new()
