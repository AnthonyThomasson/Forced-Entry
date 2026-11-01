extends Node2D
## Vision domain (private): the view's polygons drawn as triangle fans in world coordinates, a fan
## from the eye to each pair of neighbouring ray ends (so a run of ray ends along one wall never
## fails to triangulate). Two painters are made of it: the memory's, whose vertices are textured
## with the capture (a vertex's coordinate is where its world point is on the capture: the camera's
## transform over the capture's size), and the mask's, whose vertex colour is the mask value and
## which draws the polygon once per entry of `offsets` (a disc of shifts, to feather the edge).

## World-unit shifts the polygon is drawn at; one zero entry draws it once, in place.
var offsets := PackedVector2Array([Vector2.ZERO])
## The vertex colour (the mask's value per draw).
var color := Color.WHITE
## The texture the polygon is drawn with (the capture), or null to draw it in vertex colour alone.
var texture: Texture2D
var _points := PackedVector2Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _colors := PackedColorArray()


func _draw() -> void:
	if _indices.is_empty():
		return
	var rid := texture.get_rid() if texture != null else RID()
	for shift in offsets:
		draw_set_transform(shift)
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(),
			_indices,
			_points,
			_colors,
			_uvs,
			PackedInt32Array(),
			PackedFloat32Array(),
			rid,
		)


## Rebuild the triangles from the `cone` (the eye, then one corner per ray) and the `bubble` (one
## corner per ray round `eye`), and redraw. With a texture, a point's coordinate is `view` (the
## camera's canvas transform) of it over `view_size` (the capture's size).
func refresh(
	cone: PackedVector2Array,
	bubble: PackedVector2Array,
	eye: Vector2,
	view: Transform2D,
	view_size: Vector2,
) -> void:
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
	_uvs.resize(count)
	if texture != null:
		for i in count:
			_uvs[i] = (view * _points[i]) / view_size
	queue_redraw()


## Draw nothing until the next `refresh`.
func clear() -> void:
	_indices.clear()
	queue_redraw()


## The corners drawn: the cone's, then the eye and the bubble's.
func points() -> PackedVector2Array:
	return _points


## Where each of `points()` is on the texture.
func uvs() -> PackedVector2Array:
	return _uvs
