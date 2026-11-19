class_name InkFx
extends RefCounted
## Physics domain, what lies flat on the floor in the 3D render
## (`domain-physics/meshes.md`): blood's splats, footprints and smears, and a blast's scorch. Each
## is a few flat triangles (`InkMark`) a few tenths of a px over the ground, on the height of its
## kind (`PhysicsInkConfig`), in the shapes and colours the 2D drew (the splat's own merged
## outlines, the print's sole, the smear's ribbon, the scorch's stepped rows), opaque and in steps
## of tone as the rest of the 3D render is: blood dries in `PhysicsInkConfig.dry_steps` steps
## and a faint print takes its opacity from a few levels over the floor's tone. The marks are filed
## in 128 px chunks, a mesh each (`InkChunk`), built again at most once a frame when one of them
## changes, so a floor strewn with blood is a few draws and, once it is dry, nothing runs and
## nothing is written. A splat lives as long as its 2D node (the 2D caps free it); the prints and
## smears and the scorches are kept up to the 2D layers' caps (`BloodConfig.print_max`, the
## `Despawner`'s). A bleed-out pool is `PoolInk`'s.

## Said when a mark changed by itself (it dried), so a resting layer wakes to build its chunk.
signal went_dry

## Side (px) of a chunk, as the 2D layers'.
const CHUNK := 128.0
## A mark on a wall stops this many px over the floor (a splat cut off at the floor, not through
## it).
const FLOOR := 0.3

## How many times a chunk's mesh was built (a test reads it: a dry floor builds none).
var rebuilds := 0
var _parent: Node3D
## The chunks by cell and those whose mesh is out of date.
var _chunks := {}
var _dirty := {}
## The splats by their 2D node's instance id; the prints and smears, and the scorches, oldest
## first; the marks still drying.
var _splats := {}
var _prints := PieceQueue.new()
var _scorches := PieceQueue.new()
var _wet: Array[InkMark] = []
## The timer that dries the wet marks a step at a time, and how many scorches the world keeps.
var _timer := Timer.new()
var _cap := 1
## The smear ribbons by the id this layer gave their 2D mark (`ink_id` in it), the next id, and the
## ground the marks lie on (the road a kerb lower).
var _ribbons := {}
var _next_ribbon := 0
var _world: FxWorld


## Marks under `parent` (the 3D world's frame), `cap` scorches kept (the `Despawner`'s), over the
## ground of `world`.
func _init(parent: Node3D, cap: int, world: FxWorld) -> void:
	_world = world
	_parent = parent
	_cap = maxi(cap, 1)
	_timer.name = "Drying"
	_timer.timeout.connect(_dry)
	parent.add_child(_timer)


## How many marks of `kind` lie, and how many chunks hold them.
func count_of(kind: InkMark.Kind) -> int:
	match kind:
		InkMark.Kind.SPLAT:
			return _splats.size()
		InkMark.Kind.SCORCH:
			return _scorches.size()
	return _prints.items().filter(func(m: InkMark) -> bool: return m.kind == kind).size()


## The chunk `mark` is filed in (null when it is in none).
func chunk_of(mark: InkMark) -> InkChunk:
	return _chunks.get(mark.cell)


## How many marks are still drying.
func wet() -> int:
	return _wet.size()


## The marks of `kind`, oldest first (a list of the caller's own).
func marks(kind: InkMark.Kind) -> Array[InkMark]:
	var out: Array[InkMark] = []
	var all: Array = _splats.values() + _prints.items() + _scorches.items()
	for mark: InkMark in all:
		if mark.kind == kind:
			out.append(mark)
	return out


