extends Node2D
## Wall CONTROL layer (Objects domain). A hittable, deformable room-boundary entity, a plan handle
## (a `Node2D`: its place and turn are the plan's, in the group `&"walls"`): computes the wall
## centerline segments (with any doorways cut out), holds each segment's outline as polygons (the
## 3D `WallTwin` is the body those become), and takes hits (deform + debris). Built by WallFactory
## from a rect +
## openings. The 3D render shows it (`wall_mesh.gd`), reading `wall_segments()` and
## `wall_thickness` from this node.

## Segment `index` (into `wall_segments()`) has new colliders: its dents were rebuilt.
signal segment_rebuilt(index: int)

enum Side {
	NONE,
	TOP,
	BOTTOM,
	LEFT,
	RIGHT,
}

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
## Two edges this close along a wall (px) are one.
const SEAM_EPSILON := 0.5

## Room extents (centerline of the walls).
@export var size: Vector2 = Vector2(600.0, 600.0)
## Half the character's width.
@export var wall_thickness: float = 24.0
## Doorways: `{ side: Side, offset: float, width: float }`. `offset` is the gap center
## measured along the wall from its start corner (top/bottom walls start at the left,
## left/right walls start at the top).
@export var openings: Array = []
## Pixel-art cap: the tiling painter id ("" = a flat gray line), its base color (its debris takes
## the colour it is drawn in) and painter options (see ObjectArtWallConfig). Read by
## `wall_mesh.gd`.
@export var art: String = ""
## Cap base color.
@export var art_color: Color = Color(0.6, 0.6, 0.6)
## Painter options, e.g. { "pattern": "plaster" }.
@export var art_opts: Dictionary = {}
## Stretches of this wall's outline that a wall built before it already stands on, `{ side: Side,
## from: float, to: float }` along the side from its start corner (`WallFactory.seams_for`). A
## segment inside one is still a segment (the doorways cut in it stay where they are) but builds no
## collider: the wall that owns the stretch has the one, in 2D and in 3D. The owner's thickness is
## the shared stretch's, so walls built together are equally thick (`WallFactory.spawn` checks).
@export var seams: Array = []
## The wall's own ballistic surface rating (Objects owns its surface data, same as
## environment_object.gd): hard to shoot through.
@export var penetration: float = 100.0

## Damage impacts per wall-segment index (into wall_segments()), in wall-local space.
## The dents per struck segment (`wall_mesh.gd` and the collider rebuild read them). See
## _record_segment_damage().
var _seg_impacts := {}
## Segment index -> Array of that segment's convex outlines (`PackedVector2Array`, this node's
## frame), so a damaged segment's twin can be cut again to follow the deformed shape. Filled in
## _build_walls().
var _seg_outlines := {}
## Segment index -> true while its deferred collider rebuild waits: the hits that land on it before
## that runs share it, as a piece of furniture's do (each would rebuild the same pieces from the
## same dents).
var _rebuild_queued := {}
## Segment index -> the cut queued with its rebuild (`ColliderCuts`, as a piece of furniture's).
var _seg_cuts := {}
## The room's wear node (`WearFactory.spawn` sets it: the room's `RoomWear`, in this wall's frame),
## whose wall marks the 3D mesh stands on the segments' faces; null for a wall with none.
var wear: Node2D = null
## The wear of the neighbouring rooms whose marks lie on stretches of this wall that it owns (a
## stretch two rooms share is built here once, so the room that does not own it has its marks laid
## on this wall): `WearFactory.spawn` fills it.
var neighbour_wear: Array[Node2D] = []
## `_layout()` kept.
var _layout_kept := {}


func _exit_tree() -> void:
	for cut: ColliderCuts in _seg_cuts.values():
		cut.cancel()
	_seg_cuts.clear()


func _enter_tree() -> void:
	# the plan handle of a wall: what the twin space twins and the bake finds walls by
	add_to_group(&"walls")
	add_to_group(TwinSpace.BODIES)
	add_to_group(TwinSpace.HARD)


func _ready() -> void:
	_layout_kept = {}
	_build_walls()


