class_name BodyHeights
## General domain, the one holder of a body's real proportions (#194, D5; the sources and the
## method are `docs/research/3d-cover-heights.md`): the scale between metres and the sim's px, and
## each posture's eye, muzzle (bore) and head-top height and its hit-zone bands. A `class_name`
## holder of `static var`s, read as `BodyHeights.<name>` (ADR 0003), so a test can `set_static`.
##
## **Scale.** 1 3D unit is 1 px (`RenderConfig.unit`) and a 1.75 m person stands 74 px, so a metre
## is 74 / 1.75 = 42.3 px. Every height here is px above the floor; a mesh or a collider is built
## from the same px (the furniture's tops are `PieceHeights`), so a number means one thing.
##
## **Postures.** `STAND`; `DUCK` (D7, a crouch that hides behind low cover: head top about 0.85 m,
## so a piece of at least that top hides the whole body); `FIRE_OVER` (the pose a ducked character
## rises to when its muzzle line is blocked by the cover it is behind: head and shoulders above
## about 0.9 to 1.0 m cover, its bore clearing 0.9 m). Metres are the research note's: standing
## eye = stature minus 0.12 (1.64), bore = eye minus 0.065 (1.55); the duck and the fire-over are
## geometric estimates, tunable.

const STAND := &"stand"
const DUCK := &"duck"
const FIRE_OVER := &"fire_over"
## No posture: `lowest_clearing`'s answer for a piece too tall to fire over.
const NONE := &""

## A standing person: stature in metres and in px (the scale's two ends).
static var person_metres: float = 1.75
static var person_px: float = 74.0
## Per posture, in metres: `head` (top of the head), `eye`, `muzzle` (a rifle's bore line),
## `shoulder` and `zones`: `[name, highest metre]`, feet up, anything above the last row is the
## head. A standing body's torso starts at the crotch (0.90 m: ANSUR II trochanter height) and ends
## at the neck base (1.52); a duck and a fire-over are the same body folded, its bands scaled with
## it.
static var postures: Dictionary = {
	&"stand": {
		"head": 1.75, "eye": 1.64, "muzzle": 1.55, "shoulder": 1.44,
		"zones": [[&"feet", 0.10], [&"legs", 0.90], [&"torso", 1.52]],
	},
	&"duck": {
		"head": 0.85, "eye": 0.76, "muzzle": 0.70, "shoulder": 0.68,
		"zones": [[&"feet", 0.06], [&"legs", 0.42], [&"torso", 0.72]],
	},
	&"fire_over": {
		"head": 1.22, "eye": 1.10, "muzzle": 1.02, "shoulder": 0.96,
		"zones": [[&"feet", 0.08], [&"legs", 0.55], [&"torso", 1.00]],
	},
}


## How many px a metre is: 42.3.
static func px_per_metre() -> float:
	return person_px / person_metres


## `length` (metres) in px.
static func px(length: float) -> float:
	return length * px_per_metre()


## `pixels` in metres.
static func metres(pixels: float) -> float:
	return pixels / px_per_metre()


## Every posture's id, standing first.
static func postures_ids() -> Array:
	return [STAND, DUCK, FIRE_OVER]


## The height (px) of the top of `posture`'s head.
static func head_top(posture: StringName) -> float:
	return _px_of(posture, "head")


## `posture`'s head top as a share of a standing body's (1 for standing): how tall a body drawn in
## it is next to a standing one, so the drawn crouch and the twin are one height.
static func height_share(posture: StringName) -> float:
	return head_top(posture) / head_top(STAND)


## The height (px) of `posture`'s eye: where a sight line starts.
static func eye(posture: StringName) -> float:
	return _px_of(posture, "eye")


## The height (px) of `posture`'s muzzle (bore) line: where a bullet starts.
static func muzzle(posture: StringName) -> float:
	return _px_of(posture, "muzzle")


## The height (px) of `posture`'s shoulders: with the head, what shows over a piece of cover.
static func shoulder(posture: StringName) -> float:
	return _px_of(posture, "shoulder")


## `posture`'s hit-zone bands, feet up: `[name, from, to]` in px, touching, the last (`head`) ending
## at the head top. (O2 and O3 of `docs/outfits.md` will read the zone a hit falls in.)
static func zones(posture: StringName) -> Array:
	var rows: Array = _row(posture)["zones"]
	var out: Array = []
	var from := 0.0
	for row: Array in rows:
		var to := px(row[1])
		out.append([row[0], from, to])
		from = to
	out.append([&"head", from, head_top(posture)])
	return out


## The heights (px) of the points sight looks at on a body in `posture`, the head first (its
## centre, at the eye), then the chest (the middle of the torso band) and the hips (where the legs
## end): a body is seen if a line from an eye is clear to any one of them (`SightRay`).
static func sight_points(posture: StringName) -> PackedFloat32Array:
	var rows: Array = _row(posture)["zones"]
	var legs_end := px(rows[1][1])
	var torso_end := px(rows[2][1])
	return PackedFloat32Array([eye(posture), 0.5 * (legs_end + torso_end), legs_end])


## The lowest posture whose muzzle line clears a piece of cover `top` px tall, or `NONE` when no
## posture does (the cover is too tall to fire over: fire around it). A body rises only as far as
## it must: the duck itself for cover under its own muzzle, `FIRE_OVER` up to its muzzle (about
## 1.0 m), `STAND` for taller cover up to a standing muzzle (about 1.55 m). A muzzle level with
## the top does not clear it.
static func lowest_clearing(top: float) -> StringName:
	var best := NONE
	var best_muzzle := INF
	for posture: StringName in postures_ids():
		var line := muzzle(posture)
		if line > top and line < best_muzzle:
			best = posture
			best_muzzle = line
	return best


## The zone of `posture`'s body a hit at `height` px up falls in: under the floor is the feet,
## over the head is the head.
static func zone_at(posture: StringName, height: float) -> StringName:
	var rows: Array = _row(posture)["zones"]
	for row: Array in rows:
		if height <= px(row[1]):
			return row[0]
	return &"head"


## The `key` height of `posture`, in px.
static func _px_of(posture: StringName, key: String) -> float:
	return px(float(_row(posture)[key]))


## `posture`'s row of `postures` (a standing one for an id it has not).
static func _row(posture: StringName) -> Dictionary:
	return postures.get(posture, postures[STAND])