## A splat `BloodSplat` just built: its merged outlines (`shapes`, in its own frame) and its
## wet highlight (`highlight_polygon`) lie where it landed as long as the node does: on the floor,
## or on the surface it says (`BloodSplat.surface`: a piece's top at its height, a wall's face at
## the height it was struck).
func splat_made(splat: Node2D) -> void:
	var mark := _new(InkMark.Kind.SPLAT, splat.global_position)
	mark.node_id = splat.get_instance_id()
	mark.dry_time = BloodSplatConfig.dry_time
	var to_world := splat.global_transform
	var ground := _world.ground_at(splat.global_position)
	var surface: Dictionary = splat.surface
	for poly: PackedVector2Array in splat.shapes:
		_lay(mark, to_world * poly, PhysicsInkConfig.splat_layer, surface, ground)
	mark.body = mark.verts.size()
	var fleck: PackedVector2Array = splat.highlight_polygon
	if not fleck.is_empty():
		mark.fleck = splat.highlight_color
		var over := PhysicsInkConfig.splat_layer + PhysicsInkConfig.over_layer
		_lay(mark, to_world * fleck, over, surface, ground)
	if mark.body == 0:
		return
	_splats[mark.node_id] = mark
	splat.tree_exiting.connect(_splat_gone.bind(mark))
	_paint(mark, 0 if mark.dry_time > 0.0 else _steps())
	_file(mark)
	_dry_later(mark)


## A footprint of the 2D `BloodDecals`: a polygon (world px) at `alpha` of the blood colour.
func print_made(poly: PackedVector2Array, alpha: float) -> void:
	if poly.size() < 3:
		return
	var mark := _new(InkMark.Kind.PRINT, poly[0])
	mark.alpha = alpha
	mark.dry_time = BloodConfig.print_dry_time
	_fan(mark, poly, lift_of(PhysicsInkConfig.print_layer) + _world.ground_at(poly[0]))
	mark.body = mark.verts.size()
	_keep(mark)


## A smear ribbon the 2D `BloodDecals` began (`source` is its own mark: points, widths, alphas). It
## is given an `ink_id` in that mark, which its growth finds it by.
func ribbon_begun(source: Dictionary) -> void:
	var mark := _new(InkMark.Kind.RIBBON, (source["points"] as PackedVector2Array)[0])
	mark.source = source
	mark.dry_time = BloodConfig.print_dry_time
	mark.node_id = _next_ribbon
	source["ink_id"] = mark.node_id
	_next_ribbon += 1
	_ribbons[mark.node_id] = mark
	_keep(mark)


## A smear ribbon grew (`source` is the 2D mark): the new segments are laid, the old ones stay.
func ribbon_grew(source: Dictionary) -> void:
	var mark: InkMark = _ribbons.get(int(source.get("ink_id", -1)))
	if mark == null or not mark.alive:
		return
	_ribbon_grow(mark)
	_dirty[mark.cell] = true


## A scorch of the 2D `ScorchDecals`: its stepped rows (`rects`, world px, and a colour for each,
## the art's sRGB colour with its opacity), a core over a rim.
func scorch_burned(rects: Array[Rect2], tones: Array[Color]) -> void:
	if rects.is_empty():
		return
	var mark := _new(InkMark.Kind.SCORCH, rects[0].get_center())
	var core := PhysicsExplosionConfig.scorch_color.a - 0.001
	var ground := _world.ground_at(rects[0].get_center())
	for i in rects.size():
		var layer := PhysicsInkConfig.scorch_layer
		if tones[i].a >= core:
			layer += PhysicsInkConfig.over_layer
		_quad(mark, rects[i], lift_of(layer) + ground, _opaque(tones[i]))
	mark.body = mark.verts.size()
	_scorches.append(mark)
	_file(mark)
	while _scorches.size() > _cap:
		_unfile(_scorches.pop())


## Build the chunks that changed; the marks are not moving, so this is all the work there is.
func process() -> void:
	for cell: Vector2i in _dirty:
		var chunk: Variant = _chunks.get(cell)
		if not is_instance_valid(chunk):
			continue
		chunk.rebuild()
		rebuilds += 1
		if chunk.marks.is_empty():
			chunk.queue_free()
			_chunks.erase(cell)
	_dirty.clear()


## Whether a chunk waits to be built.
func pending() -> bool:
	return not _dirty.is_empty()


