class_name BodyLimbs extends RefCounted
## The body's limbs (`character_visuals.gd`'s `limbs`): tapered capsules between 3D joints, drawn
## the same from the standing rig or the fallen ragdoll. Each limb is a chain of segments (the arm:
## the upper arm and the forearm; the leg: the thigh, the shin in two parts or a boot's shaft, and
## the shoe), each painted in what the dress gives it, and drawn under one continuous outline with
## its art (limb_painter.gd) mapped along its capsule, into the visuals' kept meshes. The capsule
## geometry is shared with the shadow. Built once by the visuals.

const LimbPainter = preload("res://scenes/character/body/art/limb_painter.gd")
const Rig = preload("res://scenes/character/body/character_rig.gd")
## How far down the shin (0 knee .. 1 ankle) a boot's shaft reaches, and how much wider (body radii)
## a boot is than a shoe.
const BOOT_TOP := 0.62
const BOOT_GROW := 0.06
## No painter options: the plain strip.
const _PLAIN := {}
## Points sampled around each limb end.
const CAP_POINTS := 6

## How much the ends' radii of a convex capsule may differ, per px of its length: under the tangent
## of a cap's half step (15°), with room.
static var CAP_CONVEX := tan(PI / (2.0 * CAP_POINTS)) * 0.9
## Unit points round a capsule's ends in its own frame (x along it): the cap behind `a` from one
## side round to the other, the cap ahead of `b`, and the whole round of a capsule whose ends meet.
## `capsule` turns, scales and places them.
static var _CAP_BEHIND := _arc(PI * 0.5, PI / CAP_POINTS, CAP_POINTS + 1)
static var _CAP_AHEAD := _arc(-PI * 0.5, PI / CAP_POINTS, CAP_POINTS + 1)
static var _CAP_ROUND := _arc(0.0, TAU / (CAP_POINTS * 2), CAP_POINTS * 2)

## The limb chains last built (`chains`), the joints they were built from and the physics frame.
var _chains: Array = []
var _of: RefCounted = null
var _frame := -1
## The visuals the limbs are drawn by: their kept meshes and the art they painted.
var _visuals: Node2D
## The character: its radius.
var _character: Node
## What each limb is drawn in.
var _dress: BodyDress


## The limbs of `visuals`' body (`character`), drawn in `dress`.
func _init(visuals: Node2D, character: Node, dress: BodyDress) -> void:
	_visuals = visuals
	_character = character
	_dress = dress


## Forget the limb chains last built, so the next ask builds them again (`chains`).
func drop() -> void:
	_of = null


## The limb chains from the joints of `j` (the rig, or the ragdoll), legs then arms:
## `[leg 0, leg 1, arm 0, arm 1]`. The body's draw and its shadow's ask for the same chains, so they
## are built once for both: kept for the same joints within one physics frame, and dropped
## (`drop`) at every one of the visuals' `_process` (before the draws, and before the look is
## resolved again: the ragdoll may have stepped since an earlier ask in the same frame, or the look
## changed).
func chains(j: RefCounted) -> Array:
	var frame := Engine.get_physics_frames()
	if not is_same(j, _of) or frame != _frame:
		_chains = [_leg_chain(j, 0), _leg_chain(j, 1), _arm_chain(j, 0), _arm_chain(j, 1)]
		_of = j
		_frame = frame
	return _chains


## Side `i`'s arm as a limb chain from the joints of `j` (the rig or the ragdoll): the upper arm to
## the elbow, the forearm to the center of the fist, each a sleeve, bare skin or chrome
## (`_dress.arm_parts`).
func _arm_chain(j: RefCounted, i: int) -> Dictionary:
	var r: float = _character.radius
	var arm: Array = CharacterArtConfig.body_arm_widths
	var shoulder: Vector3 = j.point(Rig.SHOULDER[i])
	var elbow: Vector3 = j.point(Rig.ELBOW[i])
	var hand: Vector3 = j.point(Rig.HAND[i])
	var upper: Dictionary = _dress.arm_parts[i]["upper"]
	var fore: Dictionary = _dress.arm_parts[i]["fore"]
	return chain_of([
		painted(
			segment(shoulder, elbow, arm[0], arm[1], CharacterBodyConfig.upper_arm * r),
			upper["color"],
			upper["opts"],
		),
		painted(
			segment(elbow, hand, arm[1], arm[2], CharacterBodyConfig.forearm * r),
			fore["color"],
			fore["opts"],
		),
	])


