class_name MeshKit
extends RefCounted
## Art domain, the 3D mesh kit (interface 12, `domain-art/meshes.md`; #193 phase 2): code-built
## low-poly solids a domain's mesh builder composes a piece from, the way a painter composes a
## texture from `PixelCanvas` shapes. A kit collects faces and `build()` makes one `ArrayMesh`:
## flat-shaded (a face is its own vertices and normal) with one colour per face in the vertex
## colour (the toon material multiplies it by the instance's `base_color`, white by default), so a
## table's top and its legs are one mesh and one draw.
##
## **Units.** Every method works in the art's own units: a footprint in 2D px (`x`, `y` of the
## piece's frame, `y` down the screen) and a height in px above the ground (`base` the height of
## the solid's underside, `height` how tall it stands). `build()` converts to 3D units with
## `RenderConfig.unit` in this one place (2D `(x, y)` is 3D `(x, height, y)`), so a domain never
## multiplies by the unit itself. Colours are the art's colours (sRGB); a face's tone is a pick of
## `ArtSurfaceConfig.tones` (`tone`), the toon material does the banding.
##
## Build a mesh once per distinct piece: `MeshCache.fetch` shares it between every piece asking
## for the same inputs. `MeshNodes.instance` puts it on a node in the shared toon material.
##
## Each method returns the kit, so a piece reads as a chain.

## A top colour that means "the same as the sides".
const SAME := Color(0, 0, 0, 0)

## How many flat faces a cylinder has (0: `MeshKitConfig.cylinder_sides`).
var sides := 0
## The faces so far, as triangles (3 entries each) in px space: x, height, y.
var _points := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


## The tone `name` (`outline`, `shadow`, `dark`, `base`, `light`, `highlight`) of
## `ArtSurfaceConfig.tones(base)`: the colour a darker or lighter face of a piece takes.
static func tone(base: Color, name: StringName) -> Color:
	return ArtSurfaceConfig.tones(base)[String(name)]


## The volume over `footprint` (2D px), its underside `base` px above the ground and `height` px
## tall, as the box the solids below take (`position` is `(x, base, y)`, `size` `(width, height,
## depth)`).
static func volume(footprint: Rect2, base: float, height: float) -> AABB:
	return AABB(
		Vector3(footprint.position.x, base, footprint.position.y),
		Vector3(footprint.size.x, height, footprint.size.y),
	)


## An axis-aligned box filling `box` (`volume`). `color` the sides and the underside, `top_color`
## the top (`SAME`: `color`).
func box(box_volume: AABB, color: Color, top_color := SAME) -> MeshKit:
	var top := _or(top_color, color)
	var lo := box_volume.position
	var hi := box_volume.end
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		for far in [false, true]:
			var normal: Vector3 = axis if far else -axis
			var origin: Vector3 = (hi if far else lo) * axis + lo * (Vector3.ONE - axis)
			var across: Vector3 = (hi - lo) * (Vector3.ONE - axis)
			var spans := _spans(across)
			if spans.size() < 2:
				continue
			_quad([
				origin, origin + spans[0], origin + spans[0] + spans[1], origin + spans[1],
			], normal, top if normal == Vector3.UP else color)
	return self


## A wedge (a ramp, a headboard, half a pitched roof) filling `wedge_volume` (`volume`): as tall as
## the volume along the edge on the `rises_toward` side (a cardinal direction in 2D) and a knife
## edge at the opposite one, so its top slopes. `color` the sides, `top_color` the slope.
func wedge(wedge_volume: AABB, rises_toward: Vector2, color: Color, top_color := SAME) -> MeshKit:
	var frame := _wedge_frame(wedge_volume, rises_toward)
	var size := (frame.basis.transposed() * wedge_volume.size).abs()  # run, height, width
	var lift := Vector3.UP * size.y
	var low_a := frame * Vector3.ZERO
	var low_b := frame * Vector3(0.0, 0.0, size.z)
	var high_a := frame * Vector3(size.x, 0.0, 0.0)
	var high_b := frame * Vector3(size.x, 0.0, size.z)
	var rise := frame.basis.x
	var slope := (Vector3.UP * size.x - rise * size.y).normalized()
	_quad([low_a, low_b, high_b, high_a], Vector3.DOWN, color)
	_quad([high_a, high_b, high_b + lift, high_a + lift], rise, color)
	_quad([low_a, low_b, high_b + lift, high_a + lift], slope, _or(top_color, color))
	_tri([low_a, high_a, high_a + lift], -frame.basis.z, color)
	_tri([low_b, high_b, high_b + lift], frame.basis.z, color)
	return self


## An upright cylinder of `radius` px standing at `at` (`x`, the height of its underside, `y`),
## `height` tall, `sides` flat faces round (0: `MeshKitConfig.cylinder_sides`), `top_color` its lid.
func cylinder(at: Vector3, radius: float, height: float, color: Color,
		top_color := SAME) -> MeshKit:
	var count := sides if sides >= 3 else MeshKitConfig.cylinder_sides
	var ring := PackedVector2Array()
	for i in count:
		var angle := TAU * float(i) / float(count)
		ring.append(Vector2(at.x, at.z) + Vector2(cos(angle), sin(angle)) * radius)
	return extrude(ring, at.y, height, color, top_color)


