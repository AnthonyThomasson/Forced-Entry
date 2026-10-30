extends GameTest
## The body's drawing builds its shapes with one transform of a unit outline each
## (body_limbs.gd: `capsule` for every limb segment and its shadow; character_visuals.gd:
## `Deformation.texture_uvs` for the shoulders' shadow; Deformation: a circle's `base_ring` and the
## uvs of `draw_shape`), where it once placed each point with its own trig, and `BodyTrunk.hulls`
## takes the floor shadow's shift in place of a projection callable. This pins those shapes to the
## plain point-by-point sums (the trunk's exactly), on random limbs and on real falling bodies, so
## the body is drawn where it always was.

const Kill := preload("res://tests/_character/kill_probe.gd")
const SEED := 5151
const TARGETS := 2
## How far (px) a point may be from the plain sum's: float rounding only, far below a pixel.
const TOLERANCE := 0.001


func describe() -> Dictionary:
	return {
		"name": "The body's shapes are the same as the plain sums",
		"description": "Limb capsules, the shoulders' shadow uvs, a circle's ring and the fallen "
			+ "trunk's slices (as drawn and on the floor shadow) match the point-by-point sums "
			+ "they replace.",
		"tags": ["draw", "ragdoll", "deformation"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.switch(&"physics.blood", false)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	for i in TARGETS:
		s.actor(
			StringName("target%d" % i),
			&"puppet",
			Vector2(520, 180.0 + 140.0 * i),
			{ "max_health": 1.0 },
		)


func run(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_check_capsules(t, rng)
	_check_fans_convex(t, rng)
	_check_texture_uvs(t, rng)
	_check_rings(t)
	if not await Kill.kill_targets(t, TARGETS):
		return
	await _check_fallen(t)


## Limb capsules on random ends and radii (drawn from `rng`) are the plain sum's.
func _check_capsules(t: TestContext, rng: RandomNumberGenerator) -> void:
	var worst := 0.0
	for n in 400:
		var a := Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))
		var b := (a
				+ Vector2.from_angle(rng.randf() * TAU)
					* (rng.randf_range(0.0, 1.0) if n % 5 == 0 else rng.randf_range(0.5, 40.0)))
		var ra := rng.randf_range(1.0, 8.0)
		var rb := rng.randf_range(1.0, 8.0)
		worst = maxf(worst, _gap(BodyLimbs.capsule(a, b, ra, rb), _plain_capsule(a, b, ra, rb)))
	t.check(
		worst <= TOLERANCE,
		"limb capsules: the farthest point is %.6f px from the plain sum's" % worst,
	)


## A capsule whose ends' radii differ by less than CAP_CONVEX of its length is drawn as a fan,
## uncut: it must be convex.
func _check_fans_convex(t: TestContext, rng: RandomNumberGenerator) -> void:
	var fanned := 0
	var concave := 0
	for n in 3000:
		var a := Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 40.0)
		var ra := rng.randf_range(0.5, 9.0)
		var rb := rng.randf_range(0.5, 9.0)
		var span := a.distance_to(b)
		if not (span < 0.5 or absf(ra - rb) < span * BodyLimbs.CAP_CONVEX):
			continue
		fanned += 1
		if not _convex(BodyLimbs.capsule(a, b, ra, rb)):
			concave += 1
	t.check(
		fanned > 500 and concave == 0,
		"capsules drawn as fans are convex (%d of %d are not)" % [concave, fanned],
	)


## The shoulders' shadow uvs (`Deformation.texture_uvs`) of random capsules are the plain sum's.
func _check_texture_uvs(t: TestContext, rng: RandomNumberGenerator) -> void:
	var worst := 0.0
	for n in 100:
		var size := Vector2(rng.randf_range(8.0, 60.0), rng.randf_range(8.0, 60.0))
		var angle := rng.randf_range(-TAU, TAU)
		var poly: PackedVector2Array = BodyLimbs.capsule(
			Vector2.ZERO,
			Vector2(rng.randf_range(1.0, 20.0), 0.0).rotated(angle),
			6.0,
			4.0,
		)
		var plain := PackedVector2Array()
		for p in poly:
			plain.append(p.rotated(-angle) / size + Vector2(0.5, 0.5))
		worst = maxf(worst, _gap(Deformation.texture_uvs(poly, size, angle), plain))
	t.check(
		worst <= TOLERANCE * 0.01,
		"texture uvs: the farthest is %.8f from the plain sum's" % worst,
	)


