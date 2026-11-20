extends Node2D
## Physics System, blood: a dead body's bleed-out pool: a BloodFlow flood-fill claims grid cells in
## per-frame batches, wrapping around walls and furniture into one continuous irregular puddle, then
## a front eases outward through them over the bleed-out duration. Started by `seed_bleed_out` at
## the point the body's blood leaves it. Despawner-tracked. It owns the fill only; the 3D render
## shows it (`pool_ink.gd`, told by `PhysicsFxHook.pool_changed`).

## Flow cells claimed per physics frame.
const FLOW_CLAIMS_PER_FRAME := 60

## The flood-fill (the 3D pool shows its cells).
var flow: BloodFlow
## The cell budget the flow may claim (porous cells cost more), and the seconds its front takes to
## sweep them.
var _budget := 0.0
var _flow_duration := 1.0


func _physics_process(delta: float) -> void:
	# Claim the cells a batch per frame (each costs a collider query), then sweep the front.
	if _claiming():
		flow.step(
			FLOW_CLAIMS_PER_FRAME,
			TwinSpace.space_of(self),
			global_position,
			_budget,
		)
	else:
		flow.advance(delta, _flow_duration)
	flow.tick(delta)
	PhysicsFxHook.pool_changed(self)
	if not _claiming() and flow.settled() and not flow.soaking():
		set_physics_process(false)


## Start the pool: `cells` grid cells flowing out from its origin and leaning a random way, filling
## in over `duration` seconds once claimed. `exclude` is the body's twin RID(s), which the flow
## ignores.
func seed_bleed_out(cells: int, duration: float, exclude: Array) -> void:
	flow = BloodFlow.new(Vector2.RIGHT.rotated(randf() * TAU), exclude)
	BloodField.add_pool(self)
	_budget = cells
	_flow_duration = duration
	set_physics_process(true)


## Whether the flow still has cells to claim: budget left and somewhere to flow.
func _claiming() -> bool:
	return flow.budget_used() < _budget and not flow.done()


## Blood dragged out of the pool to world `pos` at `level` 0..1 (a smear): grows its outline there.
func drag_out(pos: Vector2, level: float) -> void:
	if flow == null:
		return
	flow.add_trail(
		Vector2i(((pos - global_position) / BloodPoolConfig.flow_cell_size).floor()),
		level,
	)
	PhysicsFxHook.pool_changed(self)
