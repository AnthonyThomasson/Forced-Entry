class_name FurnitureRig
extends Node3D
## Objects domain, the 3D body of one furniture piece (`domain-art/mesh-hook.md`):
## its shared mesh on a child, and the little state a piece has that changes its look. The rig
## costs nothing per frame (it has no `mirror_update` and no `_process`); a state changes it:
##   - **damage.** The 2D piece darkens by the damage it has taken (`Deformation.darken`); the rig
##     tints its solids the same, written when the piece's `Deformable` records an impact.
##   - **light.** A part that gives light (a lamp's bulb, a screen, a hot ring) is a glow node
##     (`add_glow`, with a strength of its own): lit by default, `set_lit` switches every glow and
##     brings each back to its own strength (written only on change); `set_glow_level` dims every
##     glow by a factor (the Lighting domain's rhythm of the piece's light: a failing tube, a
##     blinking sign), also written only on change.
## A bed has its own rig (`FurnitureBedRig`) that reads who lies on it.

## The solids' node (the piece's shared mesh).
var body: MeshInstance3D
## The piece's `Deformable` (null for a piece with none): the rig follows its dents.
var deformable: Deformable
## Whether the piece hangs on the wall behind its footprint (a wall stain, a menu board, a mirror):
## the 3D wall fade (Art, duck-typed) then fades it with that wall instead of by its own place.
var hangs_on_wall := false
## The glow nodes, the colour and strength each glows with; `lit` says whether they glow now.
var glows: Array[MeshInstance3D] = []
var lit := true
## How much of its own strength each glow shows (1: all of it).
var glow_level := 1.0
var _glow_colors: Array[Color] = []
var _glow_strengths: Array[float] = []
## The tint the solids carry now (white: undamaged).
var _tint := Color.WHITE
## Every solid that takes the damage tint (the body and any part added by `add_part`).
var _solids: Array[MeshInstance3D] = []
## The art the solids wear (`FurnitureArt.of`: `{ texture, rect }`; empty for a piece with none).
var _art: Dictionary = {}


## Show `mesh` as the body of `piece`'s rig and follow the piece's dents.
func with_body(piece: Node2D, mesh: Mesh) -> FurnitureRig:
	_art = FurnitureArt.of(FurnitureSpec.of(piece))
	body = MeshNodes.instance(mesh)
	_dress(body)
	body.name = "Body"
	add_child(body)
	_solids.append(body)
	var physics: Variant = piece.get("physics")
	var found: Variant = null if physics == null else (physics as Object).get("deformable")
	if found is Deformable:
		deformable = found
		deformable.changed.connect(_dented)
		_dented()
	return self


## A part of the piece on its own node (a bed's blanket), shown by `mesh` at `at` (px), tinted by
## damage like the body.
func add_part(part_name: String, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var part := MeshNodes.instance(mesh, _tint)
	part.name = part_name
	_dress(part)
	MeshNodes.place(part, at)
	add_child(part)
	_solids.append(part)
	return part


## A glow node of `mesh` (the piece's light-giving parts, their own colours in the mesh), glowing
## `color` at `strength` (a negative one: `ObjectMeshStateConfig.glow_strength`) while the rig is
## lit.
func add_glow(mesh: Mesh, color: Color, strength := -1.0) -> MeshInstance3D:
	var node := MeshNodes.instance(mesh, Color.WHITE, false)
	node.name = "Glow"
	var own := strength if strength >= 0.0 else ObjectMeshStateConfig.glow_strength
	MeshNodes.glow(node, color, own * glow_level if lit else 0.0)
	add_child(node)
	glows.append(node)
	_glow_colors.append(color)
	_glow_strengths.append(own)
	return node


## Light or darken every glow part, each back at its own strength (written only when `on` differs
## from now).
func set_lit(on: bool) -> void:
	if on == lit:
		return
	lit = on
	for i in glows.size():
		MeshNodes.glow(glows[i], _glow_colors[i], _glow_strengths[i] * glow_level if on else 0.0)


## Show every glow at `level` (0 to 1.1) of its own strength: the rhythm of the piece's light
## dims the glow with it. Written only when the level changed.
func set_glow_level(level: float) -> void:
	if is_equal_approx(level, glow_level):
		return
	glow_level = level
	if not lit:
		return
	for i in glows.size():
		MeshNodes.glow(glows[i], _glow_colors[i], _glow_strengths[i] * level)


## Put the piece's 2D art on `solid` (the toon's textured material; a piece with no art keeps the
## shared one): the art is projected straight down, so a part raised on its own node wears the same.
func _dress(solid: MeshInstance3D) -> void:
	if not _art.is_empty():
		MeshNodes.textured(solid, _art["texture"], _art["rect"])


## The damage tint the solids carry now.
func tint() -> Color:
	return _tint


## The piece took a hit: tint every solid as the 2D piece darkens (written only when it changed).
func _dented() -> void:
	var tinted := Color.WHITE.darkened(Deformation.darken(deformable.damage_total))
	if tinted == _tint:
		return
	_tint = tinted
	for solid in _solids:
		MeshNodes.base_color(solid, tinted)