## The cut of segment `i` as its dents stand now (on the main thread): a pure job
## (`Deformation.cut_wall`) on a copy of them.
func _prepare_cut(i: int) -> Callable:
	var seg: PackedVector2Array = wall_segments()[i]
	var a := seg[0]
	var b := seg[1]
	var thickness := wall_thickness
	var dents: Array = (_seg_impacts.get(i, []) as Array).duplicate(true)
	return func() -> Array: return Deformation.cut_wall(a, b, thickness, dents)


## Segment index (into `wall_segments()`) -> the convex outlines (`PackedVector2Array`) that stand
## for that segment now, in this node's frame: one rectangle while it is whole, the convex pieces of
## its dented outline after a hit. What the twin (`WallTwin`) and the 3D mesh (`art/wall_mesh.gd`)
## are built from, so they match. A copy: the arrays are the wall's own, read them only.
func segment_shapes() -> Dictionary:
	return _seg_outlines.duplicate()


## The wall's ballistic surface: hard to shoot through, debris in the colour its cap is drawn in.
func get_surface() -> Dictionary:
	return { "penetration": penetration,
		"material": "", "color": ObjectArt.drawn_color(art_color) if art != "" else art_color }


## Deform the nearest wall segment and spray debris. Walls are immovable, so no knockback.
func take_hit(hit: HitInfo) -> void:
	_record_segment_damage(hit.position, hit.normal, hit.damage, hit.blood)
	Physics.spawn_debris(get_parent(), hit, get_surface())


## Every hit mark on this wall's segments (dicts with `pos`, `depth`, `blood`, …).
func hit_marks() -> Array:
	var marks: Array = []
	for arr: Array in _seg_impacts.values():
		marks.append_array(arr)
	return marks


## Dent the nearest wall segment (caving inward along the contact normal) and
## rebuild that segment's collider to match.
func _record_segment_damage(
	world_pos: Vector2,
	world_normal: Vector2,
	amount: float,
	blood: float = 0.0,
) -> void:
	var local_pos := to_local(world_pos)
	var segs := wall_segments()
	var best_i := _nearest_segment(segs, local_pos)
	if best_i < 0:
		return
	var inward := _inward(world_pos, world_normal, segs[best_i])
	var arr: Array = _seg_impacts.get(best_i, [])
	var dent := DentLimits.new()
	dent.rng = WorldRng.of(self)
	var impact := Deformation.new_impact(local_pos, inward, amount, blood, dent)
	Deformation.push_impact(arr, impact, PhysicsDeformConfig.max_impacts)
	_seg_impacts[best_i] = arr
	# Rebuild the segment collider to follow the deformed shape (deferred — take_hit runs
	# mid-physics from the projectile, when swapping shapes is disallowed).
	if PhysicsDeformConfig.update_collider and not _rebuild_queued.has(best_i):
		_rebuild_queued[best_i] = true
		# cut beside the others' (see environment_object.gd)
		_seg_cuts[best_i] = ColliderCuts.queue(_prepare_cut.bind(best_i))
		call_deferred("_rebuild_segment", best_i)


## The index of the segment of `segs` nearest `local_pos` (this node's frame), skipping empty ones
## and those on a stretch another wall owns; -1 when there is none.
func _nearest_segment(segs: Array[PackedVector2Array], local_pos: Vector2) -> int:
	var best_i := -1
	var best_d := INF
	for i in segs.size():
		var a: Vector2 = segs[i][0]
		var b: Vector2 = segs[i][1]
		if a.is_equal_approx(b) or not has_segment(i):
			continue
		var proj := Geometry2D.get_closest_point_to_segment(local_pos, a, b)
		var d := local_pos.distance_to(proj)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


