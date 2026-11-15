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
## **Posing.** `pose(transform)` turns and places every solid added after it (in px, in the piece's
## frame), so a wheel on its side, an aimed barrel or a tilted chair back is the plain solid built
## at the origin and posed: `kit.pose(Transform3D(Basis(Vector3.BACK, PI / 2), at))`. `pose(
## Transform3D.IDENTITY)` ends it. A piece unique to one node needs no cache: `kit.build()` straight
## into `MeshNodes.instance` (only shared meshes go through `MeshCache`).
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
## The pose faces are added under (`pose`), and what turns a normal with it.
var _pose := Transform3D.IDENTITY
var _pose_normals := Basis.IDENTITY


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
	var count := _sides()
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
		_sweep(rings[i], rings[i + 1], color)
	_cap(rings[0], -(headings[0] as Vector3), color)
	_cap(rings[rings.size() - 1], headings[headings.size() - 1], color)
	return self


## Every solid added after this is turned and placed by `placing` (px, in the piece's frame; a
## scale or a mirror too, faces still face out). `Transform3D.IDENTITY` ends it.
func pose(placing: Transform3D) -> MeshKit:
	if absf(placing.basis.determinant()) < 0.000001:
		push_error("MeshKit.pose: a pose with a flat axis has no normals; ignored")
		return self
	_pose = placing
	_pose_normals = placing.basis.inverse().transposed()
	return self


## A sphere of `radius` px centred at `at` (`x`, height, `y`), `sides` flat faces round (0:
## `MeshKitConfig.cylinder_sides`) and half as many bands tall.
func sphere(at: Vector3, radius: float, color: Color) -> MeshKit:
	var bands := maxi(_sides() >> 1, 2)
	var profile := PackedVector2Array()
	for j in bands + 1:
		profile.append(_arc(radius, -PI * 0.5 + PI * float(j) / float(bands)))
	return revolve(profile, at, color)


## An upright capsule (a cylinder with a half sphere on each end) of `radius` px and `height` px in
## all (at least two radii: shorter is a sphere), standing at `at` (`x`, the height of its
## underside, `y`): a trunk, a limb, a bollard, a pill.
func capsule(at: Vector3, radius: float, height: float, color: Color) -> MeshKit:
	var bands := maxi(_sides() >> 2, 2)
	var rise := maxf(height - 2.0 * radius, 0.0)
	var profile := PackedVector2Array()
	for j in bands + 1:
		var low := _arc(radius, -PI * 0.5 + PI * 0.5 * float(j) / float(bands))
		profile.append(low + Vector2(0.0, radius))
	for j in bands + 1:
		var high := _arc(radius, PI * 0.5 * float(j) / float(bands))
		profile.append(high + Vector2(0.0, radius + rise))
	return revolve(profile, at, color)


## An upright cone of `radius` px at its base, `height` tall, standing at `at` (`x`, the height of
## its base, `y`): a lampshade, a roof spike, a cone on a road.
func cone(at: Vector3, radius: float, height: float, color: Color) -> MeshKit:
	return revolve(PackedVector2Array([Vector2(0, 0), Vector2(radius, 0), Vector2(0, height)]),
		at, color)


## A solid turned about the vertical axis through `at` (`x`, height, `y`): `profile` (px; `x` the
## distance from the axis, `y` the height above `at`) runs from the bottom up along the outside, so
## a point on the axis at each end closes it. What `sphere`, `capsule` and `cone` are made with: a
## lathe-turned post, a vase or a bowl is one more profile.
func revolve(profile: PackedVector2Array, at: Vector3, color: Color) -> MeshKit:
	var count := _sides()
	for k in range(profile.size() - 1):
		_band(profile[k], profile[k + 1], at, count, color)
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
func _tri(corners: Array, outward_in: Vector3, color: Color) -> void:
	var a: Vector3 = _pose * (corners[0] as Vector3)
	var b: Vector3 = _pose * (corners[1] as Vector3)
	var c: Vector3 = _pose * (corners[2] as Vector3)
	var outward := _pose_normals * outward_in
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


## The flat faces of one profile segment (`low` to `high`: radius, height) turned about the axis
## through `at`, `count` round, facing away from the axis (the segment's own outward side).
func _band(low: Vector2, high: Vector2, at: Vector3, count: int, color: Color) -> void:
	var edge := high - low
	var across := Vector2(edge.y, -edge.x)
	for i in count:
		var from := TAU * float(i) / float(count)
		var to := TAU * float(i + 1) / float(count)
		var mid := (from + to) * 0.5
		_quad([
			_turned(at, low, from), _turned(at, low, to), _turned(at, high, to),
			_turned(at, high, from),
		], Vector3(across.x * cos(mid), across.y, across.x * sin(mid)), color)


## The point `radius_height` (radius, height) turned `angle` about the axis through `at`.
func _turned(at: Vector3, radius_height: Vector2, angle: float) -> Vector3:
	return at + Vector3(
		radius_height.x * cos(angle), radius_height.y, radius_height.x * sin(angle)
	)


## `sides`, or the holder's count when it names none.
func _sides() -> int:
	return sides if sides >= 3 else MeshKitConfig.cylinder_sides


## A point of a round profile: `radius` out at `angle` (0 the equator), as (distance from the axis,
## height); a pole sits exactly on the axis, not a rounding error off it.
func _arc(radius: float, angle: float) -> Vector2:
	var out := cos(angle) * radius
	return Vector2(0.0 if absf(out) < 0.00001 else out, sin(angle) * radius)


## A quad (four corners in order round it) as two triangles facing `outward`.
func _quad(corners: Array, outward: Vector3, color: Color) -> void:
	_tri([corners[0], corners[1], corners[2]], outward, color)
	_tri([corners[0], corners[2], corners[3]], outward, color)


## The faces between two neighbouring rings of a loft, each its own plane's normal (a profile that
## is lopsided has no face looking straight away from the middle), turned to face away from it.
func _sweep(from: Array, to: Array, color: Color) -> void:
	var middle := _centre_of(from, to)
	for k in from.size():
		var next := (k + 1) % from.size()
		var a: Vector3 = from[k]
		var b: Vector3 = from[next]
		var c: Vector3 = to[next]
		var d: Vector3 = to[k]
		var facing := (c - a).cross(d - b)  # the face's own normal (any warp averaged out)
		var away := (a + b + c + d) * 0.25 - middle
		_quad([a, b, c, d], facing if facing.dot(away) >= 0.0 else -facing, color)


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
