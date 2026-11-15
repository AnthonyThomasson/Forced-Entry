class_name BodySolids
extends RefCounted
## Character body, the shared unit solids of the 3D body (`body_mesh.gd`; #193 phase 2b): the
## shaped parts a standing body is built from, each one mesh for every character (`MeshCache`), put
## in place by `BodyMesh` by scaling its axes. A shaped part, not a box or a ball: a trunk with a
## waist and a chest, an egg-shaped head, tapered limbs that bulge where the 2D art's widths do
## (`CharacterArtConfig.body_arm_widths`, `body_leg_widths`), a neck, a shoe with a rounded toe.
## Each is a lathe (`MeshKit.revolve`) or an extrusion (`MeshKit.extrude`) whose top is one flat
## face, so a top-down picture (the 2D art) can be laid on it.
##
## The frames: a round solid stands on the origin along +y, one unit tall, its radii the part's own
## width over the scale `BodyMesh` gives it; the head's own unit is a radius of 1 round the origin;
## a shoe is a box one unit each way over the origin, its toe along +z.

## The trunk's width over its half width (`k`) by the share of its height (`t`), pelvis to neck:
## the hips, the waist, the chest and the slope of the shoulders into the neck.
const TRUNK := [
	Vector2(0.0, 0.8), Vector2(0.1, 0.88), Vector2(0.3, 0.78), Vector2(0.55, 0.94),
	Vector2(0.75, 1.0), Vector2(0.9, 0.93), Vector2(0.97, 0.62), Vector2(1.0, 0.42),
]
## The head's outline over its radius: chin to crown (radius, height), the face a little longer
## than wide.
const HEAD := [
	Vector2(0.0, -1.12), Vector2(0.5, -1.0), Vector2(0.82, -0.62), Vector2(1.0, -0.15),
	Vector2(0.98, 0.3), Vector2(0.78, 0.78), Vector2(0.4, 1.05), Vector2(0.0, 1.12),
]
## A shoe's outline on the floor (x across, y toe-ward): a narrow heel, a wide ball, a rounded toe.
const SHOE := [
	Vector2(-0.36, -0.5), Vector2(0.36, -0.5), Vector2(0.46, -0.1), Vector2(0.5, 0.2),
	Vector2(0.42, 0.4), Vector2(0.22, 0.5), Vector2(-0.22, 0.5), Vector2(-0.42, 0.4),
	Vector2(-0.5, 0.2), Vector2(-0.46, -0.1),
]
## How round the round solids are: the trunk, the head, a limb.
const TRUNK_SIDES := 12
const HEAD_SIDES := 10
const LIMB_SIDES := 8
## The ends of a limb: how wide its flat end is over its width, and how far it rises to full width
## (over its length), so a limb is capped, not cut.
const END_FLAT := 0.75
const END_RISE := 0.04


## The shared unit solid `shape`, with `opts` the tuning it reads (the cache key's): `&"trunk"`
## (from the share of its height `from`: 0 the trunk, the vest's its own from there up), `&"head"`,
## `&"ball"`, `&"box"`, `&"shoe"`, and `&"limb"` (`radii`: pairs of share of length and width,
## flat).
static func fetch(shape: StringName, opts := {}) -> Mesh:
	var key := MeshCache.key(
		"body_solid",
		Vector2.ONE,
		Color.WHITE,
		{ "shape": shape, "opts": opts },
	)
	return MeshCache.fetch(key, _make.bind(shape, opts))


## The options of a limb solid from `radii`, widths along its length as (share of length, width)
## pairs, flat so they key the cache.
static func limb(radii: Array) -> Dictionary:
	var flat := []
	for pair: Vector2 in radii:
		flat.append_array([pair.x, pair.y])
	return { "radii": flat }


## How much of the trunk's half width a section `t` of the way up it is (0 the pelvis, 1 the neck).
static func trunk_width(t: float) -> float:
	for i in range(1, TRUNK.size()):
		var high: Vector2 = TRUNK[i]
		if t <= high.x:
			var low: Vector2 = TRUNK[i - 1]
			return lerpf(low.y, high.y, inverse_lerp(low.x, high.x, t))
	return (TRUNK[TRUNK.size() - 1] as Vector2).y


## The mesh of `fetch`.
static func _make(shape: StringName, opts: Dictionary) -> Mesh:
	var kit := MeshKit.new()
	match shape:
		&"trunk":
			kit.sides = TRUNK_SIDES
			kit.revolve(_trunk_profile(float(opts.get("from", 0.0))), Vector3.ZERO, Color.WHITE)
		&"head":
			kit.sides = HEAD_SIDES
			kit.revolve(PackedVector2Array(HEAD), Vector3.ZERO, Color.WHITE)
		&"ball":
			kit.sides = 8
			kit.sphere(Vector3.ZERO, 1.0, Color.WHITE)
		&"limb":
			kit.sides = LIMB_SIDES
			kit.revolve(_limb_profile(opts["radii"]), Vector3.ZERO, Color.WHITE)
		&"shoe":
			kit.extrude(PackedVector2Array(SHOE), 0.0, 1.0, Color.WHITE)
		_:
			kit.box(AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE), Color.WHITE)
	return kit.build()


## The trunk's outline from the share `from` of its height up, as the part's own height 0 to 1.
static func _trunk_profile(from: float) -> PackedVector2Array:
	var profile := PackedVector2Array([Vector2.ZERO, Vector2(trunk_width(from), 0.0)])
	for point: Vector2 in TRUNK:
		if point.x > from + 0.0001:
			profile.append(Vector2(point.y, (point.x - from) / (1.0 - from)))
	profile.append(Vector2(0.0, 1.0))
	return profile


## A limb's outline: a capped end, the widths (flat pairs of share of length and width) and a
## capped end, the first and last of the pairs being the ends'.
static func _limb_profile(flat: Array) -> PackedVector2Array:
	var count := flat.size() >> 1
	var first: float = flat[1]
	var last: float = flat[flat.size() - 1]
	var profile := PackedVector2Array([
		Vector2.ZERO, Vector2(first * END_FLAT, 0.0), Vector2(first, END_RISE),
	])
	for i in range(1, count - 1):
		profile.append(Vector2(float(flat[i * 2 + 1]), float(flat[i * 2])))
	profile.append(Vector2(last, 1.0 - END_RISE))
	profile.append(Vector2(last * END_FLAT, 1.0))
	profile.append(Vector2(0.0, 1.0))
	return profile