## Which way a hit at `world_pos` with contact normal `world_normal` dents the segment `seg`, in
## this node's frame: INTO the wall. The contact normal points out of the surface (toward the shot),
## so into the surface is its negation. Fallback (degenerate normal) = away from the room center,
## i.e. into the wall — never toward the room.
func _inward(world_pos: Vector2, world_normal: Vector2, seg: PackedVector2Array) -> Vector2:
	var local_pos := to_local(world_pos)
	var out_normal := to_local(world_pos + world_normal) - local_pos
	var inward := (-out_normal).normalized()
	if inward.length() < 0.5:
		var perp := (seg[1] - seg[0]).normalized().orthogonal()
		inward = perp if perp.dot(local_pos - size * 0.5) > 0.0 else -perp
	return inward


## Centerline segments (start/end points) for every wall, with the openings removed, and split where
## a shared stretch (`seams`) starts or ends, so each lies wholly on one or off every one.
func wall_segments() -> Array[PackedVector2Array]:
	return (_layout()["segments"] as Array[PackedVector2Array]).duplicate()


## Whether segment `index` of `wall_segments()` is this wall's to build: false for one on a stretch
## another wall owns (`seams`), whether or not the colliders are built yet.
func has_segment(index: int) -> bool:
	var layout := _layout()
	var segs: Array[PackedVector2Array] = layout["segments"]
	return (
		index >= 0
		and index < segs.size()
		and not layout["shared"][index]
		and not segs[index][0].is_equal_approx(segs[index][1])
	)


## Whether the doorway `gap` (an entry of `openings`) lies on a stretch another wall owns, so the
## lintel over it (3D) is that wall's.
func opening_is_shared(gap: Dictionary) -> bool:
	for seam: Dictionary in seams:
		if (
			seam["side"] == gap["side"]
			and float(gap["offset"]) > float(seam["from"])
			and float(gap["offset"]) < float(seam["to"])
		):
			return true
	return false


## The segments and, parallel to them, `shared` (on a stretch another wall owns) and `cut` (bits
## 1 and 2: the segment's start and end meet a shared piece, so it is not lengthened there).
func _layout() -> Dictionary:
	if not _layout_kept.is_empty():
		return _layout_kept
	_layout_kept = _lay_out()
	return _layout_kept


## `_layout` worked out (the wall's size, openings and seams do not change once it is built).
func _lay_out() -> Dictionary:
	var w := size.x
	var h := size.y
	# Each edge as an ordered pair of corner points.
	var edges := {
		Side.TOP: [Vector2(0.0, 0.0), Vector2(w, 0.0)],
		Side.RIGHT: [Vector2(w, 0.0), Vector2(w, h)],
		Side.BOTTOM: [Vector2(0.0, h), Vector2(w, h)],
		Side.LEFT: [Vector2(0.0, 0.0), Vector2(0.0, h)],
	}
	var out := { "segments": [] as Array[PackedVector2Array], "shared": [], "cut": [] }
	for side in edges:
		_append_side(out, side, edges[side][0], edges[side][1])
	return out


## Append to `out` the pieces of the wall along `side`, from corner `a` to `b`: the solid stretches
## between the gaps its openings leave, each split at the shared stretches (`seams`) on it.
func _append_side(out: Dictionary, side: int, a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length

	var gaps: Array = openings.filter(func(o: Dictionary) -> bool: return o.side == side)
	gaps.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.offset < y.offset)

	# Walk along the wall, emitting the solid pieces between gaps.
	var cursor := 0.0
	for gap in gaps:
		var gap_start := clampf(gap.offset - gap.width * 0.5, 0.0, length)
		var gap_end := clampf(gap.offset + gap.width * 0.5, 0.0, length)
		if gap_start > cursor:
			_append_solid(out, side, a, dir, Vector2(cursor, gap_start))
		cursor = maxf(cursor, gap_end)
	if cursor < length:
		_append_solid(out, side, a, dir, Vector2(cursor, length))