## The height (px) of decal layer `layer` over the ground: the shared rule of `MeshNodes.decal`.
static func lift_of(layer: float) -> float:
	return MeshKitConfig.decal_lift + layer * MeshKitConfig.decal_layer_step


## A mark of `kind` at world `at` (px): its chunk cell, its frame of birth.
func _new(kind: InkMark.Kind, at: Vector2) -> InkMark:
	var mark := InkMark.new()
	mark.kind = kind
	mark.cell = Vector2i((at / CHUNK).floor())
	mark.born = Engine.get_physics_frames()
	return mark


## File a print or a smear, the newest, painted wet, and drop the oldest past the 2D cap.
func _keep(mark: InkMark) -> void:
	if mark.kind == InkMark.Kind.RIBBON:
		_ribbon_grow(mark)
	_prints.append(mark)
	_paint(mark, 0 if mark.dry_time > 0.0 else _steps())
	_file(mark)
	_dry_later(mark)
	while _prints.size() > BloodConfig.print_max:
		var old: InkMark = _prints.pop()
		_wet.erase(old)
		_ribbons.erase(old.node_id if old.kind == InkMark.Kind.RIBBON else -1)
		_unfile(old)


## Put `mark` in its chunk (made when it is the first), to be built.
func _file(mark: InkMark) -> void:
	if not _chunks.has(mark.cell):
		var chunk := InkChunk.new()
		chunk.name = "Ink_%d_%d" % [mark.cell.x, mark.cell.y]
		_parent.add_child(chunk)
		_chunks[mark.cell] = chunk
	_chunks[mark.cell].marks.append(mark)
	_dirty[mark.cell] = true


## Take `mark` out of its chunk.
func _unfile(mark: InkMark) -> void:
	mark.alive = false
	var chunk: Variant = _chunks.get(mark.cell)
	if is_instance_valid(chunk):
		chunk.marks.erase(mark)
		_dirty[mark.cell] = true


## A splat's 2D node left the world (its body's cap, the `Despawner`, the end of the match).
func _splat_gone(mark: InkMark) -> void:
	_splats.erase(mark.node_id)
	_wet.erase(mark)
	_unfile(mark)


## The mark dries from now: it is watched until it is dry.
func _dry_later(mark: InkMark) -> void:
	if mark.dry_time <= 0.0 or mark.step >= _steps():
		return
	_wet.append(mark)
	if _timer.is_stopped() or mark.dry_time / float(_steps()) < _timer.wait_time:
		_timer.start(_period())


## One step of drying: each wet mark whose time has come is painted at its next step.
func _dry() -> void:
	var now := Engine.get_physics_frames()
	var i := _wet.size() - 1
	while i >= 0:
		var mark := _wet[i]
		var age := float(now - mark.born) / float(Engine.physics_ticks_per_second)
		var step := clampi(int(age / mark.dry_time * _steps()), 0, _steps())
		if step != mark.step:
			_paint(mark, step)
			_dirty[mark.cell] = true
		if step >= _steps():
			_wet.remove_at(i)
		i -= 1
	if _wet.is_empty():
		_timer.stop()
	if not _dirty.is_empty():
		went_dry.emit()


## How long (s) between two steps of drying: the quickest drying mark's.
func _period() -> float:
	var shortest := INF
	for mark in _wet:
		shortest = minf(shortest, mark.dry_time)
	return maxf(shortest / float(_steps()), 0.05)


## The steps blood dries in (at least one).
func _steps() -> int:
	return maxi(PhysicsInkConfig.dry_steps, 1)


