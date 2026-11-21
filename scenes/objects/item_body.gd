class_name ItemBody
extends PieceBody
## Objects domain, the free 3D body of a small item (#194 stack-a, D20, `docs/stacked-items.md`): a
## `PieceBody` (a plate, a cup, a book, a box: it rests on the floor or on a flat top, settles
## asleep, slides, tips and falls as Jolt decides) that a walker steps over while it lies no higher
## than a step. While its top is within `DoorFallConfig.step_over` (10 px) it lies on
## `PhysicsLayers.TWIN_WALKOVER` and ignores characters: a walker passes it and it stays, nothing
## pushes it (a character body tests its own mask against the other's layer, so the layer, not the
## item's mask, is what lets it by), and its footprint is no hole in the nav bake
## (`PieceRest.walk_over`). A round (`TWIN_ALL`), a blast and a fall (`TWIN_SURFACES`) still meet
## it; a vehicle's body does not (its mask has no `TWIN_WALKOVER`, and the item's has no
## `TWIN_VEHICLE`
## while it lies flat): a car drives over a flat item, no strike and no flick. A
## free item that falls onto it rests on it (an item's mask has
## `TWIN_WALKOVER`: a book falls onto a plate on the floor). Taller (a box, a crate, a lamp) or up
## on a table it is an obstacle like any piece, and a walker shoves it by today's rules
## (`Knockback.push`).

## What a walk-over item leaves out of its mask: a walker and a vehicle pass over it, whoever's mask
## it is (a vehicle's body would otherwise meet the item's own mask and flick it).
const _PASSED := PhysicsLayers.TWIN_CHARACTER | PhysicsLayers.TWIN_VEHICLE

## The mask it has while it is not walk-over (a piece's, and what lies flat), and whether it is
## walk-over now.
var _full_mask := 0
var _flat := false


func _init(item: Node2D = null, weight := -1.0) -> void:
	super(item, weight)
	_full_mask = collision_mask | PhysicsLayers.TWIN_WALKOVER
	collision_mask = _full_mask


## The twin space takes the piece over: walk-over is decided from where it starts.
func take_over(footprint: Node2D) -> void:
	super.take_over(footprint)
	_step(footprint)


## The footprint follows: walk-over is decided again.
func twin_update(footprint: Node2D) -> void:
	super.twin_update(footprint)
	_step(footprint)


## Whether the item lies on the walk-over layer now (what the last step decided).
func is_flat() -> bool:
	return _flat


## Whether the item is walk-over now: its highest point within a step of the floor.
func walk_over() -> bool:
	return _extent().y / RenderConfig.unit <= DoorFallConfig.step_over


## Walk-over is decided again: the item put on the walk-over layer and out of what a character is
## met by (or back on `TWIN_WORLD`), and the footprint told.
func _step(footprint: Node2D) -> void:
	var flat := walk_over()
	var rest: Variant = footprint.get(&"rest") if footprint != null else null
	if rest is PieceRest:
		(rest as PieceRest).walk_over = flat
	if flat != _flat:
		_flat = flat
		collision_layer = PhysicsLayers.TWIN_WALKOVER if flat else PhysicsLayers.TWIN_WORLD
		collision_mask = _full_mask & ~_PASSED if flat else _full_mask
