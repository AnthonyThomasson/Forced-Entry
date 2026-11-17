class_name BloodPoolField
extends RefCounted
## Physics System, blood: a bleed-out pool's fill field: the flow's cells written to a small grid,
## box-blurred so single cells at the frontier melt into their neighbours, with how far the blood
## has sunk into a porous floor beside it. The 3D render's pool (`pool_ink.gd`) cuts it into a
## decal; this holds only the field's numbers.

## Box-blur passes over the fill field, melting single frontier cells into their neighbours.
const BLUR_PASSES := 2
## Empty cells around the claimed ones, so the blur and the outline have room at the edge.
const PAD := 3


## The cells the field spans: every `covered` cell and `PAD` empty ones round them (`pool_ink.gd`
## lays its picture over it).
static func field_box(covered: Array) -> Rect2i:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in covered:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	lo -= Vector2i(PAD, PAD)
	hi += Vector2i(PAD, PAD)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## The field over `box` as RG8 bytes: red = the fill, box-blurred; green = how far the blood has
## sunk in (left at cell resolution; the texture filtering smooths it, and the shader soaks it in
## tuft by tuft).
static func field_bytes(flow: BloodFlow, covered: Array, box: Rect2i) -> PackedByteArray:
	var lo := box.position
	var w := box.size.x
	var field := PackedFloat32Array()
	field.resize(w * box.size.y)
	for c in covered:
		field[(c.y - lo.y) * w + (c.x - lo.x)] = flow.fill(c)
	for pass_i in BLUR_PASSES:
		field = _box_blur(field, w, box.size.y)
	var bytes := PackedByteArray()
	bytes.resize(field.size() * 2)
	for i in field.size():
		bytes[i * 2] = int(clampf(field[i], 0.0, 1.0) * 255.0)
	if flow.has_porous():
		for c in flow.cells:
			bytes[((c.y - lo.y) * w + (c.x - lo.x)) * 2 + 1] = int(
				clampf(flow.soak_level(c), 0.0, 1.0) * 255.0,
			)
	return bytes


## One 3x3 box-blur pass (edges read as empty), as the sum of each cell's three-cell row sums above,
## at and below it. The row sums are kept in doubles: a sum of float32 fills is exact in a double,
## so the nine-cell sum, and the field, are the same whatever the order they are added in.
static func _box_blur(src: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array:
	var rows := PackedFloat64Array()
	rows.resize(w * h)
	for y in h:
		var i := y * w
		for x in range(1, w - 1):
			rows[i + x] = src[i + x - 1] + src[i + x] + src[i + x + 1]
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in range(1, h - 1):
		var i := y * w
		for x in range(1, w - 1):
			out[i + x] = (rows[i + x - w] + rows[i + x] + rows[i + x + w]) / 9.0
	return out
