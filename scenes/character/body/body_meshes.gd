extends RefCounted
## Character body: the parts of a body that are one polygon each (its limb segments, its shoulders,
## fists and head, its shoulders' floor shadow, a fallen trunk's faces) and its standing floor
## shadow (plain black shapes) drawn on a canvas item as meshes it keeps, instead of one polygon
## command each. Rendering windowed, the engine builds a vertex and an index buffer for every
## polygon command (a textured part, or General's `FillBatch` of plain shapes) and frees them the
## next frame (about 10 µs a polygon, a dozen or more a repaint); a mesh's buffers stay, and a
## repaint only writes the new corners and uvs into them. A part's mesh is cut into the triangles
## the engine itself cuts the polygon into (`Geometry2D.triangulate_polygon`) and drawn in the
## polygon's colour as its modulate (both full floats; a mesh's own vertex colours would be 8-bit),
## so it covers the same pixels in the same colours. A mesh is rebuilt only when its part's corner
## count or cut changes. Under the headless display (`enabled` false) nothing is rendered and a
## polygon command costs nothing: there each part is the polygon command.
##
## A canvas item draws all its commands again at every repaint, and only then: `begin` at the start
## of its draw hands its meshes out again from the first, so a mesh it still shows is never written
## until the draw that replaces it.

## Whether parts are drawn as kept meshes (else as polygon commands): not under the headless
## display, whose renderer draws nothing.
static var enabled := DisplayServer.get_name() != "headless"

## The canvas item the parts are drawn on.
var _canvas: CanvasItem
## Every mesh made so far, handed out in order at each draw.
var _slots: Array[Slot] = []
## How many of `_slots` this draw has handed out.
var _used := 0


## The parts drawn on `canvas`.
func _init(canvas: CanvasItem) -> void:
	_canvas = canvas


## Start a draw of the canvas: its meshes are handed out again from the first.
func begin() -> void:
	_used = 0


## How many meshes the canvas's last draw drew (tests read it).
func used() -> int:
	return _used


## Draw `poly` (canvas px) in `modulate`, `texture` mapped on by `uvs` (none: a plain polygon): the
## pixels `draw_colored_polygon(poly, modulate, uvs, texture)` draws. `bounds` holds the polygon
## (it places the mesh for culling and the lights); an empty one is measured. A polygon the engine
## cannot cut is drawn as that polygon command.
func draw(
	poly: PackedVector2Array,
	uvs: PackedVector2Array,
	texture: Texture2D,
	modulate := Color.WHITE,
	bounds := Rect2(),
) -> void:
	var cut := Geometry2D.triangulate_polygon(poly) if enabled else PackedInt32Array()
	if cut.is_empty():
		_canvas.draw_colored_polygon(poly, modulate, uvs, texture)
		return
	_canvas.draw_mesh(_next_mesh(poly, uvs, cut, bounds), texture, Transform2D.IDENTITY, modulate)


## A batch of plain shapes all in `color`, drawn on the canvas as one kept mesh (`Solid`).
func solid(color: Color) -> Solid:
	return Solid.new(_canvas, color, _next_mesh)


## The next kept mesh, holding `points` mapped by `uvs` (none: plain), cut into `cut`, within
## `bounds` (empty: measured), for the canvas to draw.
func _next_mesh(
	points: PackedVector2Array,
	uvs: PackedVector2Array,
	cut: PackedInt32Array,
	bounds: Rect2,
) -> ArrayMesh:
	if _used == _slots.size():
		_slots.append(Slot.new())
	var slot := _slots[_used]
	_used += 1
	slot.put(points, uvs, cut, bounds if bounds.has_area() else _measure(points))
	return slot.mesh


## The rect round `poly`.
static func _measure(poly: PackedVector2Array) -> Rect2:
	var out := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		out = out.expand(p)
	return out