## A circle's `base_ring` is the plain sum's, and a fresh array on every call.
func _check_rings(t: TestContext) -> void:
	var worst := 0.0
	for diameter in [6.0, 12.5, 28.0, 64.0]:
		var plain := PackedVector2Array()
		var count: int = maxi(3, PhysicsDeformConfig.circle_points)
		for i in count:
			var at := TAU * float(i) / float(count)
			plain.append(Vector2(cos(at), sin(at)) * diameter * 0.5)
		var ring := Deformation.base_ring("circle", Vector2(diameter, diameter))
		worst = maxf(worst, _gap(ring, plain))
		# The caller's own copy: changing it must change no later ring.
		ring.append(Vector2(999.0, 999.0))
	var again := Deformation.base_ring("circle", Vector2(64.0, 64.0))
	t.check(
		again.size() == maxi(3, PhysicsDeformConfig.circle_points)
			and not again.has(Vector2(999.0, 999.0)),
		"a circle's ring is a fresh array on every call (%d points)" % again.size(),
	)
	t.check(
		worst <= TOLERANCE,
		"circle rings: the farthest point is %.6f px from the plain sum's" % worst,
	)


## The falling targets' trunk slices (as drawn and on the floor shadow) and outline, every frame
## for 90 frames, are the plain sums'.
func _check_fallen(t: TestContext) -> void:
	var frames := 0
	var outlines_differ := 0
	var worst := 0.0
	for f in 90:
		await t.frames(1)
		for i in TARGETS:
			var body := t.actor(StringName("target%d" % i))
			var rd = body.anatomy.ragdoll
			if rd == null:
				continue
			var fallen = body.get_node("Visuals")
			worst = maxf(worst, _trunk_gap(fallen, rd))
			if fallen.laid.trunk._outline(rd) != _plain_outline(fallen.laid.trunk.hulls(rd)):
				outlines_differ += 1
			frames += 1
	t.check(frames >= 60, "falling trunks compared (%d)" % frames)
	t.check(
		worst == 0.0,
		"fallen trunk slices are the plain sum's exactly (the farthest point is %.6f px off)"
			% worst,
	)
	t.check(
		outlines_differ == 0,
		"the fallen trunk's outline is the plain union's in every frame (%d differ)"
			% outlines_differ,
	)


## The farthest a slice of `fallen`'s trunk (ragdoll `rd`), as drawn and on the floor shadow, lies
## from the plain sum's outline either way (INF when they count different slices).
func _trunk_gap(fallen: Node, rd: RefCounted) -> float:
	var worst := 0.0
	for shift in [Vector2.ZERO, fallen.shadow.shift()]:
		var hulls: Array = fallen.laid.trunk.hulls(rd, shift)
		var plain := _plain_hulls(fallen, rd, shift)
		if hulls.size() != plain.size():
			worst = INF
			continue
		for k in hulls.size():
			worst = maxf(
				worst,
				maxf(_outline_gap(hulls[k], plain[k]), _outline_gap(plain[k], hulls[k])),
			)
	return worst


## Whether `poly` turns the same way at every corner (straight allowed): convex.
func _convex(poly: PackedVector2Array) -> bool:
	var sign_ := 0.0
	for i in poly.size():
		var turn := (poly[(i + 1) % poly.size()] - poly[i]).cross(poly[(i + 2) % poly.size()]
				- poly[(i + 1) % poly.size()])
		if absf(turn) < 1e-9:
			continue
		if sign_ == 0.0:
			sign_ = signf(turn)
		elif signf(turn) != sign_:
			return false
	return true