## Side `i`'s leg as a limb chain from the joints of `j`: the thigh, the shin in two parts (the
## calf is wider than the ankle, and in chrome below the knee on a chrome leg) and the shoe along
## the way the foot points; in boots the shin's lower part is the boot's shaft and the boot is a
## little wider.
func _leg_chain(j: RefCounted, i: int) -> Dictionary:
	var r: float = _character.radius
	var leg: Array = CharacterArtConfig.body_leg_widths
	var knee: Vector3 = j.point(Rig.KNEE[i])
	var ankle: Vector3 = j.point(Rig.ANKLE[i])
	var calf := knee.lerp(ankle, 0.35)
	var shin := CharacterBodyConfig.shin * r
	var opts: Dictionary = _dress.leg_opts[i]
	var segs := [
		painted(
			segment(j.point(Rig.HIP[i]), knee, leg[0], leg[1], CharacterBodyConfig.thigh * r),
			_dress.pants,
			opts["thigh"],
		),
		painted(segment(knee, calf, leg[1], leg[2], shin * 0.35), _dress.pants, opts["knee"]),
	]
	if _dress.boots:
		_add_boot(segs, j, i, calf)
	else:
		segs.append(painted(
			segment(calf, ankle, leg[2], leg[3], shin * 0.65), _dress.shin_colour(i), opts["shin"],
		))
		segs.append(_foot_seg(j, i, 0.0))
	return chain_of(segs)


## Side `i`'s boot added to its leg's `segs` from the joints of `j`: the shin from the `calf` to the
## boot's top, the boot's shaft down to the ankle, a little wider, and the boot.
func _add_boot(segs: Array, j: RefCounted, i: int, calf: Vector3) -> void:
	var leg: Array = CharacterArtConfig.body_leg_widths
	var knee: Vector3 = j.point(Rig.KNEE[i])
	var ankle: Vector3 = j.point(Rig.ANKLE[i])
	var r: float = _character.radius
	var shin := CharacterBodyConfig.shin * r
	var opts: Dictionary = _dress.leg_opts[i]
	var top := knee.lerp(ankle, BOOT_TOP)
	var top_width: float = lerpf(leg[2], leg[3], (BOOT_TOP - 0.35) / 0.65) + BOOT_GROW
	segs.append(painted(
		segment(calf, top, leg[2], top_width - BOOT_GROW, shin * (BOOT_TOP - 0.35)),
		_dress.shin_colour(i),
		opts["shin"],
	))
	segs.append(painted(
		segment(top, ankle, top_width, leg[3] + BOOT_GROW, shin * (1.0 - BOOT_TOP)),
		_dress.shoes,
		opts["shaft"],
	))
	segs.append(_foot_seg(j, i, BOOT_GROW))


## Side `i`'s shoe (`grow` body radii wider: a boot) along the way the foot of `j` points, a
## quarter of it behind the ankle.
func _foot_seg(j: RefCounted, i: int, grow: float) -> Dictionary:
	var shoe: Array = CharacterArtConfig.body_shoe_widths
	var ankle: Vector3 = j.point(Rig.ANKLE[i])
	var toes: Vector3 = j.toes(i)
	var r: float = _character.radius
	var foot := CharacterBodyConfig.foot * r
	var heel := ankle - toes * foot * 0.25
	var tip := ankle + toes * foot * 0.75
	return painted(
		segment(heel, tip, shoe[0] + grow, shoe[1] + grow, foot),
		_dress.shoes,
		_dress.leg_opts[i]["foot"],
	)


## One tapered limb segment from `a` to `b` (3D): its widths at each end in body radii and the true
## `length` (px) its art is painted at (`painted` gives it its colour and options).
func segment(
	a: Vector3,
	b: Vector3,
	width_a: float,
	width_b: float,
	length: float,
) -> Dictionary:
	var r: float = _character.radius
	return { "a": a, "b": b, "ra": width_a * r * 0.5, "rb": width_b * r * 0.5, "length": length }


## Segment `seg` painted in `color` with its painter options `opts` (its `material` among them).
static func painted(seg: Dictionary, color: Color, opts: Dictionary = _PLAIN) -> Dictionary:
	seg["color"] = color
	seg["opts"] = opts
	return seg


## A limb chain: its segments, sorted as one part by their mean height.
func chain_of(segs: Array) -> Dictionary:
	var height := 0.0
	for seg in segs:
		height += ((seg["a"] as Vector3).z + (seg["b"] as Vector3).z) * 0.5
	return { "kind": "chain", "segs": segs, "height": height / segs.size() }


## A limb chain: every segment first a pixel wider in its outline tone, then every fill over them
## (lowest first), so the joints run together under one continuous outline.
func draw_chain(chain: Dictionary) -> void:
	var outlines := FillBatch.new(_visuals)
	# The segments by mean height, lowest first; a tie keeps the chain's order.
	var order: Array = []
	var heights: Array[float] = []
	for seg in chain["segs"]:
		_outline_seg(outlines, seg)
		var height := (seg["a"] as Vector3).z + (seg["b"] as Vector3).z
		var at := order.size()
		while at > 0 and height < heights[at - 1]:
			at -= 1
		order.insert(at, seg)
		heights.insert(at, height)
	outlines.flush()
	for seg in order:
		_draw_segment(seg)