## Append the solid stretch `span` (from, to) along `dir` from `a`, in the pieces the shared
## stretches of `side` leave: a piece inside one is `shared`, one beside one is `cut` at that end.
func _append_solid(
	out: Dictionary,
	side: int,
	a: Vector2,
	dir: Vector2,
	span: Vector2,
) -> void:
	var from := span.x
	var to := span.y
	var cuts: Array[float] = [from, to]
	for seam: Dictionary in seams:
		if seam["side"] != side:
			continue
		for edge: float in [seam["from"], seam["to"]]:
			if edge > from + SEAM_EPSILON and edge < to - SEAM_EPSILON:
				cuts.append(edge)
	cuts.sort()
	var pieces: Array = []
	for i in cuts.size() - 1:
		if cuts[i + 1] - cuts[i] > SEAM_EPSILON:
			pieces.append([cuts[i], cuts[i + 1], _on_seam(side, (cuts[i] + cuts[i + 1]) * 0.5)])
	for i in pieces.size():
		var cut := 0
		if i > 0 and pieces[i - 1][2] != pieces[i][2]:
			cut |= 1
		if i < pieces.size() - 1 and pieces[i + 1][2] != pieces[i][2]:
			cut |= 2
		(out["segments"] as Array).append(
			PackedVector2Array([a + dir * pieces[i][0], a + dir * pieces[i][1]])
		)
		(out["shared"] as Array).append(pieces[i][2])
		(out["cut"] as Array).append(cut)


## Whether the point `at` along `side` is on a shared stretch.
func _on_seam(side: int, at: float) -> bool:
	for seam: Dictionary in seams:
		if seam["side"] == side and at > float(seam["from"]) and at < float(seam["to"]):
			return true
	return false


## Give each wall segment this wall owns its rectangle outline.
func _build_walls() -> void:
	var layout := _layout()
	var segs: Array[PackedVector2Array] = layout["segments"]
	for i in segs.size():
		if segs[i][0].is_equal_approx(segs[i][1]) or layout["shared"][i]:
			continue
		# keyed by wall_segments() index for later rebuilds
		_seg_outlines[i] = [_owned_outline(segs[i], layout["cut"][i])]


## The outline of the segment `seg` this wall owns, its ends lengthened by half the thickness so
## corners overlap cleanly, but not where it meets a stretch another wall owns (`cut`: bits 1 and
## 2, that wall stands there). Opening edges are lengthened slightly too, which just rounds the
## doorway jamb a touch.
func _owned_outline(seg: PackedVector2Array, cut: int) -> PackedVector2Array:
	var half := wall_thickness * 0.5
	var dir := (seg[1] - seg[0]).normalized()
	var start := seg[0] - dir * (0.0 if cut & 1 else half)
	var end := seg[1] + dir * (0.0 if cut & 2 else half)
	return _segment_outline(start, end, dir)


## The rectangle outline of a wall segment from `start` to `end` (its ends already extended)
## running along `dir`, `wall_thickness` thick.
func _segment_outline(start: Vector2, end: Vector2, dir: Vector2) -> PackedVector2Array:
	var t := wall_thickness
	var length := start.distance_to(end)
	# Horizontal segment -> width along x; vertical segment -> width along y.
	var across := Vector2(length, t) if absf(dir.x) > absf(dir.y) else Vector2(t, length)
	var centre := (start + end) * 0.5
	var half := across * 0.5
	return PackedVector2Array([
		centre + Vector2(-half.x, -half.y), centre + Vector2(half.x, -half.y),
		centre + Vector2(half.x, half.y), centre + Vector2(-half.x, half.y),
	])


## Cut a damaged wall segment's outlines again from its deformed polygon, so the twin
## is what's drawn. Keeps the old outlines if convex decomposition fails.
func _rebuild_segment(i: int) -> void:
	_rebuild_queued.erase(i)
	# [] for the one cut here
	var made: Array = (_seg_cuts[i] as ColliderCuts).take() if _seg_cuts.has(i) else []
	_seg_cuts.erase(i)
	var segs := wall_segments()
	if i < 0 or i >= segs.size():
		return
	var seg: PackedVector2Array = segs[i]
	var poly := Deformation.wall_polygon(seg[0], seg[1], wall_thickness, _seg_impacts.get(i, []))
	var outlines: Array = (
		made[1] if not made.is_empty() and made[0] == poly else Deformation.convex_pieces(poly)
	)
	if outlines.is_empty():
		return
	_seg_outlines[i] = outlines  # polygon points are already in room-local space
	segment_rebuilt.emit(i)
