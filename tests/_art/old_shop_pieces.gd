extends RefCounted
## The old look of the shops' and special rooms' whole pieces: the 3D mesh and the flat art each had
## before #194 made their stock free items (commit 08f43a10's `shop_mesh`, `noodle_mesh`,
## `clinic_mesh`, `tech_mesh` and their painters, kept beside it as `old_*.gd`), an oracle for the
## test that sets the old piece and the new one side by side (`art/shop_pieces_lit_windowed`).
## `rig` builds the old piece the way its mesh builder did, wearing the old painter's art (the
## till, the bowls, the glass and the stock drawn on it). Nothing in scenes/ reads this.

const MESHES := {
	"shop": preload("res://tests/_art/old_shop_mesh.gd"),
	"noodle": preload("res://tests/_art/old_noodle_mesh.gd"),
	"clinic": preload("res://tests/_art/old_clinic_mesh.gd"),
	"tech": preload("res://tests/_art/old_tech_mesh.gd"),
}
const PAINTERS := {
	"shop": preload("res://tests/_art/old_shop_painter.gd"),
	"noodle": preload("res://tests/_art/old_noodle_painter.gd"),
	"clinic": preload("res://tests/_art/old_clinic_painter.gd"),
	"tech": preload("res://tests/_art/old_tech_painter.gd"),
}


## Whether `art` (a painter id) has an old look here.
static func has(art: String) -> bool:
	return MESHES.has(art)


## The old 3D look of `piece` (a furniture piece at its canonical facing): the old mesh in a rig,
## the old painter's flat art on its solids, origin at the piece's origin, in 3D units.
static func rig(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var made: Node3D = MESHES[spec.art].build(piece)
	var opts := spec.opts.merged({ "material": spec.material }, true)
	var texture := PixelArt.render_flat(PAINTERS[spec.art], spec.size, spec.color, opts)
	var body: Variant = made.get("body")
	if body is MeshInstance3D:
		MeshNodes.textured(body, texture, Rect2(-spec.size * 0.5, spec.size))
	return made