## Paint `mark` at `step` of its drying: blood from its wet colour toward the dried one, a print's
## or
## smear's opacity laid over the floor's tone, the fleck of a splat fading with it. A scorch has
## its colours from the start.
func _paint(mark: InkMark, step: int) -> void:
	mark.step = step
	var dried := float(step) / float(_steps())
	var blood := BloodConfig.color.lerp(BloodConfig.dried_color, dried)
	match mark.kind:
		InkMark.Kind.SPLAT:
			var body := _filled(mark.body, _linear(blood, false))
			var fleck := mark.fleck.lerp(blood, dried)
			mark.colors = body + _filled(mark.verts.size() - mark.body, _linear(fleck, false))
		InkMark.Kind.PRINT:
			blood.a *= mark.alpha
			mark.colors = _filled(mark.verts.size(), _linear(blood, true))
		InkMark.Kind.RIBBON:
			_paint_ribbon(mark, blood)


## A ribbon's colours: a colour for each segment (six vertices) by that point's opacity.
func _paint_ribbon(mark: InkMark, blood: Color) -> void:
	var alphas: PackedFloat32Array = mark.source["alphas"]
	var tones := PackedColorArray()
	for i in int(mark.verts.size() / 6.0):
		var tone := blood
		tone.a *= alphas[i]
		tones.append_array(_filled(6, _linear(tone, true)))
	mark.colors = tones


## Lay the segments of ribbon `mark`'s 2D mark it has not got yet, a flat band each, in the colour
## the mark has now (a segment is six vertices).
func _ribbon_grow(mark: InkMark) -> void:
	var points: PackedVector2Array = mark.source["points"]
	var widths: PackedFloat32Array = mark.source["widths"]
	var alphas: PackedFloat32Array = mark.source["alphas"]
	var blood := BloodConfig.color.lerp(BloodConfig.dried_color, float(mark.step) / float(_steps()))
	for i in range(mark.laid, points.size() - 1):
		_segment(mark, points, widths, i)
		var tone := blood
		tone.a *= alphas[i]
		mark.colors.append_array(_filled(6, _linear(tone, true)))
	mark.laid = maxi(points.size() - 1, 0)
	mark.body = mark.verts.size()


## The band of segment `i` of a ribbon (its `points` and `widths`), over the ground at its start.
func _segment(
	mark: InkMark,
	points: PackedVector2Array,
	widths: PackedFloat32Array,
	i: int,
) -> void:
	var to := points[i + 1]
	if points[i].distance_squared_to(to) < 0.0001:
		to = points[i] + Vector2(0.001, 0.0)
	var side := (to - points[i]).normalized().orthogonal()
	var from_edge := side * widths[i] * 0.5
	var to_edge := side * widths[i + 1] * 0.5
	var lift := lift_of(PhysicsInkConfig.print_layer) + _world.ground_at(points[i])
	_quad_points(mark, [points[i] - from_edge, points[i] + from_edge, to + to_edge,
		to - to_edge], lift)


## `places` copies of `tone`.
func _filled(places: int, tone: Color) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(maxi(places, 0))
	out.fill(tone)
	return out


## The colour a vertex takes for the art's sRGB colour `color`: blood's own (`see_through` false:
## its opacity is nearly full, so ignored) or, for a mark that is see-through in 2D, laid over the
## floor's tone by the nearest of the opacity steps.
func _linear(color: Color, see_through: bool) -> Color:
	var tone := _opaque(color) if see_through else Color(color.r, color.g, color.b)
	return tone.srgb_to_linear()


## `color` (the art's sRGB colour and its opacity) laid over the floor's tone by the nearest of
## the opacity steps: the opaque colour a see-through mark is in 3D.
func _opaque(color: Color) -> Color:
	var steps: Array = PhysicsInkConfig.alpha_steps
	var level := 1.0
	var gap := INF
	for step: float in steps:
		if absf(step - color.a) < gap:
			gap = absf(step - color.a)
			level = step
	return PhysicsInkConfig.ground_tone.lerp(Color(color.r, color.g, color.b), level)


## The triangles of `poly` (world px, a simple polygon) on decal layer `layer` of where it lies:
## over the `ground` (`surface` empty), on a piece's top, or on a wall's face.
func _lay(
	mark: InkMark, poly: PackedVector2Array, layer: float, surface: Dictionary, ground: float
) -> void:
	if surface.is_empty():
		_fan(mark, poly, lift_of(layer) + ground)
	elif surface["kind"] == BloodLanding.Kind.TOP:
		_fan(mark, poly, float(surface["height"]) + lift_of(layer))
	else:
		_wall_fan(mark, poly, surface, lift_of(layer))