## The largest distance between matching points of `a` and `b` (INF when their sizes differ).
func _gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() != b.size():
		return INF
	var out := 0.0
	for i in a.size():
		out = maxf(out, a[i].distance_to(b[i]))
	return out


## The farthest any corner of `a` lies from the outline of `b`: a hull's corners can differ where
## three of its points are all but in line, while the outline they make is the same.
func _outline_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var out := 0.0
	for p in a:
		var near := INF
		for i in b.size():
			near = minf(
				near,
				p.distance_to(Geometry2D.get_closest_point_to_segment(
					p, b[i], b[(i + 1) % b.size()],
				)),
			)
		out = maxf(out, near)
	return out


## `BodyTrunk._outline` as it was: every union's pieces weighed by their area.
func _plain_outline(hulls: Array) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for hull in hulls:
		if outline.is_empty():
			outline = hull
			continue
		var best := PackedVector2Array()
		var best_area := 0.0
		var outer := 0
		for poly in Geometry2D.merge_polygons(outline, hull):
			var area: float = BodyTrunk._area(poly)
			if area > best_area:
				best = poly
				best_area = area
			if not Geometry2D.is_polygon_clockwise(poly) and area > BodyTrunk.PIECE_MIN_AREA:
				outer += 1
		if outer > 1:
			outline = BodyTrunk._open(Geometry2D.convex_hull(outline + hull))
		else:
			outline = best if best.size() >= 3 else outline
	if Geometry2D.triangulate_polygon(outline).is_empty():
		var everything := PackedVector2Array()
		for hull in hulls:
			everything.append_array(hull)
		outline = BodyTrunk._open(Geometry2D.convex_hull(everything))
	return outline


## `BodyLimbs.capsule` as it was: each point from its own angle.
func _plain_capsule(a: Vector2, b: Vector2, ra: float, rb: float) -> PackedVector2Array:
	var points: int = 6  # BodyLimbs.CAP_POINTS
	var span := a.distance_to(b)
	var out := PackedVector2Array()
	if span < 0.5:
		var rad := maxf(ra, rb)
		for k in points * 2:
			out.append(a + Vector2.from_angle(TAU * k / (points * 2)) * rad)
		return out
	var base := (b - a).angle()
	for k in points + 1:
		out.append(a + Vector2.from_angle(base + PI * 0.5 + PI * k / points) * ra)
	for k in points + 1:
		out.append(b + Vector2.from_angle(base - PI * 0.5 + PI * k / points) * rb)
	return out


## `BodyTrunk.hulls` as it was: each ring point placed in 3D, then seen from above shifted by its
## height.
func _plain_hulls(visuals: Node, rd: RefCounted, shift: Vector2) -> Array:
	var r: float = visuals.get_parent().radius
	var basis: Basis = rd.torso()
	var pelvis: Vector3 = rd.point(visuals.Rig.PELVIS)
	var spine: float = (rd.point(visuals.Rig.CHEST) - pelvis).length()
	var rings := []
	for t in BodyTrunk._steps():
		var centre: Vector3 = pelvis + basis.y * t * spine
		var half: Vector2 = BodyTrunk._section_at(t) * r
		rings.append(_plain_ring(centre, basis, half, shift))
	var hulls := []
	for k in range(1, rings.size()):
		hulls.append(
			BodyTrunk._grown(BodyTrunk._open(Geometry2D.convex_hull(rings[k - 1] + rings[k]))),
		)
	return hulls


## One trunk section's ring as `BodyTrunk.hulls` placed it: `SECTION_POINTS` points round `centre`
## in the torso's `basis`, `half` its half-width and half-depth, seen from above shifted by `shift`
## a unit of height.
func _plain_ring(
	centre: Vector3,
	basis: Basis,
	half: Vector2,
	shift: Vector2,
) -> PackedVector2Array:
	var count: int = BodyTrunk.SECTION_POINTS
	var ring := PackedVector2Array()
	for k in count:
		var around := Vector2.from_angle(TAU * k / count)
		var p: Vector3 = centre + basis.x * around.x * half.x + basis.z * around.y * half.y
		ring.append(Vector2(p.x, p.y) + shift * p.z)
	return ring