## One kept mesh: its corners and uvs rewritten in place, rebuilt when the corner count, the cut or
## whether it has uvs changes. What has not changed since the last draw (a limb that did not move
## while another part did) is not written again: every write is a buffer copy on the GPU.
class Slot:
	extends RefCounted

	## Corners in 2D and per-corner uvs, both rewritable in place.
	const FLAGS := Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE | Mesh.ARRAY_FLAG_USE_2D_VERTICES

	## The mesh drawn, its one surface rewritten in place.
	var mesh := ArrayMesh.new()
	## The corner count, the triangles and whether it had uvs, as the mesh was built (none yet).
	var _corners := -1
	var _cut := PackedInt32Array()
	var _mapped := false
	## The corners, uvs and bounds it holds.
	var _poly := PackedVector2Array()
	var _uvs := PackedVector2Array()
	var _bounds := Rect2()

	## Hold `poly` mapped by `uvs` (none: plain), cut into `cut`, within `bounds`.
	func put(
		poly: PackedVector2Array,
		uvs: PackedVector2Array,
		cut: PackedInt32Array,
		bounds: Rect2,
	) -> void:
		var rid := mesh.get_rid()
		var mapped := not uvs.is_empty()
		if poly.size() != _corners or mapped != _mapped or cut != _cut:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = poly
			if mapped:
				arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = cut
			mesh.clear_surfaces()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, FLAGS)
			_corners = poly.size()
			_cut = cut
			_mapped = mapped
			_bounds = Rect2()  # A new surface: its bounds are set again.
		else:
			if poly != _poly:
				RenderingServer.mesh_surface_update_vertex_region(rid, 0, 0, poly.to_byte_array())
			if mapped and uvs != _uvs:
				RenderingServer.mesh_surface_update_attribute_region(rid, 0, 0, uvs.to_byte_array())
		_poly = poly
		_uvs = uvs
		if bounds != _bounds:
			RenderingServer.mesh_set_custom_aabb(
				rid,
				AABB(Vector3(bounds.position.x, bounds.position.y, 0.0),
					Vector3(bounds.size.x, bounds.size.y, 0.0)),
			)
			_bounds = bounds


## Plain shapes in one colour gathered as General's `FillBatch` gathers them (each polygon cut as
## the engine cuts it, a polygon the caller knows to be convex and `draw_circle`'s 64-gon fanned
## from their first corner, in the order added: `FillBatch.unit_circle()` and `FillBatch.fan()`),
## drawn by `flush` as one kept mesh in that colour.
## It takes `FillBatch`'s calls, so a drawing can hand either to the same helpers; the colour each
## shape is given must be the batch's.
class Solid:
	extends RefCounted

	## The canvas item the mesh is drawn on (and a polygon the engine cannot cut, by itself).
	var _canvas: CanvasItem
	## The colour every shape added must be, and the mesh's modulate.
	var _color: Color
	## (points, uvs, cut, bounds) -> ArrayMesh: the pool's next kept mesh, holding them.
	var _next_mesh: Callable
	## The corners and triangles gathered since the last `flush`.
	var _points := PackedVector2Array()
	var _indices := PackedInt32Array()

	func _init(canvas: CanvasItem, color: Color, next_mesh: Callable) -> void:
		_canvas = canvas
		_color = color
		_next_mesh = next_mesh

	## Add `poly` (canvas px), moved by `xform` first, as the engine cuts it. One it cannot cut is
	## drawn on its own, after what was added before it.
	func fill(poly: PackedVector2Array, color: Color, xform := Transform2D.IDENTITY) -> void:
		assert(color == _color, "a solid batch is all one colour")
		var placed := poly if xform == Transform2D.IDENTITY else xform * poly
		var tris := Geometry2D.triangulate_polygon(placed)
		if tris.is_empty():
			flush()
			_canvas.draw_colored_polygon(placed, _color)
			return
		var base := _points.size()
		for i in tris:
			_indices.append(base + i)
		_points.append_array(placed)

	## Add `poly` (canvas px), which the caller knows to be convex, moved by `xform` first, fanned
	## from its first corner.
	func fill_convex(poly: PackedVector2Array, color: Color, xform := Transform2D.IDENTITY) -> void:
		assert(color == _color, "a solid batch is all one colour")
		_add_fan(poly if xform == Transform2D.IDENTITY else xform * poly)

	## Add the disc `draw_circle(center, radius)` draws, moved by `xform` first.
	func circle(
		center: Vector2,
		radius: float,
		color: Color,
		xform := Transform2D.IDENTITY,
	) -> void:
		assert(color == _color, "a solid batch is all one colour")
		var disc := Transform2D(0.0, Vector2(radius, radius), 0.0, center)
		_add_fan(xform * disc * FillBatch.unit_circle())

	## Draw what was added as one kept mesh, `bounds` holding it (empty: measured), and start
	## again.
	func flush(bounds := Rect2()) -> void:
		if _indices.is_empty():
			return
		var mesh: ArrayMesh = _next_mesh.call(_points, PackedVector2Array(), _indices, bounds)
		_canvas.draw_mesh(mesh, null, Transform2D.IDENTITY, _color)
		_points = PackedVector2Array()
		_indices = PackedInt32Array()

	## Add the convex `placed` as a fan from its first corner.
	func _add_fan(placed: PackedVector2Array) -> void:
		_indices.append_array(FillBatch.fan(_points.size(), placed.size()))
		_points.append_array(placed)
