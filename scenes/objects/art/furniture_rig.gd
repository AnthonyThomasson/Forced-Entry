class_name FurnitureRig
extends Node3D
## Objects domain, the 3D body of one furniture piece (#193 phase 2, `domain-art/mesh-hook.md`):
## its shared mesh on a child, and the little state a piece has that changes its look. The rig
## costs nothing per frame (it has no `mirror_update` and no `_process`); a state changes it:
##   - **damage.** The 2D piece darkens by the damage it has taken (`Deformation.darken`); the rig
##     tints its solids the same, written when the piece's `Deformable` records an impact.
##   - **light.** A part that gives light (a lamp's bulb, a screen, a hot ring) is a glow node
##     (`add_glow`, with a strength of its own): lit by default, `set_lit` switches every glow and
##     brings each back to its own strength (written only on change) with no real light, which is
##     phase 3's. Nothing calls `set_lit` in play until the lighting job lets a piece switch off.
## A bed has its own rig (`FurnitureBedRig`) that reads who lies on it.

## The solids' node (the piece's shared mesh).
var body: MeshInstance3D
## The piece's `Deformable` (null for a piece with none): the rig follows its dents.
var deformable: Deformable
## The glow nodes, the colour and strength each glows with; `lit` says whether they glow now.
var glows: Array[MeshInstance3D] = []
var lit := true
var _glow_colors: Array[Color] = []
var _glow_strengths: Array[float] = []
## The tint the solids carry now (white: undamaged).
var _tint := Color.WHITE
## Every solid that takes the damage tint (the body and any part added by `add_part`).
var _solids: Array[MeshInstance3D] = []


## Show `mesh` as the body of `piece`'s rig and follow the piece's dents.
func with_body(piece: Node2D, mesh: Mesh) -> FurnitureRig:
	body = MeshNodes.instance(mesh)
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
	MeshNodes.glow(node, color, own if lit else 0.0)
	add_child(node)
	glows.append(node)
	_glow_colors.append(color)
	_glow_strengths.append(own)
	return node


## Light or darken every glow part, each back at its own strength (written only when `on` differs
## from now). No piece calls it in play yet: the lighting job's switch.
func set_lit(on: bool) -> void:
	if on == lit:
		return
	lit = on
	for i in glows.size():
		MeshNodes.glow(glows[i], _glow_colors[i], _glow_strengths[i] if on else 0.0)


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
		solid.set_instance_shader_parameter(&"base_color", tinted)