## Segment `seg`'s capsule a pixel wider all round added to `outlines`, in its colour's outline tone
## (ArtSurfaceConfig.tones).
static func _outline_seg(outlines: FillBatch, seg: Dictionary) -> void:
	var a3: Vector3 = seg["a"]
	var b3: Vector3 = seg["b"]
	var a := Vector2(a3.x, a3.y)
	var b := Vector2(b3.x, b3.y)
	var ra: float = seg["ra"] + 1.0
	var rb: float = seg["rb"] + 1.0
	var tone := (seg["color"] as Color).darkened(ArtSurfaceConfig.tone_outline)
	fill_capsule(outlines, capsule(a, b, ra, rb), convex(a, b, ra, rb), tone)


## One limb segment's art (a shaded strip from limb_painter.gd) mapped onto its tapered capsule:
## across the strip runs across the limb, along it from end to end.
func _draw_segment(seg: Dictionary) -> void:
	var a := flat(seg["a"])
	var b := flat(seg["b"])
	var ra: float = seg["ra"]
	var rb: float = seg["rb"]
	var span := a.distance_to(b)
	var dir := (b - a) / span if span > 0.01 else Vector2.DOWN
	var widest := maxf(ra, rb)
	var tex := PixelArt.render_turned(
		LimbPainter,
		Vector2(roundf(widest * 2.0), roundf(float(seg["length"]) + ra + rb)),
		seg["color"],
		PixelArt.snap_angle(dir.angle() - PI * 0.5),
		seg["opts"],
	)
	_visuals.art.append(tex)
	var poly := capsule(a, b, ra, rb)
	_visuals.meshes.draw(
		poly, _strip_uvs(a, dir, span, ra, rb) * poly, tex, Color.WHITE,
		Rect2(a.min(b), (b - a).abs()).grow(widest),
	)


## The transform from canvas px to a strip's uvs on the capsule from `a` (radius `ra`) `span` px
## along `dir` to its other end (`rb`): across the strip, the offset from the axis over the strip's
## width; along it, from `ra` behind `a` over the whole length.
static func _strip_uvs(a: Vector2, dir: Vector2, span: float, ra: float, rb: float) -> Transform2D:
	var across := dir.orthogonal() / (maxf(ra, rb) * 2.0)
	var along := dir / (span + ra + rb)
	return Transform2D(Vector2(across.x, along.x), Vector2(across.y, along.y),
		Vector2(0.5 - across.dot(a), (ra - dir.dot(a)) / (span + ra + rb)))


## A tapered capsule outline from `a` (radius `ra`) to `b` (radius `rb`): a round cap behind each
## end joined by straight sides; a circle when the ends meet (a limb pointing at the camera).
static func capsule(a: Vector2, b: Vector2, ra: float, rb: float) -> PackedVector2Array:
	var span := a.distance_to(b)
	if span < 0.5:
		var rad := maxf(ra, rb)
		return Transform2D(0.0, Vector2(rad, rad), 0.0, a) * _CAP_ROUND
	var base := (b - a).angle()
	var out := Transform2D(base, Vector2(ra, ra), 0.0, a) * _CAP_BEHIND
	out.append_array(Transform2D(base, Vector2(rb, rb), 0.0, b) * _CAP_AHEAD)
	return out


## Add the capsule `poly` (`capsule(a, b, ra, rb)`) to `fills` (a `FillBatch` or a
## `BodyMeshes.Solid`) in `color`: as a fan without being cut when it is convex (`is_convex`, from
## `convex`), else cut as the engine cuts it.
static func fill_capsule(
	fills: RefCounted,
	poly: PackedVector2Array,
	is_convex: bool,
	color: Color,
) -> void:
	if is_convex:
		fills.fill_convex(poly, color)
	else:
		fills.fill(poly, color)


## Whether the capsule from `a` (radius `ra`) to `b` (`rb`) is convex: one whose ends' radii differ
## by less than `CAP_CONVEX` of its length (each cap ends half a step, 15°, short of its side, which
## leans by `atan(|ra - rb| / span)`), or a circle.
static func convex(a: Vector2, b: Vector2, ra: float, rb: float) -> bool:
	var span := a.distance_to(b)
	return span < 0.5 or absf(ra - rb) < span * CAP_CONVEX


## `count` unit vectors from angle `from`, `step` apart.
static func _arc(from: float, step: float, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in count:
		out.append(Vector2.from_angle(from + step * k))
	return out


## A 3D point's place on the floor plane, seen from above.
static func flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.y)
