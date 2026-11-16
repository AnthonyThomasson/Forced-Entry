extends Node2D
## Vision domain (private): the view's polygons drawn as triangle fans in world coordinates, a fan
## from the eye to each pair of neighbouring ray ends (so a run of ray ends along one wall never
## fails to triangulate). Two painters are made of it (`ViewGround`): the seen mask's and the live
## mask's, whose vertex colour is the mask value and which draws the polygon once per entry of
## `offsets` (a disc of shifts, to feather the edge).

## World-unit shifts the polygon is drawn at; one zero entry draws it once, in place.
var offsets := PackedVector2Array([Vector2.ZERO])
## The vertex colour (the mask's value per draw).
var color := Color.WHITE
var _points := PackedVector2Array()
var _indices := PackedInt32Array()
var _colors := PackedColorArray()


func _draw() -> void:
	if _indices.is_empty():
		return
	for shift in offsets:
		draw_set_transform(shift)
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(),
			_indices,
			_points,
			_colors,
			PackedVector2Array(),
			PackedInt32Array(),
			PackedFloat32Array(),
			RID(),
		)


## Rebuild the triangles from the `cone` (the eye, then one corner per ray) and the `bubble` (one
## corner per ray round `eye`), and redraw.
func refresh(cone: PackedVector2Array, bubble: PackedVector2Array, eye: Vector2) -> void:
	var cone_n := cone.size() if cone.size() >= 3 else 0
	var ring := bubble.size() if bubble.size() >= 3 else 0
	var count := cone_n + (ring + 1 if ring > 0 else 0)
	_points.resize(count)
	for i in cone_n:
		_points[i] = cone[i]
	if ring > 0:
		_points[cone_n] = eye
		for i in ring:
			_points[cone_n + 1 + i] = bubble[i]
	_indices.resize(maxi(cone_n - 2, 0) * 3 + ring * 3)
	var at := 0
	for k in maxi(cone_n - 2, 0):
		_indices[at] = 0
		_indices[at + 1] = 1 + k
		_indices[at + 2] = 2 + k
		at += 3
	for k in ring:
		_indices[at] = cone_n
		_indices[at + 1] = cone_n + 1 + k
		_indices[at + 2] = cone_n + 1 + (k + 1) % ring
		at += 3
	_colors.resize(count)
	_colors.fill(color)
	queue_redraw()


## Draw nothing until the next `refresh`.
func clear() -> void:
	_indices.clear()
	queue_redraw()


## The corners drawn: the cone's, then the eye and the bubble's.
func points() -> PackedVector2Array:
	return _points
