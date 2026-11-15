class_name FurnitureSpec
extends RefCounted
## Objects domain, what a furniture mesh is built from (#193 phase 2, `domain-art/meshes.md`): one
## piece's footprint in its painter's canonical frame (front toward +y, width across the front),
## the colour its painter draws it in, its painter options and the quarter turns that take the
## canonical front onto the piece's facing. The 2D art is painted canonical and turned
## (`PixelArt.render`); a mesh is built the same way, in the canonical frame, then turned by
## `kit()`'s pose, so one mesh serves a piece at any facing and a sofa against the left wall is the
## sofa against the back wall, turned.
##
## A builder reads only this (never the piece), so what a mesh depends on is what its cache key
## names: `FurnitureMesh.fetch`.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

## The footprint (px) in the canonical frame: the piece's `size`, its sides swapped for a piece
## facing left or right.
var size := Vector2.ZERO
## The colour the painter draws in: the piece's colour in the run-down grade.
var color := Color.WHITE
## The painter's options (`look.art_opts`).
var opts: Dictionary = {}
## The painter's id (`look.art`) and the surface finish it is drawn in (`object_material`): what
## the piece's flat texture is painted from (`FurnitureArt`).
var art := ""
var material := ""
## The piece's own colour, not yet run down (`ObjectArt` grades the colour it paints in).
var paint := Color.WHITE
## Clockwise quarter turns from the canonical front (+y) to the piece's facing (0 to 3).
var turns := 0
## The part that reaches beyond the footprint (a streetlight's arm and head, an awning), in the
## canonical frame centred on the piece's origin: its size and where it lies from the origin,
## `reach` px out toward the front. Empty for a piece with none.
var overhang := Rect2()


## The spec of `piece` (an `EnvironmentObject`: `size`, `color`, `look`), read duck-typed.
static func of(piece: Node2D) -> FurnitureSpec:
	var spec := FurnitureSpec.new()
	var body_size: Vector2 = piece.get("size")
	spec.paint = piece.get("color")
	spec.color = ObjectArt.drawn_color(spec.paint)
	var look: Variant = piece.get("look")
	var facing := Vector2.DOWN
	if look is Object:
		var options: Variant = (look as Object).get("art_opts")
		spec.opts = options if options is Dictionary else {}
		var face: Variant = (look as Object).get("facing")
		facing = face if face is Vector2 else Vector2.DOWN
	spec.art = String(look.get("art")) if look is Object else ""
	var finish: Variant = piece.get("object_material")
	spec.material = String(finish) if finish != null else ""
	spec.turns = posmod(roundi(Vector2.DOWN.angle_to(facing) / (PI * 0.5)), 4)
	spec.size = Vector2(body_size.y, body_size.x) if spec.turns % 2 == 1 else body_size
	spec._read_overhang(piece)
	return spec


## The canonical overhang of `piece` (its `look.overhang_rect()` turned back to the canonical
## front), read once: the part reaches out along the facing, `reach` px to its centre.
func _read_overhang(piece: Node2D) -> void:
	var look: Variant = piece.get("look")
	if not look is Object or not (look as Object).has_method(&"overhang_rect"):
		return
	var rect: Rect2 = (look as Object).call(&"overhang_rect")
	if not rect.has_area():
		return
	var across := Vector2(rect.size.y, rect.size.x) if turns % 2 == 1 else rect.size
	var reach := rect.get_center().length()
	overhang = Rect2(Vector2(-across.x * 0.5, reach - across.y * 0.5), across)


## `size` halved: where the footprint's edges lie from the centre.
func half() -> Vector2:
	return size * 0.5


## The rectangle at (`x`, `y`) from the footprint's back-left corner, `w` wide and `h` deep, in the
## frame centred on the piece: a painter's own coordinates, in px.
func area(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(Vector2(x, y) - half(), Vector2(w, h))


## `rect` (px from the footprint's back-left corner) in the frame centred on the piece: `area` for a
## rectangle already in hand.
func within(from: Rect2) -> Rect2:
	return area(from.position.x, from.position.y, from.size.x, from.size.y)


## The rectangle at (`x`, `y`) from the overhang's back-left corner, `w` wide and `h` deep, in the
## frame centred on the piece (the overhang painter's own coordinates, in px).
func over_area(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(overhang.position + Vector2(x, y), Vector2(w, h))


## A deterministic random stream for a mesh's scattered detail (rubble, litter, a heap of bags):
## seeded by the footprint, the colour, the options the shape reads (`names`, as `read`) and `salt`,
## so a piece of one look is one mesh, and an option the shape never reads does not change it.
func rng(salt: String, names: Array) -> RandomNumberGenerator:
	var made := RandomNumberGenerator.new()
	made.seed = hash([size, color.to_html(), var_to_str(read(names)), salt])
	return made


## A kit that turns what is added to it to the piece's facing.
func kit() -> MeshKit:
	var made := MeshKit.new()
	level(made)
	return made


## Pose `kit` for the solids added next: `local` (px, in the canonical frame; the identity for none)
## turned to the piece's facing. A turn of none leaves the kit unposed.
func level(kit_to_pose: MeshKit, local := Transform3D.IDENTITY) -> void:
	if turns == 0:
		kit_to_pose.pose(local)
	else:
		kit_to_pose.pose(Transform3D(Basis(Vector3.UP, -turns * PI * 0.5), Vector3.ZERO) * local)


## An ellipse inscribed in `rect` (px) of `sides` corners, for `MeshKit.extrude`.
static func ellipse(rect: Rect2, sides := 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	var centre := rect.get_center()
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		out.append(centre + Vector2(cos(angle), sin(angle)) * rect.size * 0.5)
	return out


## A rectangle `rect` (px) with its corners rounded by `radius`, of `steps` segments a corner, for
## `MeshKit.extrude`: a rounded box, a pad.
static func rounded(rect: Rect2, radius: float, steps := 3) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	if r < 0.05:
		return PackedVector2Array([
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		])
	var centres := [
		rect.end - Vector2(r, r),
		Vector2(rect.position.x + r, rect.end.y - r),
		rect.position + Vector2(r, r),
		Vector2(rect.end.x - r, rect.position.y + r),
	]
	var out := PackedVector2Array()
	for i in 4:
		for k in steps + 1:
			var angle := (float(i) + float(k) / float(steps)) * PI * 0.5
			out.append((centres[i] as Vector2) + Vector2(cos(angle), sin(angle)) * r)
	return out


## Every value in `opts` named by `names` (`opts.get(name)` or `fallbacks[name]`), the options a
## shape reads, as a dictionary for the cache key.
func read(names: Array, fallbacks: Dictionary = {}) -> Dictionary:
	var out := {}
	for name: String in names:
		out[name] = opts.get(name, fallbacks.get(name))
	return out


## The four strips of `whole` around `hole` (a rectangle inside it): left, right, back, front.
static func ring(whole: Rect2, hole: Rect2) -> Array[Rect2]:
	return [
		Rect2(whole.position, Vector2(hole.position.x - whole.position.x, whole.size.y)),
		Rect2(
			Vector2(hole.end.x, whole.position.y),
			Vector2(whole.end.x - hole.end.x, whole.size.y),
		),
		Rect2(hole.position.x, whole.position.y, hole.size.x, hole.position.y - whole.position.y),
		Rect2(hole.position.x, hole.end.y, hole.size.x, whole.end.y - hole.end.y),
	]