## The triangles of `poly` (world px, as it would lie on the floor at the splat's place) stood on
## a wall's face: its x runs along the wall, its y down it, from the height the blood struck at, cut
## off at the floor and at the wall's top; `lift` px off the face.
func _wall_fan(mark: InkMark, poly: PackedVector2Array, surface: Dictionary, lift: float) -> void:
	var at: Vector2 = surface["at"]
	var height: float = surface["height"]
	var local := PackedVector2Array()
	for point in poly:
		local.append(point - at)
	var top := minf(PhysicsInkConfig.wall_top, float(surface.get("top", INF)))
	var band := _rect_polygon(Rect2(-1.0e4, height - top, 2.0e4, top - FLOOR))
	for part in Geometry2D.intersect_polygons(local, band):
		var corners := Geometry2D.triangulate_polygon(part)
		for i in range(0, corners.size(), 3):
			var points: Array[Vector3] = []
			for k in 3:
				points.append(_on_wall(surface, part[corners[i + k]], lift))
			_stand(mark, points, _facing(surface))


## The 3D point of local point `p` of a splat stood on a wall's face (`surface`), `lift` px off it:
## along the wall by its x, down it by its y from the height struck.
func _on_wall(surface: Dictionary, p: Vector2, lift: float) -> Vector3:
	var normal := _facing(surface)
	var along := Vector3(-normal.z, 0.0, normal.x)
	var base := PlanSpace.lift(surface["at"], float(surface["height"]) - p.y)
	return base + (along * p.x + normal * lift) * RenderConfig.unit


## The way the wall's face looks (a unit 3D vector, flat).
func _facing(surface: Dictionary) -> Vector3:
	var normal: Vector2 = surface["normal"]
	return Vector3(normal.x, 0.0, normal.y)


## The corners of `rect`, going round.
func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array(
		[
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		]
	)


## One triangle of three 3D points, wound to face `normal`, which its vertices take.
func _stand(mark: InkMark, points: Array[Vector3], normal: Vector3) -> void:
	var a := points[0]
	var b := points[1]
	var c := points[2]
	if (c - a).cross(b - a).dot(normal) < 0.0:
		var swap := b
		b = c
		c = swap
	for corner in [a, b, c]:
		mark.verts.append(corner)
		mark.normals.append(normal)


## The triangles of `poly` (world px, a simple polygon) at `lift` px, facing up.
func _fan(mark: InkMark, poly: PackedVector2Array, lift: float) -> void:
	var corners := Geometry2D.triangulate_polygon(poly)
	for i in range(0, corners.size(), 3):
		_triangle(mark, poly[corners[i]], poly[corners[i + 1]], poly[corners[i + 2]], lift)


## A rectangle `rect` (world px) at `lift`, the colour `tone` (the art's sRGB colour).
func _quad(mark: InkMark, rect: Rect2, lift: float, tone: Color) -> void:
	var before := mark.verts.size()
	_quad_points(mark, [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)], lift)
	mark.colors.append_array(_filled(mark.verts.size() - before, tone.srgb_to_linear()))


## The quad of four corners (world px, going round) at `lift`.
func _quad_points(mark: InkMark, corners: Array, lift: float) -> void:
	_triangle(mark, corners[0], corners[1], corners[2], lift)
	_triangle(mark, corners[0], corners[2], corners[3], lift)


## One triangle, wound the way the engine draws its front seen from above.
func _triangle(mark: InkMark, a: Vector2, b: Vector2, c: Vector2, lift: float) -> void:
	if (b - a).cross(c - a) < 0.0:
		var swap := b
		b = c
		c = swap
	for corner in [a, b, c]:
		mark.verts.append(Vector3(corner.x, lift, corner.y) * RenderConfig.unit)
