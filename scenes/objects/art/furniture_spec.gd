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
## Clockwise quarter turns from the canonical front (+y) to the piece's facing (0 to 3).
var turns := 0


## The spec of `piece` (an `EnvironmentObject`: `size`, `color`, `look`), read duck-typed.
static func of(piece: Node2D) -> FurnitureSpec:
	var spec := FurnitureSpec.new()
	var body_size: Vector2 = piece.get("size")
	spec.color = ObjectArt.drawn_color(piece.get("color"))
	var look: Variant = piece.get("look")
	var facing := Vector2.DOWN
	if look is Object:
		var options: Variant = (look as Object).get("art_opts")
		spec.opts = options if options is Dictionary else {}
		var face: Variant = (look as Object).get("facing")
		facing = face if face is Vector2 else Vector2.DOWN
	spec.turns = posmod(roundi(Vector2.DOWN.angle_to(facing) / (PI * 0.5)), 4)
	spec.size = Vector2(body_size.y, body_size.x) if spec.turns % 2 == 1 else body_size
	return spec


## `size` halved: where the footprint's edges lie from the centre.
func half() -> Vector2:
	return size * 0.5


## The rectangle at (`x`, `y`) from the footprint's back-left corner, `w` wide and `h` deep, in the
## frame centred on the piece: a painter's own coordinates, in px.
func area(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(Vector2(x, y) - half(), Vector2(w, h))


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
