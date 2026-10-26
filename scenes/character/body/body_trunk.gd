class_name BodyTrunk extends RefCounted
## The laid-out body's trunk: a crouched or fallen body's torso seen from above, drawn from the
## joints of the rig or the ragdoll. Its outline is lofted through cross-sections up the spine
## (ellipses eased between CharacterArtConfig.ragdoll_trunk_sections and domed at both ends), so it
## is waisted and rounded from any side and foreshortens as it tips; the art of the sides turned to
## the camera is mapped across it, and the shots the body took while alive show as wounds on
## whatever skin faces up. The shadow draws its slices (`hulls`). Built once by the visuals.

const BodyPainter = preload("res://scenes/character/body/art/body_painter.gd")
const TorsoPainter = preload("res://scenes/character/body/art/torso_painter.gd")
const Rig = preload("res://scenes/character/body/character_rig.gd")
## Points sampled around each trunk cross-section.
const SECTION_POINTS := 16
## Cross-sections the trunk's outline is lofted through between its ends, and in each end's dome.
const TRUNK_STEPS := 10
const DOME_STEPS := 3
## How far past the end sections the domes reach (spine fractions): over the shoulders, under the
## hips.
const DOME_TOP := 0.12
const DOME_BOTTOM := 0.1
## Px each slice of the trunk's outline grows by so neighbouring slices overlap in area, and the
## area (px²) above which a piece of their union counts as a body part rather than a sliver.
const HULL_OVERLAP := 0.5
const PIECE_MIN_AREA := 1.0
## A wound shows once its patch of skin turns at least this far (its normal's z) to the camera.
const WOUND_MIN_FACING := 0.3

## The unit ring a trunk cross-section is sampled on (`hulls`): point `k` at angle
## `TAU * k / SECTION_POINTS`.
static var _SECTION_RING := _ring(SECTION_POINTS)

## The visuals the trunk is drawn by: their canvas, kept meshes and the art they painted.
var _visuals: Node2D
## The character: its radius and its wounds.
var _character: Node
## What the trunk is drawn in.
var _dress: BodyDress


## The trunk of `visuals`' body (`character`), drawn in `dress`.
func _init(visuals: Node2D, character: Node, dress: BodyDress) -> void:
	_visuals = visuals
	_character = character
	_dress = dress


