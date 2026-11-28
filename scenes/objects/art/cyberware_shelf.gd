class_name CyberwareShelf
extends RefCounted
## Objects domain, the ripperdoc's cyberware shelf (`docs/stacked-items.md` SI16, decision D21): an
## open steel shelf that steps up in columns (a board on four posts to a tier, none over another),
## not a block with the cyberware drawn on it: the chrome arms, eyes, chips and jars it held are
## free items (`rows`, by `PieceCarries`) standing each on a board's top. Its body moves as the
## solid box of its extent (`PieceBody._as_solid`). In px in the painter's canonical frame
## (`FurnitureSpec.area`: back-left corner at (0, 0), x across, the front toward +y); `parts` are
## `{ base, top, rect }` as `PieceHeights` reads them.

const ClinicMesh = preload("res://scenes/objects/art/clinic_mesh.gd")
## The posts' side, a board's thickness (thicker than the 1.5 drawn: `ShelfMesh.HULL`'s reason) and
## the inset of the well the cyberware lies in.
const POST := 3.0
const BOARD := 2.0
const WELL := 3.0
## How far the lowest column's board's top is lifted from the floor at the least (px).
const LIFT := 2.0
## The art options its seeded layout reads (so a retuned look is another layout).
const OPTIONS := ["kind", "neon", "height"]
const ARM_WIDTH := 3.0
## The small things stacked across a column, how far apart they stand along the depth, and what they
## are; and how far one step along a column goes past an arm and past a stack (px).
const SMALL := 3
const SMALL_STRIDE := 9.0
const ARM_STEP := 4.0
const SMALL_STEP := 6.0
const SMALL_KINDS := ["cyber_eye", "cyber_chip", "cyber_jar"]


## Whether `spec` is the cyberware shelf.
static func has(spec: FurnitureSpec) -> bool:
	return spec.art == "clinic" and String(spec.opts.get("kind", "tool_cart")) == "cyberware_shelf"


## The tops (px above the floor) of the boards of `spec`, lowest first: what the cyberware stands
## on, a step to each column (the top one the shelf's height).
static func tops(spec: FurnitureSpec) -> Array[float]:
	var out: Array[float] = []
	var height := ClinicMesh.height_of(spec)
	var tiers := maxi(1, ObjectMeshTechConfig.cyber_tiers)
	for tier in tiers:
		out.append(LIFT + float(tier + 1) * (height - LIFT) / float(tiers))
	return out


## The parts of `spec` (`has`), left to right: the shelf steps up in columns, one per tier, each a
## board on four posts, and no board is over another's cyberware (the game camera looks down on
## it: tiers one over another would hide the lower ones).
static func parts(spec: FurnitureSpec) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := spec.size.y
	var wide := spec.size.x / float(maxi(1, ObjectMeshTechConfig.cyber_tiers))
	var column := 0
	for top in tops(spec):
		var x := float(column) * wide
		for post_x: float in [x, x + wide - POST]:
			for post_y: float in [0.0, d - POST]:
				_add(spec, out, Rect2(post_x, post_y, POST, POST), 0.0, top - BOARD)
		_add(spec, out, Rect2(x, 0, wide, d), top - BOARD, top)
		column += 1
	return out


## The rows of the cyberware of `spec`, laid left to right along each column: an arm lying the
## depth of the column or a stack of `SMALL` things (eyes, chips, jars) across it, `{ key, at, size,
## lift, height, color }` (`PieceCarries`), `at` from the shelf's centre.
static func rows(spec: FurnitureSpec) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not has(spec):
		return out
	var rng := spec.rng("shelf", OPTIONS)
	var well := Rect2(WELL, WELL, spec.size.x - 2.0 * WELL, spec.size.y - 2.0 * WELL)
	var wide := spec.size.x / float(maxi(1, ObjectMeshTechConfig.cyber_tiers))
	var column := 0
	for top in tops(spec):
		var x := float(column) * wide + POST + 0.5
		var end := float(column + 1) * wide - POST - 0.5
		while x <= end - 6.0:
			var arm := rng.randi_range(0, 1) == 0
			if arm:
				out.append(_row(spec, well, "cyber_arm", Vector2(x, top), well.position.y + 1.0))
			else:
				for k in SMALL:
					var key: String = SMALL_KINDS[rng.randi_range(0, 2)]
					var y := well.position.y + 1.0 + float(k) * SMALL_STRIDE
					y += rng.randf_range(0.0, 1.0)
					out.append(_row(spec, well, key, Vector2(x, top), y))
			x += ARM_STEP if arm else SMALL_STEP
		column += 1
	return out


## The row of the cyberware `key` at column `slot.x` of the `well` and `y` (its back edge), on the
## board whose top is `slot.y`.
static func _row(
	spec: FurnitureSpec,
	well: Rect2,
	key: String,
	slot: Vector2,
	y: float,
) -> Dictionary:
	var foot := Rect2(slot.x - 0.5, y, ARM_WIDTH, well.size.y - 4.0)
	var colour := ObjectArtClinicConfig.clinic_chrome_color
	match key:
		"cyber_eye":
			foot = Rect2(slot.x, y, 6.0, 6.0)
			colour = ObjectArtClinicConfig.clinic_eye_color
		"cyber_chip":
			foot = Rect2(slot.x, y, 6.0, 7.0)
			colour = ObjectArtClinicConfig.clinic_chip_color
		"cyber_jar":
			foot = Rect2(slot.x, y, 6.0, 6.0)
			colour = ObjectArtClinicConfig.clinic_jar_color
	return {
		"key": key,
		"at": foot.get_center() - spec.size * 0.5,
		"size": foot.size,
		"lift": slot.y,
		"color": colour,
		"plain": true,
	}


## One part over `area` (px), `base` to `top`.
static func _add(
	spec: FurnitureSpec,
	out: Array[Dictionary],
	area: Rect2,
	base: float,
	top: float,
) -> void:
	var size := Vector2(maxf(spec.size.x, 1.0), maxf(spec.size.y, 1.0))
	out.append({ "base": base, "top": top, "rect": Rect2(area.position / size, area.size / size) })
