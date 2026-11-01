extends Node2D
## Physics System, blood: a dead body's bleed-out pool: a BloodFlow flood-fill claims grid cells in
## per-frame batches, wrapping around walls and furniture into one continuous irregular puddle, then
## a front eases outward through them over the bleed-out duration. Started by `seed_bleed_out` at
## the point the body's blood leaves it. Despawner-tracked. Drawing lives in blood_pool_visuals.gd;
## this control node owns the fill only.

const Visuals := preload("res://scenes/physics/blood/blood_pool_visuals.gd")
## Flow cells claimed per physics frame.
const FLOW_CLAIMS_PER_FRAME := 60

## The flood-fill (the visuals draw its cells).
var flow: BloodFlow
## The cell budget the flow may claim (porous cells cost more), and the seconds its front takes to
## sweep them.
var _budget := 0.0
var _flow_duration := 1.0
## The pool changed while the player's view did not show it, so its draw is out of date.
var _stale := false

## The draw layer child.
@onready var _visuals := $BloodPoolVisuals


func _physics_process(delta: float) -> void:
	# Claim the cells a batch per frame (each costs a collider query), then sweep the front.
	if _claiming():
		flow.step(
			FLOW_CLAIMS_PER_FRAME,
			get_world_2d().direct_space_state,
			global_position,
			_budget,
		)
	else:
		flow.advance(delta, _flow_duration)
	flow.tick(delta)
	_redraw()
	# A pool out of date waits to be seen, so it keeps watching (cheaply) for the view to reach it.
	if not _claiming() and flow.settled() and not flow.soaking() and not _stale:
		set_physics_process(false)


## Start the pool: `cells` grid cells flowing out from its origin and leaning a random way, filling
## in over `duration` seconds once claimed. `exclude` is the body's RID(s), which the flow ignores.
func seed_bleed_out(cells: int, duration: float, exclude: Array) -> void:
	flow = BloodFlow.new(Vector2.RIGHT.rotated(randf() * TAU), exclude)
	BloodField.add_pool(self)
	_budget = cells
	_flow_duration = duration
	set_physics_process(true)


## Whether the flow still has cells to claim: budget left and somewhere to flow.
func _claiming() -> bool:
	return flow.budget_used() < _budget and not flow.done()


## Blood dragged out of the pool to world `pos` at `level` 0..1 (a smear): grows its outline there,
## drawn by the pool itself.
func drag_out(pos: Vector2, level: float) -> void:
	if flow == null:
		return
	flow.add_trail(
		Vector2i(((pos - global_position) / BloodPoolConfig.flow_cell_size).floor()),
		level,
	)
	_redraw()


## Redraw the pool, unless it lies wholly outside what the player's view shows live
## (`SeenArea`): then its draw is left out of date until the view reaches it (the pool keeps
## growing, and what is seen later is drawn whole).
func _redraw() -> void:
	if _seen():
		_stale = false
		_visuals.queue_redraw()
		return
	_stale = true
	set_physics_process(true)


## Whether the pool's drawing, the box of cells it covers and the blur round them, reaches what the
## player's view shows.
func _seen() -> bool:
	var size := BloodPoolConfig.flow_cell_size
	var box := flow.extent()
	var pad := Vector2.ONE * size * Visuals.PAD
	var rect := Rect2(Vector2(box.position) * size - pad, Vector2(box.size) * size + pad * 2.0)
	return SeenArea.reaches(to_global(rect.get_center()), rect.size.length() * 0.5)