## `count` unit vectors round the circle, `k` at angle `TAU * k / count`.
static func _ring(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in count:
		out.append(Vector2.from_angle(TAU * k / count))
	return out


## The trunk's cross-section at spine fraction `t` (0 = hip joints, 1 = shoulder joints) as
## Vector2(half-width, half-depth) in body radii, eased between the configured sections so the
## outline curves; past either end it rounds off in a dome.
static func _section_at(t: float) -> Vector2:
	var sections: Array = CharacterArtConfig.ragdoll_trunk_sections
	var first: Vector3 = sections[0]
	var last: Vector3 = sections[sections.size() - 1]
	if t < first.x:
		return Vector2(first.y, first.z) * _dome((first.x - t) / DOME_BOTTOM)
	if t > last.x:
		return Vector2(last.y, last.z) * _dome((t - last.x) / DOME_TOP)
	for k in range(1, sections.size()):
		var hi: Vector3 = sections[k]
		if t <= hi.x:
			var lo: Vector3 = sections[k - 1]
			var w := smoothstep(0.0, 1.0, (t - lo.x) / maxf(hi.x - lo.x, 0.001))
			return Vector2(lerpf(lo.y, hi.y, w), lerpf(lo.z, hi.z, w))
	return Vector2(last.y, last.z)


## A dome's width `s` of the way (0..1) from its base to its tip.
static func _dome(s: float) -> float:
	return sqrt(maxf(1.0 - 0.85 * s * s, 0.0))


## The spine fractions the trunk's outline is lofted through: the domes under the hips and over the
## shoulders, and evenly between them.
static func _steps() -> PackedFloat32Array:
	var sections: Array = CharacterArtConfig.ragdoll_trunk_sections
	var t0: float = (sections[0] as Vector3).x
	var t1: float = (sections[sections.size() - 1] as Vector3).x
	var out := PackedFloat32Array()
	for k in range(DOME_STEPS, 0, -1):
		out.append(t0 - DOME_BOTTOM * k / DOME_STEPS)
	for k in TRUNK_STEPS + 1:
		out.append(lerpf(t0, t1, float(k) / TRUNK_STEPS))
	for k in range(1, DOME_STEPS + 1):
		out.append(t1 + DOME_TOP * k / DOME_STEPS)
	return out


## The trunk's outline seen from above, each point shifted by `shift` per px of its height (zero: as
## drawn; `BodyShadow.shift`: on the floor shadow): the union of the hulls of each pair of
## neighbouring cross-sections (ellipses across the spine, eased between
## CharacterArtConfig.ragdoll_trunk_sections and domed at both ends), so it is waisted and rounded
## from any side and shrinks to the shoulders seen from above.
func _outline(rd: RefCounted, shift := Vector2.ZERO) -> PackedVector2Array:
	var outline := PackedVector2Array()
	var slices := hulls(rd, shift)
	for hull in slices:
		if outline.is_empty():
			outline = hull
			continue
		var merged := Geometry2D.merge_polygons(outline, hull)
		if merged.size() == 1:
			# One piece (most merges): it is the largest and the only outer one, whatever its area
			# (a union of slices has some).
			outline = merged[0] if merged[0].size() >= 3 else outline
			continue
		var best := PackedVector2Array()
		var best_area := 0.0
		var outer := 0
		for poly in merged:
			var area := _area(poly)
			if area > best_area:
				best = poly
				best_area = area
			if not Geometry2D.is_polygon_clockwise(poly) and area > PIECE_MIN_AREA:
				outer += 1
		if outer > 1:
			# The union came apart (two outer pieces): keep both slices in one hull rather than
			# drop the body so far.
			outline = _open(Geometry2D.convex_hull(outline + hull))
		else:
			# The union's outer boundary is its largest piece (any others would be holes).
			outline = best if best.size() >= 3 else outline
	if Geometry2D.triangulate_polygon(outline).is_empty():
		var everything := PackedVector2Array()
		for hull in slices:
			everything.append_array(hull)
		outline = _open(Geometry2D.convex_hull(everything))
	return outline


## The trunk's slices seen from above, shifted by `shift` per px of height (as `_outline`):
## the hull of each pair of neighbouring cross-sections (ellipses across the spine, eased between
## CharacterArtConfig.ragdoll_trunk_sections and domed at both ends), each grown by `HULL_OVERLAP`.
## Their union is the trunk's outline (`_outline`); the shadow draws them as they are.
func hulls(rd: RefCounted, shift := Vector2.ZERO) -> Array[PackedVector2Array]:
	var r: float = _character.radius
	var basis: Basis = rd.torso()
	var pelvis: Vector3 = rd.point(Rig.PELVIS)
	var spine: float = (rd.point(Rig.CHEST) - pelvis).length()
	var rings := []
	for t in _steps():
		var centre: Vector3 = pelvis + basis.y * t * spine
		var half := _section_at(t) * r
		var ring := PackedVector2Array()
		for around in _SECTION_RING:
			ring.append(
				BodyShadow.cast(
					centre + basis.x * around.x * half.x + basis.z * around.y * half.y, shift,
				),
			)
		rings.append(ring)
	var out: Array[PackedVector2Array] = []
	for k in range(1, rings.size()):
		out.append(_grown(_open(Geometry2D.convex_hull(rings[k - 1] + rings[k]))))
	return out


## `poly` grown by `HULL_OVERLAP`, so neighbouring slices of the trunk overlap in area. They share a
## ring, which seen edge-on is a line, and slices touching along a line can come out of the union as
## separate pieces.
static func _grown(poly: PackedVector2Array) -> PackedVector2Array:
	var grown := Geometry2D.offset_polygon(poly, HULL_OVERLAP, Geometry2D.JOIN_MITER)
	return grown[0] if grown.size() == 1 else poly


## The area enclosed by `poly`, whichever way it winds.
static func _area(poly: PackedVector2Array) -> float:
	var twice := 0.0
	for k in poly.size():
		twice += poly[k].cross(poly[(k + 1) % poly.size()])
	return absf(twice) * 0.5


## `poly` without a closing point that repeats its first.
static func _open(poly: PackedVector2Array) -> PackedVector2Array:
	if poly.size() > 1 and poly[0].is_equal_approx(poly[poly.size() - 1]):
		poly.remove_at(poly.size() - 1)
	return poly


## The trunk: a shirt-colored underfill of its outline, the art of the sides turned to the camera
## mapped across it (`_faces`: the chest, the back or a flank, with the shoulders' top over it
## when that is the side most turned up), a 1 px outline, then the wounds on whatever skin faces up.
func draw(rd: RefCounted) -> void:
	var outline := _outline(rd)
	if outline.size() < 3:
		return
	_visuals.draw_colored_polygon(outline, _dress.shirt)
	for face in _faces(rd):
		var ax: Vector2 = face["x"]
		var ay: Vector2 = face["y"]
		var size: Vector2 = face["size"]
		var det := ax.x * ay.y - ax.y * ay.x
		if absf(det) <= 0.0001:
			continue
		var uvs := PackedVector2Array()
		for p in outline:
			var rel: Vector2 = p - face["center"]
			var u := (rel.x * ay.y - rel.y * ay.x) / det
			var v := (ax.x * rel.y - ax.y * rel.x) / det
			uvs.append(Vector2(u / size.x + 0.5, v / size.y + 0.5))
		_visuals.meshes.draw(outline, uvs, face["texture"])
		_visuals.art.append(face["texture"])
	var closed := outline.duplicate()
	closed.append(outline[0])
	_visuals.draw_polyline(closed, ArtSurfaceConfig.tones(_dress.shirt).outline, 1.0)
	_draw_wounds(rd)


## The trunk's sides to map across its outline, lowest first, each as its `texture`, its `center`
## and the screen vectors its art's x and y run along (per px) over its `size`: the side most turned
## to the camera of the chest, the back and a flank (the torso art, a full strip that covers the
## outline), and over it the shoulders' top when that is turned up more still (a body bent over in a
## crouch, or upright as it starts to fall). The shoulders' art covers only the shoulders, so drawn
## alone it would leave the rest of a bent back (and whatever is worn on it) bare shirt.
func _faces(rd: RefCounted) -> Array:
	var r: float = _character.radius
	var basis: Basis = rd.torso()
	var pelvis: Vector3 = rd.point(Rig.PELVIS)
	var spine: float = (rd.point(Rig.CHEST) - pelvis).length()
	var sections: Array = CharacterArtConfig.ragdoll_trunk_sections
	var bottom: float = ((sections[0] as Vector3).x - DOME_BOTTOM) * spine
	var top: float = ((sections[sections.size() - 1] as Vector3).x + DOME_TOP) * spine
	var mid: Vector3 = pelvis + basis.y * (bottom + top) * 0.5
	var faces := [
		{
			"kind": "top", "score": basis.y.z, "centre": pelvis + basis.y * top, "x": basis.x,
			"y": basis.z, "size": Vector2(2.0 * r, 2.0 * r),
		},
	]
	faces.append_array(_sides(basis, mid, top - bottom))
	var side_on: Dictionary = faces[1] if faces[1]["score"] >= faces[2]["score"] else faces[2]
	if faces[0]["score"] > side_on["score"]:
		return [_face_art(side_on), _face_art(faces[0])]
	return [_face_art(side_on)]


## The trunk's chest or back (whichever faces up) and a flank, as `_faces` scores them: turned
## by `basis`, about the trunk's `mid` point, `length` px along the spine.
func _sides(basis: Basis, mid: Vector3, length: float) -> Array:
	var r: float = _character.radius
	var depth := CharacterArtConfig.shoulder_depth * r
	var side := signf(basis.x.z) if basis.x.z != 0.0 else 1.0
	var facing := signf(basis.z.z) if basis.z.z != 0.0 else 1.0
	return [
		{
			"kind": "front" if facing > 0.0 else "back", "score": absf(basis.z.z),
			"centre": mid + basis.z * depth * facing, "x": basis.x * facing, "y": -basis.y,
			"size": Vector2(2.0 * r, length),
		},
		{
			"kind": "side", "score": absf(basis.x.z), "centre": mid + basis.x * r * side,
			"x": basis.z * -side, "y": -basis.y, "size": Vector2(2.0 * depth, length),
		},
	]


## One trunk side (`face`, from `_faces`) as the art to map: its texture, centre and screen
## axes.
func _face_art(face: Dictionary) -> Dictionary:
	var x3: Vector3 = face["x"]
	var y3: Vector3 = face["y"]
	var ax := BodyLimbs.flat(x3)
	var ay := BodyLimbs.flat(y3)
	var size: Vector2 = face["size"]
	var angle := ay.angle() - PI * 0.5 if ay.length() > 0.05 else ax.angle()  # The art's turn.
	# The art is asked for at whole pixels, as the limbs' is (`BodyLimbs._draw_segment`): the
	# spine's length changes a little every frame as the ragdoll flexes, and a size that is never
	# the same twice paints (and caches) a new texture every frame.
	var art_size := Vector2(roundf(size.x), roundf(size.y))
	var tex: Texture2D
	if face["kind"] == "top":
		tex = PixelArt.render_turned(
			BodyPainter,
			art_size,
			_dress.shirt,
			PixelArt.snap_angle(angle),
			_dress.shoulder_opts,
		)
	else:
		tex = PixelArt.render_turned(
			TorsoPainter,
			art_size,
			_dress.shirt,
			PixelArt.snap_angle(angle),
			_dress.torso_opts[face["kind"]],
		)
	return {
		"texture": tex,
		"center": BodyLimbs.flat(face["centre"]),
		"x": ax,
		"y": ay,
		"size": size,
	}


## The shots the body took while alive, as wounds on its fallen trunk: each sits around the body
## where it struck (its angle in the shoulders' frame) at a height seeded per wound between waist
## and chest, and shows only while that patch of skin faces the camera — the chest's wounds on a
## body lying on its back, the back's on one lying face down.
func _draw_wounds(rd: RefCounted) -> void:
	var deformable = _character.anatomy.deformable
	if deformable == null:
		return
	var basis: Basis = rd.torso()
	var pelvis: Vector3 = rd.point(Rig.PELVIS)
	var spine: float = (rd.point(Rig.CHEST) - pelvis).length()
	var wounds := []
	for impact in deformable.impacts:
		var wound := _wound(impact, basis, pelvis, spine)
		if not wound.is_empty():
			wounds.append(wound)
	Deformation.draw_marks(
		_visuals, wounds, CharacterArtConfig.flesh_crack_color, CharacterArtConfig.flesh_hole_color,
		CharacterArtConfig.flesh_scorch_color,
	)


## The wound `impact` left on the fallen trunk (turned by `basis`, up its `spine` px from the
## `pelvis`): around the body where it struck, at its seeded height, its depth by how squarely that
## patch faces the camera; {} while it faces away.
func _wound(impact: Dictionary, basis: Basis, pelvis: Vector3, spine: float) -> Dictionary:
	var pos: Vector2 = impact["pos"]
	if pos.length() < 0.001:
		return {}
	# Recorded with the body facing +x: its right is −y, its front +x.
	var around := Vector2(-pos.y, pos.x).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(impact["seed"])
	var t := rng.randf_range(0.35, 0.9)
	var r: float = _character.radius
	var half := _section_at(t) * r
	var on := _on_section(around, half)
	var skin: Vector3 = pelvis + basis.y * t * spine + basis.x * on.x + basis.z * on.y
	var normal: Vector3 = (basis.x * on.x / (half.x * half.x)
			+ basis.z * on.y / (half.y * half.y)).normalized()
	if normal.z < WOUND_MIN_FACING:
		return {}
	var wound: Dictionary = impact.duplicate()
	wound["pos"] = BodyLimbs.flat(skin)
	wound["inward"] = Vector2.ZERO
	wound["depth"] = float(impact["depth"]) * normal.z
	return wound


## Where the way `around` (unit, across the spine) meets the edge of a cross-section of half-width
## and half-depth `half`.
static func _on_section(around: Vector2, half: Vector2) -> Vector2:
	var reach := 1.0 / sqrt(pow(around.x / half.x, 2.0) + pow(around.y / half.y, 2.0))
	return around * reach
