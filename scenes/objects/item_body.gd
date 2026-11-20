class_name ItemBody
extends PieceBody
## Objects domain, the free 3D body of a small item (#194 stack-a, D20, `docs/stacked-items.md`): a
## `PieceBody` (a plate, a cup, a book, a box: it rests on the floor or on a flat top, settles
## asleep, slides, tips and falls as Jolt decides) that a walker steps over while it lies no higher
## than a step. While its top is within `DoorFallConfig.step_over` (10 px) it does not collide with
## a character (a walker passes it and it stays: nothing pushes it) and its footprint is no hole in
## the nav bake (`PieceRest.walk_over`); a vehicle, a round, a blast and a fall still move
## it. Taller (a box, a crate, a lamp) or up on a table it is an obstacle like any piece, and a
## walker shoves it by today's rules (`Knockback.push`).

## The mask it has while it is not walk-over (a piece's), and whether it is walk-over now.
var _full_mask := 0
var _flat := false


func _init(item: Node2D = null, weight := -1.0) -> void:
	super(item, weight)
	_full_mask = collision_mask


## The twin space takes the piece over: walk-over is decided from where it starts.
func take_over(footprint: Node2D) -> void:
	super.take_over(footprint)
	_step(footprint)


## The footprint follows: walk-over is decided again.
func twin_update(footprint: Node2D) -> void:
	super.twin_update(footprint)
	_step(footprint)


## Whether the item is walk-over now: its highest point within a step of the floor.
func walk_over() -> bool:
	return _extent().y / RenderConfig.unit <= DoorFallConfig.step_over


## Walk-over is decided again, and the character taken out of (or put back into) what it collides
## with, and the footprint told.
func _step(footprint: Node2D) -> void:
	var flat := walk_over()
	var rest: Variant = footprint.get(&"rest") if footprint != null else null
	if rest is PieceRest:
		(rest as PieceRest).walk_over = flat
	if flat != _flat:
		_flat = flat
		collision_mask = _full_mask & ~PhysicsLayers.TWIN_CHARACTER if flat else _full_mask