## A solid with a flat top and bottom and `polygon` (2D px, convex or not, either way round) for a
## footprint, `height` px tall over `base`: a rounded table top, an L-shaped counter, a plate.
func extrude(polygon: PackedVector2Array, base: float, height: float, color: Color,
		top_color := SAME) -> MeshKit:
	if polygon.size() < 3:
		return self
	var top := _or(top_color, color)
	var triangles := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, triangles.size(), 3):
		var corners := [polygon[triangles[i]], polygon[triangles[i + 1]], polygon[triangles[i + 2]]]
		_tri(_lifted(corners, base + height), Vector3.UP, top)
		_tri(_lifted(corners, base), Vector3.DOWN, color)
	var counter_clockwise := _area(polygon) > 0.0
	for i in polygon.size():
		var from := polygon[i]
		var to := polygon[(i + 1) % polygon.size()]
		var edge := to - from
		var outward := Vector2(edge.y, -edge.x) if counter_clockwise else Vector2(-edge.y, edge.x)
		_quad([
			Vector3(from.x, base, from.y), Vector3(to.x, base, to.y),
			Vector3(to.x, base + height, to.y), Vector3(from.x, base + height, from.y),
		], Vector3(outward.x, 0.0, outward.y).normalized(), color)
	return self


## `profile` (a convex outline in px, `x` across the path and `y` up) swept along `path` (px points:
## `x`, height, `y`), the way a pipe, a rail, a handle or a car's roof line is made. Both ends are
## closed. The profile turns with the path's heading; a path that runs straight up has none, so it
## keeps the x axis as across.
func loft(path: PackedVector3Array, profile: PackedVector2Array, color: Color) -> MeshKit:
	if path.size() < 2 or profile.size() < 3:
		return self
	var rings: Array = []
	var headings: Array = []
	for i in path.size():
		var ahead := path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]
		var heading := ahead.normalized()
		headings.append(heading)
		rings.append(_ring(path[i], heading, profile))
	for i in range(path.size() - 1):
		for k in profile.size():
			var next := (k + 1) % profile.size()
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][next]
			var c: Vector3 = rings[i + 1][next]
			var d: Vector3 = rings[i + 1][k]
			var away := ((a + b + c + d) * 0.25) - _centre_of(rings[i], rings[i + 1])
			_quad([a, b, c, d], away.normalized(), color)
	_cap(rings[0], -(headings[0] as Vector3), color)
	_cap(rings[rings.size() - 1], headings[headings.size() - 1], color)
	return self


## The mesh of every face so far, in 3D units (`RenderConfig.unit` a px), or an empty mesh when
## nothing was added.
func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _points.is_empty():
		return mesh
	var unit := RenderConfig.unit
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for i in _points.size():
		vertices.append(_points[i] * unit)
		colors.append(_colors[i].srgb_to_linear())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One triangle of `corners` facing `outward`, colour `color`: wound the way the engine draws its
## front (clockwise seen from the front), whichever way round the corners were given.
func _tri(corners: Array, outward: Vector3, color: Color) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000001:
		return
	if normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
	for p in [a, c, b]:
		_points.append(p)
		_normals.append(outward.normalized())
		_colors.append(color)


## A quad (four corners in order round it) as two triangles facing `outward`.
func _quad(corners: Array, outward: Vector3, color: Color) -> void:
	_tri([corners[0], corners[1], corners[2]], outward, color)
	_tri([corners[0], corners[2], corners[3]], outward, color)


## The profile's points placed round `at`, turned to look along `heading`.
func _ring(at: Vector3, heading: Vector3, profile: PackedVector2Array) -> Array:
	var across := heading.cross(Vector3.UP)
	if across.length_squared() < 0.000001:
		across = Vector3.RIGHT
	across = across.normalized()
	var up := across.cross(heading).normalized()
	var ring: Array = []
	for p in profile:
		ring.append(at + across * p.x + up * p.y)
	return ring


## A closed end of a loft: a fan over `ring` facing `outward`.
func _cap(ring: Array, outward: Vector3, color: Color) -> void:
	var middle := Vector3.ZERO
	for p: Vector3 in ring:
		middle += p
	middle /= float(ring.size())
	for k in ring.size():
		_tri([middle, ring[k], ring[(k + 1) % ring.size()]], outward, color)


## A wedge's frame: `x` runs from its low edge to its high one (the `rises_toward` side), `y` is up
## and `z` goes across, at the volume's corner where its low edge begins.
func _wedge_frame(wedge_volume: AABB, rises_toward: Vector2) -> Transform3D:
	var along_x := absf(rises_toward.x) >= absf(rises_toward.y)
	var flip := (rises_toward.x if along_x else rises_toward.y) < 0.0
	var rise := (Vector3.RIGHT if along_x else Vector3.BACK) * (-1.0 if flip else 1.0)
	var across := Vector3.BACK if along_x else Vector3.RIGHT
	var corner := wedge_volume.position
	if flip:
		corner += (Vector3.RIGHT if along_x else Vector3.BACK) * (
			wedge_volume.size.x if along_x else wedge_volume.size.z
		)
	return Transform3D(Basis(rise, Vector3.UP, across), corner)


## `top` unless it is `SAME`, then `color`.
func _or(top: Color, color: Color) -> Color:
	return color if top.a == 0.0 else top


## The two vectors along the two axes `across` (a vector with one zero axis) spans.
func _spans(across: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var along: Vector3 = across * axis
		if along != Vector3.ZERO:
			out.append(along)
	return out


## The middle of two neighbouring rings.
func _centre_of(first: Array, second: Array) -> Vector3:
	var middle := Vector3.ZERO
	for p: Vector3 in first + second:
		middle += p
	return middle / float(first.size() + second.size())


## `corners` (2D px) as points `at` px up.
func _lifted(corners: Array, at: float) -> Array:
	var out: Array = []
	for p: Vector2 in corners:
		out.append(Vector3(p.x, at, p.y))
	return out


## The signed area of `polygon` (positive when it runs counter-clockwise with `y` up).
func _area(polygon: PackedVector2Array) -> float:
	var sum := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		sum += a.x * b.y - b.x * a.y
	return sum * 0.5
